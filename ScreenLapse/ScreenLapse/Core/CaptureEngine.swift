import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics
import AppKit

final class CaptureEngine: NSObject {
    enum CaptureError: Error {
        case noContent
        case noDisplay
        case streamStartFailed(Error)
    }

    var onVideoFrame: ((CMSampleBuffer) -> Void)?
    var onAudioFrame: ((CMSampleBuffer) -> Void)?
    var onStop: ((Error?) -> Void)?

    private(set) var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.screenlapse.capture.video",
                                           qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.screenlapse.capture.audio",
                                           qos: .userInitiated)

    private(set) var pixelWidth: Int = 0
    private(set) var pixelHeight: Int = 0

    static func fetchShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false,
                                                             onScreenWindowsOnly: true)
    }

    static func backingScale(for displayID: CGDirectDisplayID) -> CGFloat {
        let screen = NSScreen.screens.first { screen in
            let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return n == displayID
        }
        return screen?.backingScaleFactor ?? 2.0
    }

    func startCapture(source: CaptureSource,
                      captureFPS: Int,
                      capturesAudio: Bool,
                      showsCursor: Bool) async throws {

        let content = try await Self.fetchShareableContent()

        let filter: SCContentFilter
        let cropRect: CGRect?
        let baseWidth: Int
        let baseHeight: Int

        // Exclude ScreenLapse itself so our popover/toolbar never appear in recordings.
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.screenlapse.app"
        let selfApps = content.applications.filter { $0.bundleIdentifier == myBundleID }

        switch source {
        case .display(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id })
                    ?? content.displays.first else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(display: display,
                                     excludingApplications: selfApps,
                                     exceptingWindows: [])
            cropRect = nil
            baseWidth = display.width
            baseHeight = display.height

        case .window(let id, _, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            cropRect = nil
            baseWidth = Int(window.frame.width)
            baseHeight = Int(window.frame.height)

        case .region(let rect, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
                    ?? content.displays.first else {
                throw CaptureError.noDisplay
            }
            filter = SCContentFilter(display: display,
                                     excludingApplications: selfApps,
                                     exceptingWindows: [])
            cropRect = rect
            // rect is in points (NSScreen coords). SCStreamConfiguration.width/height
            // are pixels, so multiply by the display's backing scale to capture at
            // native resolution on Retina.
            let scale = Self.backingScale(for: displayID)
            baseWidth = max(2, Int((rect.width * scale).rounded()))
            baseHeight = max(2, Int((rect.height * scale).rounded()))
        }

        let config = SCStreamConfiguration()
        config.width = max(2, baseWidth)
        config.height = max(2, baseHeight)
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(1, captureFPS)))
        // BGRA = raw GPU pixel values with no YCbCr color-matrix conversion.
        // Converting to YCbCr here would clip Display P3 colours into BT.709
        // gamut, causing the washed-out look. BGRA preserves every colour exactly.
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        config.showsCursor = showsCursor
        config.scalesToFit = false
        if let crop = cropRect {
            // sourceRect is in points (display coords); width/height above are pixels.
            config.sourceRect = crop
        }
        if capturesAudio {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        self.pixelWidth = config.width
        self.pixelHeight = config.height

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        do {
            try await stream.startCapture()
        } catch {
            throw CaptureError.streamStartFailed(error)
        }

        self.stream = stream
    }

    func stopCapture() async {
        guard let stream = stream else { return }
        do { try await stream.stopCapture() } catch { /* ignore */ }
        self.stream = nil
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error)
    }
}

extension CaptureEngine: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,
                                                                            createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let info = attachments.first,
                  let statusValue = info[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusValue),
                  status == .complete else {
                return
            }
            onVideoFrame?(sampleBuffer)

        case .audio:
            onAudioFrame?(sampleBuffer)

        @unknown default:
            break
        }
    }
}
