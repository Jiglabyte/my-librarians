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
    private var firstPTS: CMTime?
    private var frameIndex: Int64 = 0
    private(set) var frameCount: Int64 = 0
    private var didFinalize = false

    init(configuration: Configuration) throws {
        self.configuration = configuration

        let fileType: AVFileType = configuration.containerIsMOV ? .mov : .mp4
        do {
            self.writer = try AVAssetWriter(outputURL: configuration.outputURL,
                                            fileType: fileType)
        } catch {
            throw WriterError.createFailed(error)
        }

        let avCodec: AVVideoCodecType = configuration.codec == .hevc ? .hevc : .h264
        let profileLevel: String = configuration.codec == .hevc
            ? (kVTProfileLevel_HEVC_Main_AutoLevel as String)
            : (kVTProfileLevel_H264_High_AutoLevel as String)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: avCodec,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.bitrate,
                AVVideoProfileLevelKey: profileLevel,
                AVVideoExpectedSourceFrameRateKey: Int(RecordingMode.playbackFPS),
                AVVideoMaxKeyFrameIntervalKey: Int(RecordingMode.playbackFPS) * 2,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]

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

        let pts: CMTime
        switch configuration.mode {
        case .normal:
            if firstPTS == nil { firstPTS = inputPTS }
            pts = CMTimeSubtract(inputPTS, firstPTS ?? .zero)
        case .timeLapse:
            pts = CMTime(value: frameIndex, timescale: RecordingMode.playbackFPS)
            frameIndex += 1
        }

        if !hasStartedSession {
            writer.startSession(atSourceTime: .zero)
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
