// ScreenLapsePro
// Core/CaptureEngine.swift
// SCStream wrapper that captures screen frames and forwards them to a delegate

import Foundation
import AppKit
import ScreenCaptureKit
import CoreMedia

// MARK: - Delegate Protocol

/// Receives events from a running CaptureEngine.
protocol CaptureEngineDelegate: AnyObject {
    /// Called on an unspecified background queue for each complete video frame.
    func captureEngine(_ engine: CaptureEngine, didOutputVideoFrame sampleBuffer: CMSampleBuffer)
    /// Called when the underlying SCStream stops (either normally or on error).
    func captureEngineDidStop(_ engine: CaptureEngine)
}

// MARK: - CaptureEngine

/// Wraps `SCStream` to capture screen content and deliver CMSampleBuffers to a delegate.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {

    // MARK: State

    private(set) var stream: SCStream?
    weak var delegate: CaptureEngineDelegate?

    // MARK: Start

    /// Builds an `SCStream` configured for the given filter and frame rate, then starts capture.
    ///
    /// - Parameters:
    ///   - filter: The display or window to capture.
    ///   - fps: Target capture frame rate for normal recording.
    ///   - isTimeLapse: When `true`, the capture frame rate is reduced by `timeLapseMultiplier`
    ///     so that the engine delivers fewer frames per second.
    ///   - timeLapseMultiplier: Speed factor; the capture interval becomes `multiplier/30` seconds.
    func start(filter: SCContentFilter,
               fps: Int,
               isTimeLapse: Bool,
               timeLapseMultiplier: Int) async throws {

        let config = SCStreamConfiguration()

        // Pixel format: 32-bit BGRA – compatible with HEVC encoding via VideoToolbox.
        config.pixelFormat = kCVPixelFormatType_32BGRA

        // Derive capture dimensions from the content filter's rectangle.
        // pointPixelScale and contentRect are macOS 14+; fall back to Retina defaults on 13.
        let rect: CGRect
        let scale: CGFloat
        if #available(macOS 14.0, *) {
            scale = CGFloat(filter.pointPixelScale)
            rect  = filter.contentRect
        } else {
            scale = 2.0
            rect  = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        let width  = max(2, Int(rect.width  * scale))
        let height = max(2, Int(rect.height * scale))

        config.width  = width
        config.height = height

        // Capture interval.
        if isTimeLapse {
            // Capture at 30/multiplier fps; e.g. 15× → 2 fps (interval = 15/30 s).
            config.minimumFrameInterval = CMTime(
                value:     CMTimeValue(timeLapseMultiplier),
                timescale: 30
            )
        } else {
            let clampedFPS = max(1, fps)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clampedFPS))
        }

        // Audio is not captured by this engine.
        config.capturesAudio = false

        // Cursor visibility is controlled by the Prefs value at start time.
        config.showsCursor = Prefs.showCursor

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = newStream

        try newStream.addStreamOutput(self,
                                      type: .screen,
                                      sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        try await newStream.startCapture()
    }

    // MARK: Stop

    /// Stops the running stream. Safe to call even if the stream was never started.
    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        // Only handle video frames.
        guard outputType == .screen else { return }

        // Only forward frames that are fully available.
        guard sampleBuffer.isValid else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRawValue = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else {
            return
        }

        delegate?.captureEngine(self, didOutputVideoFrame: sampleBuffer)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.captureEngineDidStop(self)
    }
}
