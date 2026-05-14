import SwiftUI
import AppKit

struct MenuBarPopover: View {
    @EnvironmentObject var manager: RecordingManager
    @State private var modeTabIndex: Int = 0
    @State private var showingRecents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
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
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(3)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
        .onAppear {
            modeTabIndex = manager.mode.isTimeLapse ? 1 : 0
            Task { await manager.refreshSources() }
        }
        .popover(isPresented: $showingRecents, arrowEdge: .trailing) {
            RecentRecordingsView()
                .frame(width: 360, height: 400)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 18, weight: .medium))
            Text("ScreenLapse")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            if manager.isRecording {
                HStack(spacing: 4) {
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
        Picker("", selection: $modeTabIndex) {
            Text("Normal").tag(0)
            Text("Time-lapse").tag(1)
        }
        .pickerStyle(.segmented)
        .disabled(manager.isRecording || manager.isPreparing)
        .onChange(of: modeTabIndex) { newValue in
            manager.mode = (newValue == 0) ? .normalDefault : .timeLapseDefault
        }
    }

    // MARK: - Live stats

    private var liveStats: some View {
        HStack(spacing: 0) {
            statCell(label: "Elapsed", value: manager.formattedElapsed)
            if manager.mode.isTimeLapse {
                Divider().frame(height: 32)
                statCell(label: "Output", value: formatDuration(manager.projectedOutputDuration))
            }
            Divider().frame(height: 32)
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
            Task {
                if manager.isRecording {
                    await manager.stopRecording()
                } else {
                    try? await manager.startRecording()
                }
            }
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
        .help(manager.isRecording ? "Stop Recording (Return)" : "Start Recording (Return)")
    }

    private var buttonLabel: String {
        if manager.isPreparing {
            return "Preparing…"
        }
        if manager.isRecording {
            return "Stop Recording"
        }
        if manager.countdownSeconds > 0 {
            return "Record  (\(manager.countdownSeconds)s countdown)"
        }
        return "Start Recording"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                showingRecents.toggle()
            } label: {
                Label("Recents", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Recent Recordings")

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Quit ScreenLapse")
        }
    }

    // MARK: - Helpers

    private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.openSettings()
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
