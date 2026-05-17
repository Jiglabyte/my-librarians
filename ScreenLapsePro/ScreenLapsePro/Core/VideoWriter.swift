// ScreenLapsePro
// Core/VideoWriter.swift
// AVAssetWriter wrapper with HEVC encoding and time-lapse PTS remapping

import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox

// MARK: - VideoWriter

/// Wraps AVAssetWriter to write HEVC video frames, with optional
/// PTS remapping for time-lapse playback.
final class VideoWriter {

    // MARK: Public Properties

    let outputURL: URL

    // MARK: Private Properties

    private let assetWriter: AVAssetWriter
    private let vwInput: AVAssetWriterInput

    private let isTimeLapse: Bool
    private let timeLapseMultiplier: Int

    /// Monotonic frame counter used to build synthetic PTS in time-lapse mode.
    private var frameIndex: Int64 = 0

    // MARK: Init

    /// - Parameters:
    ///   - outputURL: Destination file (must not yet exist).
    ///   - width: Pixel width of the video.
    ///   - height: Pixel height of the video.
    ///   - isTimeLapse: When `true`, PTS is remapped so the file plays back at real-time speed
    ///     despite having been captured at a lower frame rate.
    ///   - timeLapseMultiplier: Speed factor (5, 10, 15, 30, or 60). Ignored when `isTimeLapse` is false.
    init(outputURL: URL,
         width: Int,
         height: Int,
         isTimeLapse: Bool,
         timeLapseMultiplier: Int) throws {

        self.outputURL          = outputURL
        self.isTimeLapse        = isTimeLapse
        self.timeLapseMultiplier = timeLapseMultiplier

        // Remove any stale file at the destination.
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        // MARK: Video Settings

        // Target ~4 Mbps for 1080p; scale proportionally for other resolutions.
        let pixelCount  = width * height
        let baseBitrate = 4_000_000 // 4 Mbps at 1920×1080
        let scaledBitrate = max(500_000,
                                Int(Double(baseBitrate) * Double(pixelCount) / Double(1920 * 1080)))

        let videoSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.hevc,
            AVVideoWidthKey:  width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:              scaledBitrate,
                AVVideoExpectedSourceFrameRateKey:     30,
                AVVideoMaxKeyFrameIntervalKey:         60,
                AVVideoProfileLevelKey:                kVTProfileLevel_HEVC_Main_AutoLevel,
            ] as [String: Any],
        ]

        vwInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vwInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(vwInput) else {
            throw VideoWriterError.cannotAddInput
        }
        assetWriter.add(vwInput)
    }

    // MARK: Lifecycle

    /// Prepares the writer and begins the session at time zero.
    func start() {
        guard assetWriter.status == .unknown else { return }
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
    }

    /// Appends a video frame.  In time-lapse mode the presentation timestamp is
    /// synthetically advanced so that the resulting file plays at real-time speed.
    func appendFrame(_ sampleBuffer: CMSampleBuffer) {
        guard vwInput.isReadyForMoreMediaData else { return }
        guard assetWriter.status == .writing  else { return }

        if isTimeLapse {
            // Build a synthetic PTS at exactly 30 fps so the file plays back at normal speed.
            // The multiplier was already applied on the *capture* side (fewer frames captured),
            // so sequential frames should be 1/30 s apart in the output.
            let syntheticPTS = CMTime(value: frameIndex, timescale: CMTimeScale(30))
            frameIndex += 1

            var timingInfo = CMSampleTimingInfo(
                duration:               CMTime(value: 1, timescale: 30),
                presentationTimeStamp:  syntheticPTS,
                decodeTimeStamp:        .invalid
            )

            var remappedBuffer: CMSampleBuffer?
            let status = CMSampleBufferCreateCopyWithNewTiming(
                allocator:              kCFAllocatorDefault,
                sampleBuffer:           sampleBuffer,
                sampleTimingEntryCount: 1,
                sampleTimingArray:      &timingInfo,
                sampleBufferOut:        &remappedBuffer
            )

            if status == noErr, let buf = remappedBuffer {
                vwInput.append(buf)
            }
        } else {
            // Normal mode: use the real capture timestamp.
            vwInput.append(sampleBuffer)
        }
    }

    /// Finalises the file, waits for the writer to drain, then returns the output URL.
    @discardableResult
    func finish() async -> URL {
        vwInput.markAsFinished()
        await assetWriter.finishWriting()
        return outputURL
    }

    // MARK: Errors

    enum VideoWriterError: LocalizedError {
        case cannotAddInput

        var errorDescription: String? {
            switch self {
            case .cannotAddInput: return "AVAssetWriter could not add the video input track."
            }
        }
    }
}
