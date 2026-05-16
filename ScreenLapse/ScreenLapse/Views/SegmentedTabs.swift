import SwiftUI

// Drop-in replacement for SwiftUI's Picker(.segmented). The system control on
// macOS 26 is backed by Apple's DesignLibrary, which crashes during view body
// updates inside @MainActor-isolated environment-object reads
// (swift_task_isMainExecutorImpl → objc_opt_class on a bad pointer). This
// rebuilds the look from plain Buttons, which never reach DesignLibrary.
struct SegmentedTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Option]
    var isDisabled: Bool = false

    struct Option: Identifiable {
        let label: String
        let value: Value
        var id: Value { value }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let isSelected = selection == option.value
                Button {
                    guard !isDisabled else { return }
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected
                                      ? Color.accentColor.opacity(0.28)
                                      : Color.clear)
                        )
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        )
        .opacity(isDisabled ? 0.5 : 1.0)
        .allowsHitTesting(!isDisabled)
    }
}

extension SegmentedTabs {
    init(selection: Binding<Value>,
         labels: [(String, Value)],
         isDisabled: Bool = false) {
        self._selection = selection
        self.options = labels.map { Option(label: $0.0, value: $0.1) }
        self.isDisabled = isDisabled
    }
}
