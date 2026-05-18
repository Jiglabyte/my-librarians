// ScreenLapsePro
// Views/SettingsView.swift
// Full app preferences sheet

import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // Output
    @AppStorage(PrefsKey.outputFolder)        private var outputFolder       = Prefs.outputFolder

    // Video
    @AppStorage(PrefsKey.useHEVC)             private var useHEVC            = true
    @AppStorage(PrefsKey.videoBitratePreset)  private var bitrateRaw         = BitratePreset.medium.rawValue
    @AppStorage(PrefsKey.frameRate)           private var frameRate          = 30
    @AppStorage(PrefsKey.timeLapseMultiplier) private var timeLapseMultiplier = 15

    // Audio
    @AppStorage(PrefsKey.recordSystemAudio)   private var recordSystemAudio  = false
    @AppStorage(PrefsKey.recordMicrophone)    private var recordMicrophone   = false

    // Capture
    @AppStorage(PrefsKey.showCursor)          private var showCursor         = true

    // Recording behavior
    @AppStorage(PrefsKey.countdownSeconds)    private var countdownSeconds   = 3
    @AppStorage(PrefsKey.autoStopMinutes)     private var autoStopMinutes    = 0
    @AppStorage(PrefsKey.preventSleep)        private var preventSleep       = true

    // Display
    @AppStorage(PrefsKey.showFloatingPill)    private var showFloatingPill   = true
    @AppStorage(PrefsKey.showStatusBarTimer)  private var showStatusBarTimer = true

    private let fpsOptions:        [Int] = [24, 30, 60]
    private let multiplierOptions: [Int] = [5, 10, 15, 30, 60]
    private let countdownOptions:  [Int] = [0, 3, 5, 10]
    private let autoStopOptions:   [Int] = [0, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: Output
                    section("Output") {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(abbreviatedPath(outputFolder))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Change…") { chooseOutputFolder() }
                                .font(.system(size: 12))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }

                    divider()

                    // MARK: Audio
                    section("Audio") {
                        VStack(spacing: 10) {
                            toggleRow(
                                label: "Record system audio",
                                sublabel: "Captures all sound playing on your Mac",
                                icon: "speaker.wave.2.fill",
                                isOn: $recordSystemAudio
                            )
                            toggleRow(
                                label: "Record microphone",
                                sublabel: "Captures your voice via built-in or external mic",
                                icon: "mic.fill",
                                isOn: $recordMicrophone
                            )
                            if recordSystemAudio || recordMicrophone {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Text("Audio is saved as AAC 192 kbps alongside the video.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    divider()

                    // MARK: Video Quality
                    section("Video Quality") {
                        VStack(spacing: 10) {
                            // Codec
                            HStack {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Codec")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $useHEVC) {
                                    Text("HEVC (H.265)").tag(true)
                                    Text("H.264").tag(false)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 130)
                            }

                            // Bitrate
                            HStack {
                                Image(systemName: "dial.medium")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Bitrate")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $bitrateRaw) {
                                    ForEach(BitratePreset.allCases, id: \.rawValue) { preset in
                                        Text(preset.label).tag(preset.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 140)
                            }

                            // Frame rate
                            HStack {
                                Image(systemName: "timer")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Default frame rate")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $frameRate) {
                                    ForEach(fpsOptions, id: \.self) { fps in
                                        Text("\(fps) fps").tag(fps)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 130)
                            }
                        }
                    }

                    divider()

                    // MARK: Capture
                    section("Capture") {
                        VStack(spacing: 10) {
                            toggleRow(label: "Show cursor in recordings",
                                      icon: "cursorarrow",
                                      isOn: $showCursor)

                            // Default time-lapse speed
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    Text("Default time-lapse speed")
                                        .font(.system(size: 13))
                                }
                                HStack(spacing: 5) {
                                    ForEach(multiplierOptions, id: \.self) { mult in
                                        let sel = mult == timeLapseMultiplier
                                        Button { timeLapseMultiplier = mult } label: {
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
                                    }
                                }
                            }
                        }
                    }

                    divider()

                    // MARK: Recording Behavior
                    section("Recording Behavior") {
                        VStack(spacing: 10) {
                            // Countdown
                            HStack {
                                Image(systemName: "timer.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Countdown before recording")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $countdownSeconds) {
                                    Text("None").tag(0)
                                    ForEach([3, 5, 10], id: \.self) { s in
                                        Text("\(s)s").tag(s)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 150)
                            }

                            // Auto-stop
                            HStack {
                                Image(systemName: "stop.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text("Auto-stop after")
                                    .font(.system(size: 13))
                                Spacer()
                                Picker("", selection: $autoStopMinutes) {
                                    Text("Off").tag(0)
                                    Text("5 min").tag(5)
                                    Text("10 min").tag(10)
                                    Text("15 min").tag(15)
                                    Text("30 min").tag(30)
                                    Text("60 min").tag(60)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 100)
                            }

                            toggleRow(
                                label: "Prevent screen sleep",
                                sublabel: "Keeps your Mac awake while recording",
                                icon: "moon.zzz",
                                isOn: $preventSleep
                            )
                        }
                    }

                    divider()

                    // MARK: Display
                    section("Display") {
                        VStack(spacing: 10) {
                            toggleRow(
                                label: "Floating recording pill",
                                sublabel: "Shows timer and stop button on screen during recording",
                                icon: "rectangle.and.pencil.and.ellipsis",
                                isOn: $showFloatingPill
                            )
                            toggleRow(
                                label: "Live timer in menu bar",
                                sublabel: "Replaces the icon with a running clock while recording",
                                icon: "menubar.rectangle",
                                isOn: $showStatusBarTimer
                            )
                        }
                    }

                    divider()

                    // MARK: About
                    HStack {
                        Spacer()
                        VStack(spacing: 3) {
                            Text("ScreenLapse Pro")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(appVersion)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func divider() -> some View {
        Divider().padding(.horizontal, 18)
    }

    @ViewBuilder
    private func toggleRow(label: String,
                           sublabel: String? = nil,
                           icon: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13))
                if let sub = sublabel {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.canCreateDirectories    = true
        panel.allowsMultipleSelection = false
        panel.prompt  = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private var appVersion: String {
        let ver   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(ver) (\(build))"
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
