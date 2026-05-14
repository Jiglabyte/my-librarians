import SwiftUI

struct NormalModeView: View {
    @EnvironmentObject var manager: RecordingManager

    var currentFPS: Int {
        if case .normal(let fps) = manager.mode { return fps }
        return 30
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Frame rate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Picker("", selection: Binding(
                get: { currentFPS },
                set: { manager.mode = .normal(fps: $0) }
            )) {
                ForEach(RecordingMode.normalFPSOptions, id: \.self) { fps in
                    Text("\(fps)").tag(fps)
                }
            }
            .pickerStyle(.segmented)
            .disabled(manager.isRecording || manager.isPreparing)

            HStack(spacing: 16) {
                Toggle("System Audio", isOn: $manager.captureSystemAudio)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Mic", isOn: $manager.captureMic)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .disabled(manager.isRecording || manager.isPreparing)
        }
    }
}
