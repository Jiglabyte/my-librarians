import Foundation
import Combine
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import AppKit

@MainActor
final class RecordingManager: ObservableObject {

    // MARK: - Published state for SwiftUI

    @Published var mode: RecordingMode = .normal(fps: 30)
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isPreparing = false

    @Published var elapsedSeconds: TimeInterval = 0
    @Published var capturedFrames: Int64 = 0
    @Published var currentFileSize: Int64 = 0
    @Published var lastRecordingURL: URL?
    @Published var errorMessage: String?

    @Published var availableSources: [CaptureSource] = []
    @Published var selectedSource: CaptureSource? = nil

    // MARK: - User-tunable settings

    @AppStorage("ScreenLapse.quality") var qualityRaw: String = QualityPreset.max.rawValue
    @AppStorage("ScreenLapse.codec") var codecRaw: String = CodecChoice.hevc.rawValue
    @AppStorage("ScreenLapse.resolution") var resolutionRaw: String = OutputResolution.native.rawValue
    @AppStorage("ScreenLapse.useMOV") var useMOV: Bool = false
    @AppStorage("ScreenLapse.captureSystemAudio") var captureSystemAudio: Bool = true
    @AppStorage("ScreenLapse.captureMic") var captureMic: Bool = false
    @AppStorage("ScreenLapse.captureWebcam") var captureWebcam: Bool = false
    @AppStorage("ScreenLapse.webcamCornerRaw") var webcamCornerRaw: String = WebcamCorner.bottomRight.rawValue
    @AppStorage("ScreenLapse.webcamRelativeHeight") var webcamRelativeHeight: Double = 0.22
    @AppStorage("ScreenLapse.highlightClicks") var highlightClicks: Bool = false
    @AppStorage("ScreenLapse.showsCursor") var showsCursor: Bool = true
    @AppStorage("ScreenLapse.countdownSeconds") var countdownSeconds: Int = 3
    @AppStorage("ScreenLapse.outputFolderPath") var outputFolderPath: String = ""

    var quality: QualityPreset {
        get { QualityPreset(rawValue: qualityRaw) ?? .medium }
        set { qualityRaw = newValue.rawValue }
    }

    var codec: CodecChoice {
        get { CodecChoice(rawValue: codecRaw) ?? .hevc }
        set { codecRaw = newValue.rawValue }
    }

    var resolution: OutputResolution {
        get { OutputResolution(rawValue: resolutionRaw) ?? .native }
        set { resolutionRaw = newValue.rawValue }
    }

    var webcamCorner: WebcamCorner {
        get { WebcamCorner(rawValue: webcamCornerRaw) ?? .bottomRight }
        set { webcamCornerRaw = newValue.rawValue }
    }

    var outputFolderURL: URL {
        if !outputFolderPath.isEmpty {
            let url = URL(fileURLWithPath: outputFolderPath)
            ensureDirectory(url)
            return url
        }
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        let folder = movies.appendingPathComponent("ScreenLapse", isDirectory: true)
        ensureDirectory(folder)
        return folder
    }

    // MARK: - Private collaborators

    private var captureEngine = CaptureEngine()
    private var cameraCapture: CameraCapture?
    private var micCapture: MicCapture?
    private var clickTracker: ClickTracker?
    private var compositor: FrameCompositor?
    private var videoWriter: VideoWriter?

    private var durationTimer: Timer?
    private var sizeTimer: Timer?
    private var startedAt: Date?
    private var currentRecordingMode: RecordingMode = .normal(fps: 30)
    private var currentOutputSize: (width: Int, height: Int) = (0, 0)
    private var currentSourceFrame: CGRect = .zero

    init() {
        Task { await refreshSources() }
    }

    // MARK: - Source discovery

    func refreshSources() async {
        do {
            let content = try await CaptureEngine.fetchShareableContent()
            var list: [CaptureSource] = []
            for display in content.displays {
                let screenName = NSScreen.screens.first { screen in
                    let num = screen.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID
                    return num == display.displayID
                }?.localizedName ?? "Display"
                let name = "\(screenName) (\(display.width)×\(display.height))"
                list.append(.display(id: display.displayID, name: name))
            }
            for window in content.windows {
                let title = window.title ?? "Untitled"
                let app = window.owningApplication?.applicationName ?? "Unknown"
                guard window.frame.width >= 100, window.frame.height >= 100 else { continue }
                list.append(.window(id: window.windowID, title: title, app: app))
            }
            availableSources = list
            if selectedSource == nil {
                selectedSource = list.first
            }
        } catch {
            let msg = error.localizedDescription
            if msg.localizedCaseInsensitiveContains("TCC") ||
               msg.localizedCaseInsensitiveContains("declined") ||
               msg.localizedCaseInsensitiveContains("not authorized") {
                errorMessage = "Screen recording permission denied. Enable ScreenLapse in System Settings → Privacy & Security → Screen Recording."
            } else {
                errorMessage = "Could not list sources: \(msg)"
            }
        }
    }

    // MARK: - Recording lifecycle

    func startRecording() async throws {
        guard !isRecording, !isPreparing else { return }
        guard let source = selectedSource ?? availableSources.first else {
            errorMessage = "No capture source selected."
            return
        }

        // On macOS 14+, ScreenCaptureKit has its own TCC entry separate from the legacy
        // CGPreflightScreenCaptureAccess check. Use availableSources as the ground truth:
        // if SCShareableContent succeeded at least once, we have permission.
        let hasPermission = PermissionChecker.screenRecordingStatus() == .granted
                         && !availableSources.isEmpty
        if !hasPermission {
            _ = PermissionChecker.requestScreenRecording()
            errorMessage = "Screen recording permission is required. Enable ScreenLapse in System Settings → Privacy & Security → Screen Recording, then try again."
            PermissionChecker.openScreenRecordingSettings()
            return
        }

        if captureMic, PermissionChecker.micStatus() == .notDetermined {
            _ = await PermissionChecker.requestMic()
        }
        if captureWebcam, PermissionChecker.cameraStatus() == .notDetermined {
            _ = await PermissionChecker.requestCamera()
        }

        // Refuse to start if disk is nearly full — avoids a corrupt/truncated file mid-recording.
        let freeBytes = (try? outputFolderURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        if freeBytes < 100_000_000 {
            errorMessage = "Not enough disk space (need ≥ 100 MB free, have \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)))."
            return
        }

        isPreparing = true
        errorMessage = nil

        if countdownSeconds > 0 {
            await CountdownOverlayController.runCountdown(seconds: countdownSeconds)
        }

        do {
            try await internalStart(source: source)
        } catch {
            errorMessage = error.localizedDescription
            isPreparing = false
            await teardown()
            throw error
        }
    }

    private func internalStart(source: CaptureSource) async throws {

        currentRecordingMode = mode

        let captureFPS = mode.captureFPS

        let (sourceWidth, sourceHeight, sourceFrame) = try await measureSource(source)
        currentSourceFrame = sourceFrame

        let (outWidth, outHeight) = computeOutputSize(sourceWidth: sourceWidth,
                                                      sourceHeight: sourceHeight)
        currentOutputSize = (outWidth, outHeight)

        let timestamp = dateStamp()
        let ext = (useMOV || codec == .proRes) ? "mov" : "mp4"
        let modeTag = mode.isTimeLapse ? "timelapse" : "normal"
        let fileName = "ScreenLapse-\(modeTag)-\(timestamp).\(ext)"
        let outputURL = outputFolderURL.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: outputURL)

        let bitrate = quality.bitrate(for: outHeight)
        let recordsAudio = !mode.isTimeLapse && (captureSystemAudio || captureMic)

        let writerConfig = VideoWriter.Configuration(
            outputURL: outputURL,
            width: outWidth,
            height: outHeight,
            bitrate: bitrate,
            qualityFactor: quality.qualityFactor,
            codec: codec,
            containerIsMOV: useMOV,
            recordsAudio: recordsAudio,
            mode: mode
        )

        let writer = try VideoWriter(configuration: writerConfig)
        try writer.start()
        self.videoWriter = writer

        let compositor = FrameCompositor()
        var opts = FrameCompositor.Options()
        opts.webcamCorner = webcamCorner
        opts.webcamRelativeHeight = webcamRelativeHeight
        opts.drawClickRipples = highlightClicks
        opts.sourceFrameInGlobalCoords = sourceFrame
        compositor.options = opts
        self.compositor = compositor

        if highlightClicks {
            let tracker = ClickTracker()
            tracker.start()
            compositor.clickTracker = tracker
            self.clickTracker = tracker
        }

        if captureWebcam {
            do {
                let cam = CameraCapture()
                cam.onFrame = { [weak compositor] buf in
                    compositor?.updateCameraFrame(buf)
                }
                try cam.start()
                self.cameraCapture = cam
            } catch {
                NSLog("ScreenLapse: camera start failed: \(error)")
            }
        }

        let captureSystemAudioForThisRun = recordsAudio && captureSystemAudio
        let captureMicForThisRun = recordsAudio && captureMic

        if captureMicForThisRun {
            do {
                let mic = MicCapture()
                mic.onAudioFrame = { [weak writer] sb in
                    writer?.appendAudio(sb)
                }
                try mic.start()
                self.micCapture = mic
            } catch {
                NSLog("ScreenLapse: mic start failed: \(error)")
            }
        }

        let webcamOn = captureWebcam
        let clicksOn = highlightClicks
        let frameW = outWidth
        let frameH = outHeight

        captureEngine = CaptureEngine()
        captureEngine.onVideoFrame = { [weak writer, weak compositor] sample in
            guard let writer, let compositor else { return }
            let composed = compositor.compose(screenSampleBuffer: sample,
                                              outputWidth: frameW,
                                              outputHeight: frameH,
                                              includeWebcam: webcamOn,
                                              includeClicks: clicksOn)
            writer.appendVideo(composed ?? sample)
        }
        captureEngine.onAudioFrame = { [weak writer] sample in
            writer?.appendAudio(sample)
        }
        captureEngine.onStop = { [weak self] err in
            if let err {
                let msg = err.localizedDescription
                NSLog("ScreenLapse: SCStream stopped with error: \(msg)")
                Task { @MainActor [weak self] in
                    // Stop recording first so isRecording is false, THEN surface the error.
                    await self?.stopRecording()
                    AppDelegate.shared?.showError("Recording stopped unexpectedly", detail: msg)
                }
            }
        }

        NSLog("ScreenLapse: calling startCapture – source=\(source.displayName) fps=\(captureFPS) audio=\(captureSystemAudioForThisRun)")
        try await captureEngine.startCapture(source: source,
                                             captureFPS: captureFPS,
                                             capturesAudio: captureSystemAudioForThisRun,
                                             showsCursor: showsCursor)
        NSLog("ScreenLapse: startCapture succeeded – isRecording will be set true")

        startedAt = Date()
        elapsedSeconds = 0
        capturedFrames = 0
        currentFileSize = 0
        isPreparing = false
        isPaused = false
        isRecording = true

        startTimers()
    }

    private func startTimers() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(start)
                self.capturedFrames = self.videoWriter?.frameCount ?? 0
            }
        }
        sizeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentFileSize = self?.videoWriter?.currentFileSize ?? 0
            }
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        videoWriter?.pause(atPTS: now)
        isPaused = true
        durationTimer?.invalidate(); durationTimer = nil
        sizeTimer?.invalidate(); sizeTimer = nil
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        videoWriter?.resume(atPTS: now)
        isPaused = false
        startTimers()
    }

    func stopRecording() async {
        guard isRecording || isPreparing else { return }
        let writer = self.videoWriter
        let realDuration = elapsedSeconds
        let mode = currentRecordingMode

        await teardown()

        var savedURL: URL?
        if let writer = writer {
            do {
                savedURL = try await writer.finalize()
            } catch {
                errorMessage = "Finalize failed: \(error.localizedDescription)"
            }
        }

        if let url = savedURL {
            lastRecordingURL = url
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let outputDuration: TimeInterval
            switch mode {
            case .normal:
                outputDuration = realDuration
            case .timeLapse(let mult):
                outputDuration = realDuration / Double(mult)
            }
            let recent = RecentRecording(id: UUID(),
                                         url: url,
                                         modeLabel: mode.label,
                                         capturedAt: Date(),
                                         realDuration: realDuration,
                                         outputDuration: outputDuration,
                                         fileSize: size)
            RecentRecordings.shared.add(recent)
        }
    }

    private func teardown() async {
        durationTimer?.invalidate(); durationTimer = nil
        sizeTimer?.invalidate(); sizeTimer = nil
        await captureEngine.stopCapture()
        cameraCapture?.stop(); cameraCapture = nil
        micCapture?.stop(); micCapture = nil
        clickTracker?.stop(); clickTracker = nil
        compositor = nil
        isRecording = false
        isPreparing = false
        isPaused = false
        startedAt = nil
    }

    // MARK: - Helpers

    private func computeOutputSize(sourceWidth: Int, sourceHeight: Int) -> (Int, Int) {
        guard let targetH = resolution.targetHeight else {
            return (max(2, sourceWidth & ~1), max(2, sourceHeight & ~1))
        }
        let scale = CGFloat(targetH) / CGFloat(sourceHeight)
        let w = Int((CGFloat(sourceWidth) * scale).rounded()) & ~1
        let h = targetH & ~1
        return (max(2, w), max(2, h))
    }

    private func measureSource(_ source: CaptureSource) async throws -> (Int, Int, CGRect) {
        let content = try await CaptureEngine.fetchShareableContent()
        switch source {
        case .display(let id, _):
            guard let display = content.displays.first(where: { $0.displayID == id })
                    ?? content.displays.first else {
                throw NSError(domain: "RecordingManager", code: -1)
            }
            return (display.width, display.height, display.frame)
        case .window(let id, _, _):
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw NSError(domain: "RecordingManager", code: -1)
            }
            return (Int(window.frame.width), Int(window.frame.height), window.frame)
        case .region(let rect, _):
            return (Int(rect.width), Int(rect.height), rect)
        }
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(at: url,
                                                 withIntermediateDirectories: true)
    }

    private func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Convenience

    var formattedElapsed: String {
        let total = Int(elapsedSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var projectedOutputDuration: TimeInterval {
        switch mode {
        case .normal: return elapsedSeconds
        case .timeLapse(let mult): return elapsedSeconds / Double(mult)
        }
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: currentFileSize, countStyle: .file)
    }
}
