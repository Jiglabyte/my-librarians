import SwiftUI

struct NormalModeView: View {
    @EnvironmentObject var manager: RecordingManager

    var currentFPS: Int {
        if case .normal(let fps) = manager.mode { return fps }
        return 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Frame rate
            compactLabel("Frame Rate")
            Picker("", selection: Binding(
                get: { currentFPS },
                set: { manager.mode = .normal(fps: $0) }
            )) {
                ForEach(RecordingMode.normalFPSOptions, id: \.self) { fps in
                    Text("\(fps) fps").tag(fps)
                }
            }
            .pickerStyle(.segmented)
            .disabled(manager.isRecording || manager.isPreparing)

            // Quality + Resolution
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    compactLabel("Quality")
                    Picker("", selection: Binding(
                        get: { manager.quality },
                        set: { manager.quality = $0 }
                    )) {
                        Text("Low").tag(QualityPreset.low)
                        Text("Med").tag(QualityPreset.medium)
                        Text("High").tag(QualityPreset.high)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 3) {
                    compactLabel("Resolution")
                    Picker("", selection: Binding(
                        get: { manager.resolution },
                        set: { manager.resolution = $0 }
                    )) {
                        ForEach(OutputResolution.allCases) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }
            }
            .disabled(manager.isRecording || manager.isPreparing)

            // Toggles
            HStack(spacing: 14) {
                Toggle("System Audio", isOn: $manager.captureSystemAudio)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Mic", isOn: $manager.captureMic)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Webcam", isOn: $manager.captureWebcam)
                    .toggleStyle(.checkbox).font(.caption)
            }
            .disabled(manager.isRecording || manager.isPreparing)
        }
    }

    private func compactLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
