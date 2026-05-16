import SwiftUI

struct TimeLapseModeView: View {
    @EnvironmentObject var manager: RecordingManager

    var currentMultiplier: Int {
        if case .timeLapse(let m) = manager.mode { return m }
        return 15
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Speed picker
            HStack {
                compactLabel("Speed")
                Spacer()
                Text("\(currentMultiplier)× faster")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
            SegmentedTabs(selection: Binding(
                get: { currentMultiplier },
                set: { manager.mode = .timeLapse(multiplier: $0) }
            ),
            labels: RecordingMode.timeLapseMultipliers.map { ("\($0)×", $0) },
            isDisabled: manager.isRecording || manager.isPreparing)

            // Quick estimate
            HStack(spacing: 16) {
                estimateCell(realMinutes: 10, multiplier: currentMultiplier)
                estimateCell(realMinutes: 60, multiplier: currentMultiplier)
                estimateCell(realMinutes: 480, multiplier: currentMultiplier)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.07))
            .cornerRadius(7)

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

            HStack(spacing: 4) {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Audio disabled in time-lapse mode")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func estimateCell(realMinutes: Int, multiplier: Int) -> some View {
        let outputSec = (realMinutes * 60) / multiplier
        let label: String
        if realMinutes >= 60 {
            label = "\(realMinutes / 60)h real"
        } else {
            label = "\(realMinutes)m real"
        }
        return VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(formatSec(outputSec))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatSec(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        return "\(sec / 60)m\(sec % 60 > 0 ? " \(sec % 60)s" : "")"
    }

    private func compactLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
