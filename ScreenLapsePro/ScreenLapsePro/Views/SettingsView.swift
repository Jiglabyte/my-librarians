// ScreenLapsePro
// Views/SettingsView.swift
// App preferences sheet

import SwiftUI
import AppKit

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    // Preferences backed by UserDefaults via @AppStorage
    @AppStorage(PrefsKey.outputFolder)         private var outputFolder        = Prefs.outputFolder
    @AppStorage(PrefsKey.showCursor)           private var showCursor          = true
    @AppStorage(PrefsKey.useHEVC)              private var useHEVC             = true
    @AppStorage(PrefsKey.frameRate)            private var frameRate           = 30
    @AppStorage(PrefsKey.timeLapseMultiplier)  private var timeLapseMultiplier = 15

    private let fpsOptions:         [Int] = [24, 30, 60]
    private let multiplierOptions:  [Int] = [5, 10, 15, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
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

                    // MARK: Output Folder
                    settingSection("Output Folder") {
                        HStack(spacing: 8) {
                            Text(abbreviatedPath(outputFolder))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Change…") {
                                chooseOutputFolder()
                            }
                            .font(.system(size: 12))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    settingDivider()

                    // MARK: Capture Options
                    settingSection("Capture") {
                        VStack(spacing: 10) {
                            toggleRow(
                                label: "Show cursor in recordings",
                                systemImage: "cursorarrow",
                                isOn: $showCursor
                            )
                            toggleRow(
                                label: "Use HEVC encoding",
                                systemImage: "film.stack",
                                isOn: $useHEVC,
                                hint: "Smaller files · H.265"
                            )
                        }
                    }

                    settingDivider()

                    // MARK: Default Frame Rate
                    settingSection("Default Frame Rate") {
                        Picker("", selection: $frameRate) {
                            ForEach(fpsOptions, id: \.self) { fps in
                                Text("\(fps) fps").tag(fps)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    settingDivider()

                    // MARK: Default Time-Lapse Speed
                    settingSection("Default Time-Lapse Speed") {
                        HStack(spacing: 6) {
                            ForEach(multiplierOptions, id: \.self) { mult in
                                let selected = mult == timeLapseMultiplier
                                Button {
                                    timeLapseMultiplier = mult
                                } label: {
                                    Text("\(mult)x")
                                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                                        .foregroundStyle(selected ? Color.white : Color.primary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    settingDivider()

                    // MARK: About / Version
                    HStack {
                        Spacer()
                        VStack(spacing: 2) {
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
        .frame(width: 320)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
    private func settingDivider() -> some View {
        Divider()
            .padding(.horizontal, 18)
    }

    @ViewBuilder
    private func toggleRow(label: String,
                           systemImage: String,
                           isOn: Binding<Bool>,
                           hint: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                if let h = hint {
                    Text(h)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder where recordings will be saved."

        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
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
