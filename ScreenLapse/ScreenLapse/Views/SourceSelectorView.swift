import SwiftUI

struct SourceSelectorView: View {
    @EnvironmentObject var manager: RecordingManager
    @State private var showRegionPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Capture source")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await manager.refreshSources() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh sources")
            }

            Picker("", selection: Binding(
                get: { manager.selectedSource },
                set: { manager.selectedSource = $0 }
            )) {
                ForEach(manager.availableSources, id: \.self) { src in
                    Text(src.displayName).tag(Optional(src))
                }
                if manager.availableSources.isEmpty {
                    Text("No sources").tag(Optional<CaptureSource>(nil))
                }
            }
            .labelsHidden()
            .disabled(manager.isRecording || manager.isPreparing)

            Button {
                RegionSelectorOverlay.pickRegion { result in
                    if let result {
                        Task { @MainActor in
                            manager.selectedSource = .region(rect: result.rect,
                                                             displayID: result.displayID)
                        }
                    }
                }
            } label: {
                Label("Select Region…", systemImage: "selection.pin.in.out")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(manager.isRecording || manager.isPreparing)
        }
    }
}
