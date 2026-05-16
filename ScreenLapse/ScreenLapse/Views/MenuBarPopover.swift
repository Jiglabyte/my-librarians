import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @EnvironmentObject var manager: RecordingManager
    @State private var modeTabIndex: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    modePicker

                    Group {
                        if modeTabIndex == 0 {
                            NormalModeView()
                        } else {
                            TimeLapseModeView()
                        }
                    }

                    Divider()

                    SourceSelectorView()

                    if manager.isRecording {
                        liveStats
                    }

                    if let err = manager.errorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            recordButton
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        .onAppear {
            modeTabIndex = manager.mode.isTimeLapse ? 1 : 0
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.red, .red.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 24, height: 24)
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 9, height: 9)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("ScreenLapse")
                    .font(.system(size: 14, weight: .semibold))
                Text(manager.isRecording ? "Recording…" : "Ready")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if manager.isRecording {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                    Text("REC")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12))
                .cornerRadius(5)
            }
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        SegmentedTabs(selection: $modeTabIndex,
                      labels: [("Normal", 0), ("Time-lapse", 1)],
                      isDisabled: manager.isRecording || manager.isPreparing)
        .onChange(of: modeTabIndex) { newValue in
            manager.mode = (newValue == 0) ? .normalDefault : .timeLapseDefault
        }
    }

    // MARK: - Live stats

    private var liveStats: some View {
        HStack(spacing: 0) {
            statCell(label: "Elapsed", value: manager.formattedElapsed)
            Divider().frame(height: 32)
            if manager.mode.isTimeLapse {
                statCell(label: "Output", value: formatDuration(manager.projectedOutputDuration))
                Divider().frame(height: 32)
            }
            statCell(label: "Size", value: manager.formattedFileSize)
            Divider().frame(height: 32)
            statCell(label: "Frames", value: "\(manager.capturedFrames)")
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button {
            triggerRecord()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: manager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                    .font(.system(size: 16))
                Text(buttonLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(manager.isRecording ? .red : .accentColor)
        .controlSize(.large)
        .disabled(manager.isPreparing)
        .keyboardShortcut(.return, modifiers: [])
        .help(manager.isRecording
              ? "Stop Recording  (Return or ⌃⇧R)"
              : "Start Recording  (Return or ⌃⇧R)")
    }

    private var buttonLabel: String {
        if manager.isPreparing { return "Preparing…" }
        if manager.isRecording { return "Stop Recording" }
        if manager.countdownSeconds > 0 {
            return "Start Recording   ·   \(manager.countdownSeconds)s countdown"
        }
        return "Start Recording"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                NSApp.sendAction(#selector(AppDelegate.openRecents(_:)), to: nil, from: nil)
            } label: {
                Label("Recents", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Recent recordings")

            Text("·")
                .foregroundColor(.secondary.opacity(0.5))

            Text("⌃⇧R global")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .help("Global hotkey: start/stop recording from anywhere")

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Settings  (⌘,)")
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Quit ScreenLapse  (⌘Q)")
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Helpers

    private func triggerRecord() {
        Task { @MainActor in
            if manager.isRecording {
                await manager.stopRecording()
            } else {
                AppDelegate.shared?.hidePopover()
                do {
                    try await manager.startRecording()
                } catch {
                    AppDelegate.shared?.showError("Recording failed to start",
                                                   detail: error.localizedDescription)
                }
            }
        }
    }

    private func openSettings() {
        NSApp.sendAction(#selector(AppDelegate.openSettings(_:)), to: nil, from: nil)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
