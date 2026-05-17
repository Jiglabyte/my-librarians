// ScreenLapsePro
// Core/RecordingManager.swift
// Central state machine for recording sessions

import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import AppKit

// MARK: - RecordingMode

enum RecordingMode: Equatable {
    case normal(fps: Int)
    case timeLapse(multiplier: Int)

    var isTimeLapse: Bool {
        if case .timeLapse = self { return true }
        return false
    }

    /// Speed multiplier. 1 for normal recording.
    var multiplier: Int {
        switch self {
        case .normal:                    return 1
        case .timeLapse(let m):          return m
        }
    }

    /// Frames per second that the capture engine should deliver.
    var captureFPS: Int {
        switch self {
        case .normal(let fps):           return fps
        case .timeLapse(let m):          return max(1, 30 / m)
        }
    }

    /// Human-readable description shown in the UI.
    var label: String {
        switch self {
        case .normal(let fps):           return "\(fps) fps"
        case .timeLapse(let m):          return "\(m)x time-lapse"
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
final class RecordingManager: ObservableObject, CaptureEngineDelegate {

    // MARK: Published State

    @Published var isRecording:     Bool   = false
    @Published var isPaused:        Bool   = false
    @Published var elapsedSeconds:  Int    = 0
    @Published var fileSize:        String = "0 MB"
    @Published var outputURL:       URL?   = nil
    @Published var error:           String? = nil

    // MARK: Internal

    private let captureEngine    = CaptureEngine()
    private var videoWriter:     VideoWriter?
    private var timer:           Timer?
    private var startDate:       Date?
    private var currentOutputURL: URL?

    /// Background queue used for appending buffers to the writer.
    private let writerQueue = DispatchQueue(label: "pro.screenlapse.writer",
                                           qos: .userInitiated)

    // MARK: Init

    init() {
        captureEngine.delegate = self
        _ = Prefs.shared // trigger defaults registration
    }

    // MARK: - Start Recording

    func startRecording(filter: SCContentFilter, mode: RecordingMode) async {
        guard !isRecording else { return }

        error = nil
        outputURL = nil
        elapsedSeconds = 0
        fileSize = "0 MB"

        // Prepare output URL.
        let destURL: URL
        do {
            try Prefs.ensureOutputFolderExists()
            destURL = Prefs.makeOutputURL()
        } catch {
            self.error = "Cannot create output folder: \(error.localizedDescription)"
            return
        }
        currentOutputURL = destURL

        // Determine capture dimensions from the filter.
        let scale: CGFloat
        if #available(macOS 14.0, *) {
            scale = filter.pointPixelScale
        } else {
            scale = 2.0
        }
        let rect   = filter.contentRect
        let width  = max(2, Int(rect.width  * scale))
        let height = max(2, Int(rect.height * scale))

        // Create the video writer.
        let writer: VideoWriter
        do {
            writer = try VideoWriter(
                outputURL:            destURL,
                width:                width,
                height:               height,
                isTimeLapse:          mode.isTimeLapse,
                timeLapseMultiplier:  mode.multiplier
            )
        } catch {
            self.error = "Cannot create video writer: \(error.localizedDescription)"
            return
        }

        writer.start()
        videoWriter = writer

        // Start the capture engine.
        do {
            try await captureEngine.start(
                filter:               filter,
                fps:                  mode.captureFPS,
                isTimeLapse:          mode.isTimeLapse,
                timeLapseMultiplier:  mode.multiplier
            )
        } catch {
            self.error = "Cannot start capture: \(error.localizedDescription)"
            videoWriter = nil
            return
        }

        isRecording = true
        isPaused    = false
        startDate   = Date()
        startTimer()

        NotificationCenter.default.post(name: .recordingDidStart, object: self)
    }

    // MARK: - Stop Recording

    func stopRecording() async {
        guard isRecording else { return }

        // Stop capture first so no more frames arrive.
        do {
            try await captureEngine.stop()
        } catch {
            // Non-fatal; continue to finalise the writer.
        }

        stopTimer()
        isRecording = false
        isPaused    = false

        // Finalise the file.
        if let writer = videoWriter {
            let finalURL = await writer.finish()
            videoWriter = nil
            outputURL   = finalURL

            // Reveal in Finder.
            NSWorkspace.shared.selectFile(
                finalURL.path,
                inFileViewerRootedAtPath: finalURL.deletingLastPathComponent().path
            )
        }

        NotificationCenter.default.post(name: .recordingDidStop, object: self)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let start = startDate else { return }
        elapsedSeconds = Int(Date().timeIntervalSince(start))
        updateFileSize()
    }

    private func updateFileSize() {
        guard let url = currentOutputURL else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? Int64 else { return }

        let mb = Double(bytes) / 1_048_576
        if mb >= 1000 {
            fileSize = String(format: "%.1f GB", mb / 1024)
        } else {
            fileSize = String(format: "%.1f MB", mb)
        }
    }

    // MARK: - CaptureEngineDelegate

    nonisolated func captureEngine(_ engine: CaptureEngine,
                                   didOutputVideoFrame sampleBuffer: CMSampleBuffer) {
        // Retain the buffer so it survives the dispatch.
        let retained = sampleBuffer
        writerQueue.async { [weak self] in
            guard let self else { return }
            // videoWriter access is from the serial writerQueue only after start; this is safe.
            self.videoWriter?.appendFrame(retained)
        }
    }

    nonisolated func captureEngineDidStop(_ engine: CaptureEngine) {
        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            await self.stopRecording()
        }
    }
}
