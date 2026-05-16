import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var manager: RecordingManager

    var body: some View {
        TabView {
            recordingTab.tabItem { Label("Recording", systemImage: "video") }
            videoTab.tabItem    { Label("Video",     systemImage: "film") }
            overlaysTab.tabItem { Label("Overlays",  systemImage: "person.crop.square") }
            generalTab.tabItem  { Label("General",   systemImage: "gear") }
            aboutTab.tabItem    { Label("About",     systemImage: "info.circle") }
        }
        .frame(width: 520, height: 480)
    }

    // MARK: - Recording tab

    private var recordingTab: some View {
        Form {
            Section("Save location") {
                HStack {
                    TextField("", text: Binding(
                        get: { manager.outputFolderURL.path },
                        set: { manager.outputFolderPath = $0 }
                    ))
                    .disabled(true)
                    .foregroundColor(.secondary)
                    Button("Change…") { chooseOutputFolder() }
                    Button("Show") {
                        NSWorkspace.shared.activateFileViewerSelecting([manager.outputFolderURL])
                    }
                }
            }

            Section("Audio  (Normal mode only)") {
                Toggle("System audio",  isOn: $manager.captureSystemAudio)
                Toggle("Microphone",    isOn: $manager.captureMic)
            }

            Section("Cursor") {
                Toggle("Show cursor in recording",   isOn: $manager.showsCursor)
                Toggle("Highlight mouse clicks",     isOn: $manager.highlightClicks)
            }
        }
    }

    // MARK: - Video tab

    private var videoTab: some View {
        Form {
            // ── Format ──────────────────────────────────────────────────────
            Section {
                ForEach(CodecChoice.allCases) { codec in
                    codecRow(codec)
                }
            } header: {
                Text("Format")
            } footer: {
                Text(formatFooter)
                    .foregroundColor(.secondary)
            }

            // ── Quality  (not shown for ProRes — quality is fixed by variant) ──
            if manager.codec != .proRes {
                Section {
                    Picker("", selection: Binding(
                        get: { manager.quality },
                        set: { manager.quality = $0 }
                    )) {
                        ForEach(QualityPreset.allCases) { q in
                            Text(q.settingsLabel).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(qualityFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Quality")
                }
            }

            // ── Resolution ───────────────────────────────────────────────────
            Section("Resolution") {
                Picker("", selection: Binding(
                    get: { manager.resolution },
                    set: { manager.resolution = $0 }
                )) {
                    ForEach(OutputResolution.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Native records at the screen's actual pixel size. Use 1080p or 720p to reduce file size for large displays.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // A tappable codec card — tapping selects that codec.
    private func codecRow(_ codec: CodecChoice) -> some View {
        Button {
            manager.codec = codec
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: manager.codec == codec
                      ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(manager.codec == codec ? .accentColor : .secondary)
                    .font(.system(size: 17))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(codec.shortName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(codec.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private var formatFooter: String {
        switch manager.codec {
        case .hevc:   return "Files save as .mp4  ·  Toggle .mov below if you need QuickTime compatibility"
        case .h264:   return "Files save as .mp4  ·  Plays on any device without transcoding"
        case .proRes: return "Files save as .mov  ·  Container is fixed — ProRes requires QuickTime"
        }
    }

    private var qualityFooter: String {
        let res = manager.resolution.targetHeight ?? 1080
        switch manager.quality {
        case .low:    return "Smaller files, softer on fast motion or fine text  ·  ~15 MB/min at \(res)p"
        case .medium: return "Good balance of size and sharpness  ·  ~60 MB/min at \(res)p"
        case .high:   return "Sharp on all content  ·  ~190 MB/min at \(res)p"
        case .max:    return "Quality-based VBR — same engine QuickTime uses. Bitrate adapts to content; files may be 200–600 MB/min."
        }
    }

    // MARK: - Overlays tab

    private var overlaysTab: some View {
        Form {
            Section("Webcam overlay") {
                Toggle("Enable picture-in-picture", isOn: $manager.captureWebcam)
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
            Section("Click ripples") {
                Toggle("Show ripple on every mouse click", isOn: $manager.highlightClicks)
                if manager.highlightClicks {
                    Button("Open Accessibility Settings…") {
                        PermissionChecker.openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - General tab

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
            Section("File format") {
                Toggle("Save HEVC / H.264 as .mov instead of .mp4", isOn: $manager.useMOV)
                Text("Leave off unless you specifically need .mov. ProRes always uses .mov regardless.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            Section("Global hotkey") {
                Text("⌃⇧R  —  start / stop from anywhere")
                    .font(.system(.body, design: .monospaced))
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
            if !granted {
                Button("Open Settings…") { openSettings() }
            }
        }
    }

    // MARK: - About tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ScreenLapse")
                .font(.title).bold()
            Text("Free, native macOS screen recorder with time-lapse mode. HEVC hardware encoding keeps file sizes 5–10× smaller than QuickTime at the same visual quality.")
            Text("MIT License · Open source")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
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
