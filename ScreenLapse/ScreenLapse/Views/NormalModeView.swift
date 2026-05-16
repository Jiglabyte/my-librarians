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
            SegmentedTabs(selection: Binding(
                get: { currentFPS },
                set: { manager.mode = .normal(fps: $0) }
            ),
            labels: RecordingMode.normalFPSOptions.map { ("\($0) fps", $0) },
            isDisabled: manager.isRecording || manager.isPreparing)

            // Quality + Resolution
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    compactLabel("Quality")
                    SegmentedTabs(selection: Binding(
                        get: { manager.quality },
                        set: { manager.quality = $0 }
                    ),
                    labels: [("Low", QualityPreset.low),
                             ("Med", QualityPreset.medium),
                             ("High", QualityPreset.high)])
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
