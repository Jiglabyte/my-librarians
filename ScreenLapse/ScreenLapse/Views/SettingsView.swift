import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var manager: RecordingManager

    var body: some View {
        TabView {
            recordingTab.tabItem { Label("Recording", systemImage: "video") }
            videoTab.tabItem { Label("Video", systemImage: "wand.and.stars") }
            overlaysTab.tabItem { Label("Overlays", systemImage: "person.crop.square") }
            generalTab.tabItem { Label("General", systemImage: "gear") }
            aboutTab.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .padding(20)
    }

    // MARK: - Recording

    private var recordingTab: some View {
        Form {
            Section("Output") {
                HStack {
                    TextField("Folder", text: Binding(
                        get: { manager.outputFolderURL.path },
                        set: { manager.outputFolderPath = $0 }
                    ))
                    .disabled(true)
                    Button("Change…") { chooseOutputFolder() }
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([manager.outputFolderURL]) }
                }
                Picker("Container", selection: $manager.useMOV) {
                    Text("MP4 (.mp4)").tag(false)
                    Text("QuickTime (.mov)").tag(true)
                }
            }

            Section("Audio (Normal mode only)") {
                Toggle("Capture system audio", isOn: $manager.captureSystemAudio)
                Toggle("Capture microphone", isOn: $manager.captureMic)
            }

            Section("Cursor") {
                Toggle("Show cursor in recording", isOn: $manager.showsCursor)
                Toggle("Highlight mouse clicks", isOn: $manager.highlightClicks)
            }
        }
    }

    // MARK: - Video

    private var videoTab: some View {
        Form {
            Section("Codec") {
                Picker("Codec", selection: Binding(
                    get: { manager.codec },
                    set: { manager.codec = $0 }
                )) {
                    ForEach(CodecChoice.allCases) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }
            }
            Section("Quality") {
                Picker("Preset", selection: Binding(
                    get: { manager.quality },
                    set: { manager.quality = $0 }
                )) {
                    ForEach(QualityPreset.allCases) { q in
                        Text(q.displayName).tag(q)
                    }
                }
                Text("Higher quality means larger files. Medium is a good balance.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("Resolution") {
                Picker("Output resolution", selection: Binding(
                    get: { manager.resolution },
                    set: { manager.resolution = $0 }
                )) {
                    ForEach(OutputResolution.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                Text("Native records the source at its real size — best quality.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Overlays

    private var overlaysTab: some View {
        Form {
            Section("Webcam Overlay") {
                Toggle("Enable webcam picture-in-picture", isOn: $manager.captureWebcam)
                Picker("Corner", selection: Binding(
                    get: { manager.webcamCorner },
                    set: { manager.webcamCorner = $0 }
                )) {
                    ForEach(WebcamCorner.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .disabled(!manager.captureWebcam)
                HStack {
                    Text("Size: \(Int(manager.webcamRelativeHeight * 100))%")
                    Slider(value: $manager.webcamRelativeHeight, in: 0.10...0.40)
                }
                .disabled(!manager.captureWebcam)
            }
            Section("Click highlighting") {
                Toggle("Show ripples on mouse clicks", isOn: $manager.highlightClicks)
                if manager.highlightClicks {
                    Button("Open Accessibility Settings…") {
                        PermissionChecker.openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section("Before recording") {
                Picker("Countdown", selection: $manager.countdownSeconds) {
                    Text("Off").tag(0)
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                }
            }
            Section("Permissions") {
                permissionRow(title: "Screen Recording",
                              granted: PermissionChecker.screenRecordingStatus() == .granted) {
                    PermissionChecker.openScreenRecordingSettings()
                }
                permissionRow(title: "Camera",
                              granted: PermissionChecker.cameraStatus() == .granted) {
                    PermissionChecker.openCameraSettings()
                }
                permissionRow(title: "Microphone",
                              granted: PermissionChecker.micStatus() == .granted) {
                    PermissionChecker.openMicSettings()
                }
            }
            Section("Global Hotkey") {
                Text("Toggle recording: ⌃⇧R")
                    .font(.system(.body, design: .monospaced))
                Text("Hotkey is fixed for now; the keybinding is registered globally and works even when the app is in the background.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func permissionRow(title: String,
                               granted: Bool,
                               openSettings: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(title)
            Spacer()
            Button(granted ? "OK" : "Open Settings…") {
                openSettings()
            }
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenLapse")
                .font(.title)
                .bold()
            Text("A free, open-source native macOS screen recorder with built-in time-lapse mode. HEVC hardware encoding produces tiny files at the same quality as QuickTime.")
                .font(.body)
            Text("Inspired by Tap Record. MIT License.")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            manager.outputFolderPath = url.path
        }
    }
}
