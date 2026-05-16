import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

final class VideoWriter {
    enum WriterError: Error {
        case alreadyStarted
        case createFailed(Error)
        case startSessionFailed
        case appendVideoFailed
        case appendAudioFailed
        case finalizationFailed(Error?)
    }

    struct Configuration {
        let outputURL: URL
        let width: Int
        let height: Int
        let bitrate: Int
        let qualityFactor: Float?   // non-nil = quality-based VBR (ignores bitrate); matches QuickTime
        let codec: CodecChoice
        let containerIsMOV: Bool
        let recordsAudio: Bool
        let mode: RecordingMode
    }

    private(set) var configuration: Configuration

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?

    private let writeQueue = DispatchQueue(label: "com.screenlapse.writer",
                                           qos: .userInitiated)
    private var hasStartedSession = false
    private var sessionStartPTS: CMTime?
    private var lastAcceptedSec: Double = -.infinity
    private var frameIndex: Int64 = 0
    private(set) var frameCount: Int64 = 0
    private var didFinalize = false

    init(configuration: Configuration) throws {
        self.configuration = configuration

        // ProRes is not supported in MP4 — force MOV when that codec is selected.
        let fileType: AVFileType = (configuration.containerIsMOV || configuration.codec == .proRes) ? .mov : .mp4
        do {
            self.writer = try AVAssetWriter(outputURL: configuration.outputURL,
                                            fileType: fileType)
        } catch {
            throw WriterError.createFailed(error)
        }

        let videoSettings: [String: Any]
        switch configuration.codec {
        case .proRes:
            // ProRes 4444: stores RGBA pixel data without any YCbCr conversion,
            // so Display P3 / wide-colour content is preserved bit-for-bit.
            // Hardware-accelerated on Apple Silicon. Requires MOV container.
            videoSettings = [
                AVVideoCodecKey: AVVideoCodecType.proRes4444,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
                AVVideoAllowWideColorKey: true
            ]
        case .hevc, .h264:
            let avCodec: AVVideoCodecType = configuration.codec == .hevc ? .hevc : .h264
            let profileLevel: String = configuration.codec == .hevc
                ? (kVTProfileLevel_HEVC_Main_AutoLevel as String)
                : (kVTProfileLevel_H264_High_AutoLevel as String)

            // Quality-based VBR (Max preset) vs fixed average bitrate.
            // "Quality" key = kVTCompressionPropertyKey_Quality; 1.0 tells the
            // hardware encoder to use whatever bitrate is needed — this is how
            // QuickTime screen recording works on Apple Silicon.
            var compressionProps: [String: Any] = [
                AVVideoProfileLevelKey: profileLevel,
                AVVideoExpectedSourceFrameRateKey: Int(RecordingMode.playbackFPS),
                AVVideoMaxKeyFrameIntervalKey: Int(RecordingMode.playbackFPS) * 2,
                AVVideoAllowFrameReorderingKey: false
            ]
            if let qf = configuration.qualityFactor {
                compressionProps["Quality"] = qf
            } else {
                compressionProps[AVVideoAverageBitRateKey] = configuration.bitrate
            }

            // AVVideoAllowWideColorKey tells the encoder to read the colour-space
            // metadata attached to each BGRA pixel buffer by SCStream and encode
            // accordingly (P3 on a wide-colour display, sRGB otherwise). Without
            // this, the encoder silently clips everything to BT.709 → washed out.
            videoSettings = [
                AVVideoCodecKey: avCodec,
                AVVideoWidthKey: configuration.width,
                AVVideoHeightKey: configuration.height,
                AVVideoAllowWideColorKey: true,
                AVVideoCompressionPropertiesKey: compressionProps
            ]
        }

        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: configuration.width,
            kCVPixelBufferHeightKey as String: configuration.height
        ]
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(videoInput) else {
            throw WriterError.createFailed(NSError(domain: "VideoWriter",
                                                   code: -1,
                                                   userInfo: [NSLocalizedDescriptionKey: "can't add video input"]))
        }
        writer.add(videoInput)

        if configuration.recordsAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.audioInput = aInput
            } else {
                self.audioInput = nil
            }
        } else {
            self.audioInput = nil
        }
    }

    func start() throws {
        guard writer.status == .unknown else {
            throw WriterError.alreadyStarted
        }
        guard writer.startWriting() else {
            throw WriterError.createFailed(writer.error
                                           ?? NSError(domain: "VideoWriter", code: -2))
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        writeQueue.async { [weak self] in
            self?.doAppendVideo(sampleBuffer)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        writeQueue.async { [weak self] in
            self?.doAppendAudio(sampleBuffer)
        }
    }

    private func doAppendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !didFinalize else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let inputPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard inputPTS.isValid, inputPTS != .negativeInfinity else { return }

        let pts: CMTime
        switch configuration.mode {
        case .normal:
            // Use the original PTS. We anchor the session at the first PTS below,
            // so video and audio share the same timeline (no 44-hour-file bug).
            pts = inputPTS

        case .timeLapse(let mult):
            // SCStream may ignore minimumFrameInterval — throttle manually here.
            // Drop frames that arrive too soon after the previously accepted one.
            let captureFPS = max(1, Int(RecordingMode.playbackFPS) / mult)
            let minIntervalSec = 1.0 / Double(captureFPS)
            let nowSec = CMTimeGetSeconds(inputPTS)
            if nowSec - lastAcceptedSec < minIntervalSec * 0.95 {
                return
            }
            lastAcceptedSec = nowSec
            pts = CMTime(value: frameIndex, timescale: RecordingMode.playbackFPS)
            frameIndex += 1
        }

        if !hasStartedSession {
            // For Normal mode, anchor the file's t=0 at the first video PTS so audio
            // (which arrives with absolute system-uptime PTS) lands at the right offset.
            // For Time-lapse, our synthetic PTS already starts at 0.
            let sessionStart: CMTime
            switch configuration.mode {
            case .normal:    sessionStart = pts
            case .timeLapse: sessionStart = .zero
            }
            writer.startSession(atSourceTime: sessionStart)
            sessionStartPTS = sessionStart
            hasStartedSession = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: pts) {
            frameCount += 1
        }
    }

    private func doAppendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !didFinalize, let audioInput = audioInput, hasStartedSession else { return }
        guard configuration.mode.isTimeLapse == false else { return }
        guard audioInput.isReadyForMoreMediaData else { return }

        // Drop audio samples that arrive before the session anchor (would be rejected anyway).
        let audioPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let anchor = sessionStartPTS,
           audioPTS.isValid,
           CMTimeCompare(audioPTS, anchor) < 0 {
            return
        }
        audioInput.append(sampleBuffer)
    }

    func finalize() async throws -> URL {
        guard !didFinalize else { return configuration.outputURL }
        didFinalize = true

        await writeQueue.asyncWait()

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }

        if writer.status == .completed {
            return configuration.outputURL
        } else {
            throw WriterError.finalizationFailed(writer.error)
        }
    }

    var currentFileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: configuration.outputURL.path)
        return (attrs?[.size] as? Int64) ?? 0
    }
}

private extension DispatchQueue {
    func asyncWait() async {
        await withCheckedContinuation { continuation in
            self.async { continuation.resume() }
        }
    }
}
