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

    // Mode selection
    @State private var selectedSegment:    ModeSegment = .normal
    @State private var selectedFPS:        Int         = 30
    @State private var selectedMultiplier: Int         = 15

    // Source selection
    @State private var activeFilter:   SCContentFilter?
    @State private var sourceLabel:    String = ""

    // Sheet / popover presentation
    @State private var showSourcePicker = false
    @State private var showSettings     = false

    // Error banner
    @State private var showError = false

    private let multiplierOptions: [Int] = [5, 10, 15, 30, 60]
    private let fpsOptions:        [Int] = [24, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            // Guard: permission check
            if !checkScreenRecordingPermission() {
                PermissionView()
                    .padding(12)
            } else {
                mainContent
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .onReceive(manager.$error) { err in
            showError = err != nil
        }
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
            statusOrFolderRow
            recordButton
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            if showError, let err = manager.error {
                errorBanner(err)
            }
        }
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
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $selectedSegment) {
                ForEach(ModeSegment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
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
                ForEach(fpsOptions, id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
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
                let isSelected = mult == selectedMultiplier
                Button {
                    selectedMultiplier = mult
                } label: {
                    Text("\(mult)x")
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
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
                sourceButton(icon: "display",   label: "Display",  tag: "display")
                sourceButton(icon: "macwindow", label: "Window",   tag: "window")
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
                activeFilter = filter
                sourceLabel  = label
                showSourcePicker = false
                // Auto-start if the user picked while already wanting to record
            }
        }
    }

    @ViewBuilder
    private func sourceButton(icon: String, label: String, tag: String) -> some View {
        let isActive = !sourceLabel.isEmpty && sourceLabel.localizedCaseInsensitiveContains(
            tag == "display" ? "Display" : ""
        )
        _ = isActive  // suppress unused warning; styling handled uniformly below

        Button {
            showSourcePicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12))
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
            // Animated red dot
            RecordingDot()

            Text(elapsedFormatted)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))

            Text(manager.fileSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
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
        Button(action: startOrStop) {
            HStack(spacing: 8) {
                Image(systemName: manager.isRecording ? "stop.fill" : "circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(manager.isRecording ? Color.primary : Color.white)
                Text(manager.isRecording ? "Stop Recording" : "Start Recording")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(manager.isRecording ? Color.primary : Color.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(manager.isRecording ? Color.secondary.opacity(0.2) : Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
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
                showError = false
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

    // MARK: - Actions

    private func startOrStop() {
        if manager.isRecording {
            Task { await manager.stopRecording() }
        } else {
            if activeFilter == nil {
                // Show source picker first; recording starts when the user selects
                showSourcePicker = true
            } else {
                beginRecording()
            }
        }
    }

    private func beginRecording() {
        guard let filter = activeFilter else { return }

        let mode: RecordingMode
        if selectedSegment == .timeLapse {
            mode = .timeLapse(multiplier: selectedMultiplier)
        } else {
            mode = .normal(fps: selectedFPS)
        }

        Task {
            await manager.startRecording(filter: filter, mode: mode)
        }
    }

    // MARK: - Helpers

    private var elapsedFormatted: String {
        let total   = manager.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var abbreviatedOutputPath: String {
        let path = Prefs.outputFolder
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - RecordingDot

/// Small animated red indicator dot used in the status row.
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
