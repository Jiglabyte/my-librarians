// ScreenLapsePro
// Views/PopoverView.swift
// Main popover UI — compact vertical card design

import SwiftUI
import ScreenCaptureKit

// MARK: - Segment

private enum ModeSegment: String, CaseIterable {
    case normal    = "Normal"
    case timeLapse = "Time-Lapse"
}

// MARK: - PopoverView

struct PopoverView: View {

    @StateObject private var manager = RecordingManager()

    @State private var selectedSegment:    ModeSegment = .normal
    @State private var selectedFPS:        Int         = 30
    @State private var selectedMultiplier: Int         = 15

    @State private var activeFilter:   SCContentFilter?
    @State private var sourceLabel:    String = ""

    @State private var showSourcePicker = false
    @State private var showSettings     = false
    @State private var showError        = false

    @AppStorage(PrefsKey.recordSystemAudio) private var recordSystemAudio = false
    @AppStorage(PrefsKey.recordMicrophone)  private var recordMicrophone  = false

    private let multiplierOptions: [Int] = [5, 10, 15, 30, 60]
    private let fpsOptions:        [Int] = [24, 30, 60]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !checkScreenRecordingPermission() {
                    PermissionView().padding(12)
                } else {
                    mainContent
                }
            }
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .onReceive(manager.$error) { showError = $0 != nil }
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                showSettings = true
            }

            // Countdown overlay
            if let remaining = manager.countdownRemaining {
                countdownOverlay(remaining)
                    .frame(width: 320)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.countdownRemaining)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerRow
            Divider().opacity(0.4)
            modeSection
            Divider().opacity(0.4)
            sourceSection
            Divider().opacity(0.4)
            audioRow
            Divider().opacity(0.4)
            statusOrFolderRow
            recordButton
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            if showError, let err = manager.error {
                errorBanner(err)
            }

            quitFooter
        }
    }

    // MARK: - Quit Footer

    private var quitFooter: some View {
        HStack {
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                    Text("Quit")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .help("Quit ScreenLapse Pro")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("ScreenLapse Pro")
                    .font(.system(size: 14, weight: .semibold))
                Text("Screen recorder & time-lapse")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $selectedSegment) {
                ForEach(ModeSegment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(manager.isRecording)

            Group {
                if selectedSegment == .normal {
                    normalModeOptions
                } else {
                    timeLapseModeOptions
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selectedSegment)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var normalModeOptions: some View {
        HStack(spacing: 6) {
            Text("Frame rate")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $selectedFPS) {
                ForEach(fpsOptions, id: \.self) { Text("\($0) fps").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .disabled(manager.isRecording)
        }
    }

    private var timeLapseModeOptions: some View {
        HStack(spacing: 5) {
            ForEach(multiplierOptions, id: \.self) { mult in
                let sel = mult == selectedMultiplier
                Button { selectedMultiplier = mult } label: {
                    Text("\(mult)x")
                        .font(.system(size: 12, weight: sel ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(sel ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(sel ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(manager.isRecording)
            }
        }
    }

    // MARK: - Source Section

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture Source")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            HStack(spacing: 8) {
                sourceButton(icon: "display",   label: "Display")
                sourceButton(icon: "macwindow", label: "Window")
            }

            if !sourceLabel.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text(sourceLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .sheet(isPresented: $showSourcePicker) {
            SourcePickerView { filter, label in
                activeFilter     = filter
                sourceLabel      = label
                showSourcePicker = false
            }
        }
    }

    @ViewBuilder
    private func sourceButton(icon: String, label: String) -> some View {
        Button { showSourcePicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(label).font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(manager.isRecording)
    }

    // MARK: - Audio Row

    private var audioRow: some View {
        HStack(spacing: 0) {
            audioChip(
                icon: "speaker.wave.2.fill",
                label: "System Audio",
                active: recordSystemAudio
            ) { recordSystemAudio.toggle() }

            Divider().frame(height: 28).opacity(0.3)

            audioChip(
                icon: "mic.fill",
                label: "Microphone",
                active: recordMicrophone
            ) { recordMicrophone.toggle() }
        }
        .disabled(manager.isRecording)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func audioChip(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                Text(label)
                    .font(.system(size: 12, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(active ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status / Folder Row

    private var statusOrFolderRow: some View {
        Group {
            if manager.isRecording {
                recordingStatusRow
            } else {
                folderPathRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var recordingStatusRow: some View {
        HStack(spacing: 8) {
            RecordingDot()
            Text(elapsedFormatted)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(manager.fileSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            // Audio indicators while recording
            if recordSystemAudio {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
            if recordMicrophone {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        }
    }

    private var folderPathRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text(abbreviatedOutputPath)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        let isCounting  = manager.countdownRemaining != nil
        let isActive    = manager.isRecording || isCounting
        let icon        = isActive ? "stop.fill"    : "circle.fill"
        let label       = manager.isRecording ? "Stop Recording"
                        : isCounting          ? "Cancel"
                        :                       "Start Recording"
        let bgColor: Color = isActive ? Color.secondary.opacity(0.2) : Color.red
        let fgColor: Color = isActive ? Color.primary : Color.white

        return Button(action: startOrStop) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(fgColor)
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(fgColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer()
            Button {
                showError  = false
                manager.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: - Countdown Overlay

    @ViewBuilder
    private func countdownOverlay(_ seconds: Int) -> some View {
        ZStack {
            Color.black.opacity(0.6)
                .clipShape(RoundedRectangle(cornerRadius: 0))

            VStack(spacing: 10) {
                Text("\(seconds)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: seconds)

                Text("Recording starts…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    // MARK: - Actions

    private func startOrStop() {
        if manager.isRecording {
            Task { await manager.stopRecording() }
        } else if manager.countdownRemaining != nil {
            manager.cancelCountdown()
        } else {
            if activeFilter == nil {
                showSourcePicker = true
            } else {
                beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard let filter = activeFilter else { return }
        let mode: RecordingMode = selectedSegment == .timeLapse
            ? .timeLapse(multiplier: selectedMultiplier)
            : .normal(fps: selectedFPS)
        manager.startRecording(filter: filter, mode: mode)
    }

    // MARK: - Helpers

    private var elapsedFormatted: String {
        let t = manager.elapsedSeconds
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var abbreviatedOutputPath: String {
        let path = Prefs.outputFolder
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - RecordingDot

private struct RecordingDot: View {
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: opacity)
            .onAppear { opacity = 0.2 }
    }
}

// MARK: - Preview

#if DEBUG
struct PopoverView_Previews: PreviewProvider {
    static var previews: some View {
        PopoverView()
    }
}
#endif
