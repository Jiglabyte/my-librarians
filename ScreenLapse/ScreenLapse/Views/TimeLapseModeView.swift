import SwiftUI

struct TimeLapseModeView: View {
    @EnvironmentObject var manager: RecordingManager

    var currentMultiplier: Int {
        if case .timeLapse(let m) = manager.mode { return m }
        return 15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Time-lapse speed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(currentMultiplier)× faster")
                    .font(.caption.weight(.semibold))
            }
            Picker("", selection: Binding(
                get: { currentMultiplier },
                set: { manager.mode = .timeLapse(multiplier: $0) }
            )) {
                ForEach(RecordingMode.timeLapseMultipliers, id: \.self) { m in
                    Text("\(m)×").tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(manager.isRecording || manager.isPreparing)

            Text("1 hour of work → \(estimatedOutput(multiplier: currentMultiplier))")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Audio is disabled in time-lapse mode.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func estimatedOutput(multiplier: Int) -> String {
        let seconds = 3600 / multiplier
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 { return "\(m)m \(s)s of video" }
        return "\(s)s of video"
    }
}
