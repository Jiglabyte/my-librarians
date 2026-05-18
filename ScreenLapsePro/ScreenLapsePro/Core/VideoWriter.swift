// ScreenLapsePro
// Core/VideoWriter.swift
// AVAssetWriter wrapper: HEVC/H.264 video + optional AAC audio tracks

import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

// MARK: - VideoWriter

/// Thread-safe via a single serial caller queue (RecordingManager.writerQueue).
/// All append* methods must be called from the same serial queue.
final class VideoWriter {

    let outputURL: URL

    private let assetWriter:      AVAssetWriter
    private let vwInput:          AVAssetWriterInput
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput:    AVAssetWriterInput?

    private let isTimeLapse:         Bool
    private let timeLapseMultiplier: Int

    private var frameIndex:    Int64 = 0
    private var sessionStarted = false   // first video frame triggers startSession

    // MARK: Init

    init(outputURL: URL,
         width: Int,
         height: Int,
         isTimeLapse: Bool,
         timeLapseMultiplier: Int,
         bitratePreset: BitratePreset = .medium,
         includeSystemAudio: Bool = false,
         includeMicAudio: Bool = false) throws {

        self.outputURL           = outputURL
        self.isTimeLapse         = isTimeLapse
        self.timeLapseMultiplier = timeLapseMultiplier

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // MARK: Video

        let pixelCount    = width * height
        let scaledBitrate = bitratePreset.bitrate(forPixelCount: pixelCount)
        let codec: AVVideoCodecType = Prefs.useHEVC ? .hevc : .h264

        var compressionProps: [String: Any] = [
            AVVideoAverageBitRateKey:          scaledBitrate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey:     60,
        ]
        if Prefs.useHEVC {
            compressionProps[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:                 codec,
            AVVideoWidthKey:                 width,
            AVVideoHeightKey:                height,
            AVVideoCompressionPropertiesKey: compressionProps,
        ]

        vwInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vwInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(vwInput) else {
            throw VideoWriterError.cannotAddInput
        }
        assetWriter.add(vwInput)

        // MARK: Audio (only in normal mode — time-lapse has synthetic video PTS, audio would desync)

        guard !isTimeLapse else { return }

        let audioSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey:   192_000,
        ]

        if includeSystemAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                systemAudioInput = input
            }
        }

        if includeMicAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(input) {
                assetWriter.add(input)
                micAudioInput = input
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard assetWriter.status == .unknown else { return }
        assetWriter.startWriting()
        // Session is started lazily on the first video frame so we use its real PTS as origin.
    }

    // MARK: - Append — Video

    func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard assetWriter.status == .writing else { return }

        // Lazily start the session using the first frame's PTS as the timeline origin.
        if !sessionStarted {
            let originPTS = isTimeLapse
                ? CMTime.zero
                : CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter.startSession(atSourceTime: originPTS)
            sessionStarted = true
        }

        guard vwInput.isReadyForMoreMediaData else { return }

        if isTimeLapse {
            // Build synthetic PTS at 30 fps so the output plays at real-time speed.
            let syntheticPTS = CMTime(value: frameIndex, timescale: 30)
            frameIndex += 1

            var timing = CMSampleTimingInfo(
                duration:              CMTime(value: 1, timescale: 30),
                presentationTimeStamp: syntheticPTS,
                decodeTimeStamp:       .invalid
            )
            var remapped: CMSampleBuffer?
            let err = CMSampleBufferCreateCopyWithNewTiming(
                allocator:              kCFAllocatorDefault,
                sampleBuffer:           sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray:      &timing,
                sampleBufferOut:        &remapped
            )
            if err == noErr, let buf = remapped {
                vwInput.append(buf)
            }
        } else {
            vwInput.append(sampleBuffer)
        }
    }

    // MARK: - Append — Audio
    // Audio is never appended in time-lapse mode (no systemAudioInput / micAudioInput set).
    // Both methods also gate on sessionStarted so no audio slips through before video starts.

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted,
              let input = systemAudioInput,
              input.isReadyForMoreMediaData,
              assetWriter.status == .writing else { return }
        input.append(sampleBuffer)
    }

    func appendMicAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted,
              let input = micAudioInput,
              input.isReadyForMoreMediaData,
              assetWriter.status == .writing else { return }
        input.append(sampleBuffer)
    }

    // MARK: - Finish

    /// Finalises the file and returns the output URL.
    /// Returns nil if the writer never started a session (no frames were appended).
    @discardableResult
    func finish() async -> URL? {
        guard sessionStarted else {
            // No frames written — discard the file.
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        vwInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()
        await assetWriter.finishWriting()
        if assetWriter.status == .failed {
            return nil
        }
        return outputURL
    }

    // MARK: - Errors

    enum VideoWriterError: LocalizedError {
        case cannotAddInput
        var errorDescription: String? { "AVAssetWriter could not add the video input track." }
    }
}
