import SwiftUI

struct MenuBarPopover: View {
    @EnvironmentObject var manager: RecordingManager
    @State private var modeTabIndex: Int = 0
    @State private var showingRecents = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("", selection: $modeTabIndex) {
                Text("Normal").tag(0)
                Text("Time-lapse").tag(1)
            }
            .pickerStyle(.segmented)
            .disabled(manager.isRecording || manager.isPreparing)
            .onChange(of: modeTabIndex) { newValue in
                manager.mode = (newValue == 0) ? .normalDefault : .timeLapseDefault
            }

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

            recordButton

            if let err = manager.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            HStack {
                Button {
                    showingRecents.toggle()
                } label: {
                    Label("Recent", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit ScreenLapse")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            modeTabIndex = manager.mode.isTimeLapse ? 1 : 0
            Task { await manager.refreshSources() }
        }
        .popover(isPresented: $showingRecents, arrowEdge: .trailing) {
            RecentRecordingsView()
                .frame(width: 360, height: 380)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "record.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
            Text("ScreenLapse")
                .font(.headline)
            Spacer()
            if manager.isRecording {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("REC")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var liveStats: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Elapsed").font(.caption2).foregroundColor(.secondary)
                Text(manager.formattedElapsed)
                    .font(.system(.body, design: .monospaced))
            }
            if manager.mode.isTimeLapse {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Output").font(.caption2).foregroundColor(.secondary)
                    Text(formatDuration(manager.projectedOutputDuration))
                        .font(.system(.body, design: .monospaced))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Size").font(.caption2).foregroundColor(.secondary)
                Text(manager.formattedFileSize)
                    .font(.system(.body, design: .monospaced))
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

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
            HStack {
                Image(systemName: manager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                Text(buttonLabel)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(manager.isRecording ? .red : .accentColor)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(manager.isPreparing)
    }

    private var buttonLabel: String {
        if manager.isPreparing { return "Preparing…" }
        if manager.isRecording { return "Stop Recording" }
        return "Start Recording"
    }

    private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
