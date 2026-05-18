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
        case .timeLapse(let m): return max(1, 30 / m)
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
final class RecordingManager: ObservableObject, CaptureEngineDelegate, MicrophoneCapturerDelegate {

    // MARK: Published State

    @Published var isRecording:        Bool    = false
    @Published var isPaused:           Bool    = false
    @Published var elapsedSeconds:     Int     = 0
    @Published var fileSize:           String  = "0 MB"
    @Published var outputURL:          URL?    = nil
    @Published var error:              String? = nil
    @Published var countdownRemaining: Int?    = nil
    @Published var currentMode:        RecordingMode = .normal(fps: 30)

    // MARK: Internal

    private let captureEngine    = CaptureEngine()
    private let micCapturer      = MicrophoneCapturer()
    private var videoWriter:     VideoWriter?
    private var elapsedTimer:    Timer?
    private var autoStopTimer:   Timer?
    private var startDate:       Date?
    private var currentOutputURL: URL?
    private var sleepAssertionID: IOPMAssertionID = 0

    private let writerQueue = DispatchQueue(label: "pro.screenlapse.writer", qos: .userInitiated)

    // MARK: Init

    init() {
        captureEngine.delegate = self
        micCapturer.delegate   = self
        _ = Prefs.shared
    }

    // MARK: - Start Recording

    func startRecording(filter: SCContentFilter, mode: RecordingMode) async {
        guard !isRecording, countdownRemaining == nil else { return }

        error = nil
        outputURL = nil

        // Countdown
        let countdown = Prefs.countdownSeconds
        if countdown > 0 {
            for i in stride(from: countdown, through: 1, by: -1) {
                countdownRemaining = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdownRemaining = nil
        }

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
        let width  = max(2, Int(rect.width  * scale))
        let height = max(2, Int(rect.height * scale))

        // Video writer
        let writer: VideoWriter
        do {
            writer = try VideoWriter(
                outputURL:          destURL,
                width:              width,
                height:             height,
                isTimeLapse:        mode.isTimeLapse,
                timeLapseMultiplier: mode.multiplier,
                bitratePreset:      Prefs.videoBitratePreset,
                includeSystemAudio: Prefs.recordSystemAudio,
                includeMicAudio:    Prefs.recordMicrophone
            )
        } catch {
            self.error = "Cannot create video writer: \(error.localizedDescription)"
            return
        }
        writer.start()
        videoWriter = writer

        // Capture engine
        do {
            try await captureEngine.start(
                filter:              filter,
                fps:                 mode.captureFPS,
                isTimeLapse:         mode.isTimeLapse,
                timeLapseMultiplier: mode.multiplier,
                capturesAudio:       Prefs.recordSystemAudio
            )
        } catch {
            self.error = "Cannot start capture: \(error.localizedDescription)"
            videoWriter = nil
            return
        }

        // Microphone
        if Prefs.recordMicrophone {
            do {
                try micCapturer.start()
            } catch {
                // Non-fatal: continue without mic
                self.error = "Microphone unavailable: \(error.localizedDescription)"
            }
        }

        isRecording  = true
        isPaused     = false
        currentMode  = mode
        startDate    = Date()
        startElapsedTimer()
        startAutoStopTimerIfNeeded()
        acquireSleepAssertion()

        NotificationCenter.default.post(name: .recordingDidStart, object: self)
    }

    // MARK: - Stop Recording

    func stopRecording() async {
        guard isRecording else { return }

        do { try await captureEngine.stop() } catch {}
        micCapturer.stop()

        stopElapsedTimer()
        stopAutoStopTimer()
        releaseSleepAssertion()

        isRecording = false
        isPaused    = false

        if let writer = videoWriter {
            let finalURL = await writer.finish()
            videoWriter  = nil
            outputURL    = finalURL
            NSWorkspace.shared.selectFile(
                finalURL.path,
                inFileViewerRootedAtPath: finalURL.deletingLastPathComponent().path
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
        autoStopTimer = Timer.scheduledTimer(
            withTimeInterval: Double(minutes * 60),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.stopRecording() }
        }
    }

    private func stopAutoStopTimer() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
    }

    // MARK: - Sleep Prevention

    private func acquireSleepAssertion() {
        guard Prefs.preventSleep else { return }
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

    // MARK: - CaptureEngineDelegate

    nonisolated func captureEngine(_ engine: CaptureEngine,
                                   didOutputVideoFrame sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in self?.videoWriter?.appendFrame(buf) }
    }

    nonisolated func captureEngine(_ engine: CaptureEngine,
                                   didOutputAudioFrame sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in self?.videoWriter?.appendSystemAudio(buf) }
    }

    nonisolated func captureEngineDidStop(_ engine: CaptureEngine) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            await self.stopRecording()
        }
    }

    // MARK: - MicrophoneCapturerDelegate

    nonisolated func microphoneCapturer(_ capturer: MicrophoneCapturer,
                                        didOutputSample sampleBuffer: CMSampleBuffer) {
        let buf = sampleBuffer
        writerQueue.async { [weak self] in self?.videoWriter?.appendMicAudio(buf) }
    }
}
