// ScreenLapsePro
// Core/CaptureEngine.swift
// SCStream wrapper that captures screen frames (and optionally system audio)

import Foundation
import AppKit
import ScreenCaptureKit
import CoreMedia

// MARK: - Delegate Protocol

protocol CaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: CaptureEngine, didOutputVideoFrame sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: CaptureEngine, didOutputAudioFrame sampleBuffer: CMSampleBuffer)
    func captureEngineDidStop(_ engine: CaptureEngine)
}

// Default no-op for audio so existing conformances don't break.
extension CaptureEngineDelegate {
    func captureEngine(_ engine: CaptureEngine, didOutputAudioFrame sampleBuffer: CMSampleBuffer) {}
}

// MARK: - CaptureEngine

final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {

    private(set) var stream: SCStream?
    weak var delegate: CaptureEngineDelegate?

    // MARK: Start

    func start(filter: SCContentFilter,
               fps: Int,
               isTimeLapse: Bool,
               timeLapseMultiplier: Int,
               capturesAudio: Bool = false) async throws {

        let config = SCStreamConfiguration()
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let rect: CGRect
        let scale: CGFloat
        if #available(macOS 14.0, *) {
            scale = CGFloat(filter.pointPixelScale)
            rect  = filter.contentRect
        } else {
            scale = 2.0
            rect  = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        config.width  = max(2, Int(rect.width  * scale))
        config.height = max(2, Int(rect.height * scale))

        if isTimeLapse {
            config.minimumFrameInterval = CMTime(
                value:     CMTimeValue(timeLapseMultiplier),
                timescale: 30
            )
        } else {
            let clampedFPS = max(1, fps)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clampedFPS))
        }

        config.capturesAudio = capturesAudio
        config.showsCursor   = Prefs.showCursor

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = newStream

        try newStream.addStreamOutput(self,
                                      type: .screen,
                                      sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        if capturesAudio {
            try newStream.addStreamOutput(self,
                                          type: .audio,
                                          sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
        }
        try await newStream.startCapture()
    }

    // MARK: Stop

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                             createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else { return }
            delegate?.captureEngine(self, didOutputVideoFrame: sampleBuffer)

        case .audio:
            delegate?.captureEngine(self, didOutputAudioFrame: sampleBuffer)

        case .microphone:
            // macOS 15+: we capture mic via AVCaptureSession, not SCStream
            break

        @unknown default:
            break
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        delegate?.captureEngineDidStop(self)
    }
}
