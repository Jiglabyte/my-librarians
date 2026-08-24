// ScreenLapsePro
// Core/RecordingManager.swift
// Central state machine for recording sessions

import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import AppKit
import IOKit.pwr_mgt

// MARK: - RecordingMode

enum RecordingMode: Equatable {
    case normal(fps: Int)
    case timeLapse(multiplier: Int)

    var isTimeLapse: Bool {
        if case .timeLapse = self { return true }
        return false
    }

    var multiplier: Int {
        switch self {
        case .normal:           return 1
        case .timeLapse(let m): return m
        }
    }

    var captureFPS: Int {
        switch self {
        case .normal(let fps):  return fps
        case .timeLapse(let m): return Swift.max(1, 30 / m)
        }
    }

    var label: String {
        switch self {
        case .normal(let fps):  return "\(fps) fps"
        case .timeLapse(let m): return "\(m)x time-lapse"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let recordingDidStart = Notification.Name("ScreenLapsePro.RecordingDidStart")
    static let recordingDidStop  = Notification.Name("ScreenLapsePro.RecordingDidStop")
}

// MARK: - RecordingManager

@MainActor
final class RecordingManager: ObservableObject {

    // MARK: Published State

    @Published var isRecording:        Bool    = false
    @Published var isPaused:           Bool    = false
    @Published var elapsedSeconds:     Int     = 0
    @Published var fileSize:           String  = "0 MB"
    @Published var outputURL:          URL?    = nil
    @Published var error:              String? = nil
    @Published var countdownRemaining: Int?    = nil
    @Published var currentMode:        RecordingMode = .normal(fps: 30)

    // MARK: Private — infrastructure

    private let captureEngine = CaptureEngine()
    private let micCapturer   = MicrophoneCapturer()
    // nonisolated(unsafe): access is manually serialized — set on @MainActor before capture
    // starts, cleared only after writerQueue is fully drained in stopRecording().
    nonisolated(unsafe) private var videoWriter: VideoWriter?
    private var elapsedTimer: Timer?
    private var autoStopTimer: Timer?
    private var recordingTask: Task<Void, Never>?
    private var startDate:     Date?
    private var currentOutputURL: URL?
    private var sleepAssertionID: IOPMAssertionID = 0

    /// Serial queue for all VideoWriter appends — keeps audio+video ordering tight.
    private let writerQueue = DispatchQueue(label: "pro.screenlapse.writer", qos: .userInitiated)

    /// Pause flag consulted from writerQueue. Only mutated via `writerQueue.async`
    /// to keep access serialised with buffer appends on the same queue.
    nonisolated(unsafe) private var isPausedForFrames = false

    // MARK: Init

    init() {
        captureEngine.delegate = self
        micCapturer.delegate   = self
        _ = Prefs.shared
    }

    // MARK: - Start (synchronous entry point)

    /// Kicks off a countdown (if configured) then starts recording.
    /// Non-async so callers don't need a Task wrapper.
    func startRecording(filter: SCContentFilter, mode: RecordingMode) {
        guard !isRecording, recordingTask == nil else { return }

        recordingTask = Task { [weak self] in
            await self?.runCountdownThenRecord(filter: filter, mode: mode)
            await MainActor.run { self?.recordingTask = nil }
        }
    }

    /// Cancel an active countdown before recording has actually begun.
    func cancelCountdown() {
        recordingTask?.cancel()
        recordingTask = nil
        countdownRemaining = nil
    }

    // MARK: - Countdown + Record

    private func runCountdownThenRecord(filter: SCContentFilter, mode: RecordingMode) async {
        let seconds = Prefs.countdownSeconds
        if seconds > 0 {
            for i in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else {
                    countdownRemaining = nil
                    return
                }
                countdownRemaining = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdownRemaining = nil
        }
        guard !Task.isCancelled else { return }
        await performRecordingStart(filter: filter, mode: mode)
    }

    // MARK: - Actual Recording Start

    private func performRecordingStart(filter: SCContentFilter, mode: RecordingMode) async {
        error    = nil
        outputURL = nil
        elapsedSeconds = 0
        fileSize = "0 MB"

        // Output URL
        let destURL: URL
        do {
            try Prefs.ensureOutputFolderExists()
            destURL = Prefs.makeOutputURL()
        } catch {
            self.error = "Cannot create output folder: \(error.localizedDescription)"
            return
        }
        currentOutputURL = destURL

        // Capture dimensions
        let rect: CGRect
        let scale: CGFloat
        if #available(macOS 14.0, *) {
            scale = CGFloat(filter.pointPixelScale)
            rect  = filter.contentRect
        } else {
            scale = 2.0
            rect  = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        let width  = Swift.max(2, Int(rect.width  * scale))
        let height = Swift.max(2, Int(rect.height * scale))

        // Audio only makes sense for normal recording.
        // Time-lapse uses synthetic video PTS that would completely desync real audio PTS.
        let wantSystemAudio = !mode.isTimeLapse && Prefs.recordSystemAudio
        let wantMicAudio    = !mode.isTimeLapse && Prefs.recordMicrophone

        // Build VideoWriter
        let writer: VideoWriter
        do {
            writer = try VideoWriter(
                outputURL:           destURL,
                width:               width,
                height:              height,
                isTimeLapse:         mode.isTimeLapse,
                timeLapseMultiplier: mode.multiplier,
                bitratePreset:       Prefs.videoBitratePreset,
                includeSystemAudio:  wantSystemAudio,
                includeMicAudio:     wantMicAudio
            )
        } catch {
            self.error = "Cannot create video writer: \(error.localizedDescription)"
            return
        }
        writer.start()
        videoWriter = writer

        // Start capture engine
        do {
            try await captureEngine.start(
                filter:              filter,
                fps:                 mode.captureFPS,
                isTimeLapse:         mode.isTimeLapse,
                timeLapseMultiplier: mode.multiplier,
                capturesAudio:       wantSystemAudio
            )
        } catch {
            self.error = "Cannot start capture: \(error.localizedDescription)"
            videoWriter = nil
            return
        }

        // Microphone (non-fatal if it fails)
        if wantMicAudio {
            do {
                try micCapturer.start()
            } catch {
                self.error = "Microphone unavailable: \(error.localizedDescription)"
            }
        }

        // All setup succeeded — update state
        isRecording = true
        isPaused    = false
        currentMode = mode
        startDate   = Date()
        writerQueue.async { self.isPausedForFrames = false }

        startElapsedTimer()
        startAutoStopTimerIfNeeded()
        acquireSleepAssertion()   // Only acquired after successful start

        NotificationCenter.default.post(name: .recordingDidStart, object: self)
    }

    // MARK: - Pause / Resume

    /// Freezes the recording: the elapsed timer stops and incoming buffers are
    /// dropped by the writer queue until `resumeRecording` is called.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        writerQueue.async { self.isPausedForFrames = true }
        stopElapsedTimer()
    }

    /// Resumes a paused recording. Advances `startDate` forward by the paused
    /// duration so `elapsedSeconds` continues counting from where it stopped.
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused  = false
        startDate = Date().addingTimeInterval(-TimeInterval(elapsedSeconds))
        writerQueue.async { self.isPausedForFrames = false }
        startElapsedTimer()
    }

    // MARK: - Stop Recording

    func stopRecording() async {
        guard isRecording else { return }

        // Stop inbound streams first so no more frames are dispatched to writerQueue
        do { try await captureEngine.stop() } catch {}
        micCapturer.stop()

        stopElapsedTimer()
        stopAutoStopTimer()
        releaseSleepAssertion()
        isRecording = false
        isPaused    = false

        // Drain writerQueue so all in-flight appends complete before we hand off to finish()
        let writer = videoWriter
        videoWriter = nil
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writerQueue.async { cont.resume() }
        }

        guard let writer else { return }
        let finalURL = await writer.finish()
        outputURL = finalURL

        if let url = finalURL {
            RecentRecordingsStore.shared.add(url: url, mode: currentMode.label)
            NSWorkspace.shared.selectFile(
                url.path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
        }

        NotificationCenter.default.post(name: .recordingDidStop, object: self)
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func tick() {
        guard let start = startDate else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
        updateFileSize()
    }

    private func updateFileSize() {
        guard let url = currentOutputURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return }
        let mb = Double(bytes) / 1_048_576
        fileSize = mb >= 1000
            ? String(format: "%.1f GB", mb / 1024)
            : String(format: "%.1f MB", mb)
    }

    // MARK: - Auto-Stop

    private func startAutoStopTimerIfNeeded() {
        let minutes = Prefs.autoStopMinutes
        guard minutes > 0 else { return }
        let t = Timer(timeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.stopRecording() }
        }
        RunLoop.main.add(t, forMode: .common)
        autoStopTimer = t
    }

    private func stopAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
    }

    // MARK: - Sleep Prevention

    private func acquireSleepAssertion() {
        guard Prefs.preventSleep, sleepAssertionID == 0 else { return }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ScreenLapse Pro is recording" as CFString,
            &sleepAssertionID
        )
    }

    private func releaseSleepAssertion() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }
}

// MARK: - CaptureEngineDelegate

extension RecordingManager: CaptureEngineDelegate {

    nonisolated func captureEngine(_ engine: CaptureEngine,
                                   didOutputVideoFrame sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in
            guard let self, !self.isPausedForFrames else { return }
            self.videoWriter?.appendFrame(buf)
        }
    }

    nonisolated func captureEngine(_ engine: CaptureEngine,
                                   didOutputAudioFrame sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in
            guard let self, !self.isPausedForFrames else { return }
            self.videoWriter?.appendSystemAudio(buf)
        }
    }

    nonisolated func captureEngineDidStop(_ engine: CaptureEngine) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            await self.stopRecording()
        }
    }
}

// MARK: - MicrophoneCapturerDelegate

extension RecordingManager: MicrophoneCapturerDelegate {

    nonisolated func microphoneCapturer(_ capturer: MicrophoneCapturer,
                                        didOutputSample sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in
            guard let self, !self.isPausedForFrames else { return }
            self.videoWriter?.appendMicAudio(buf)
        }
    }
}

// MARK: - CMSampleBuffer Sendable

// CMSampleBuffer is a Core Foundation reference type that is internally thread-safe.
// This retroactive conformance lets us pass buffers across actor/queue boundaries
// without wrapping them, matching the standard pattern used in AVFoundation pipelines.
extension CMSampleBuffer: @unchecked @retroactive Sendable {}
