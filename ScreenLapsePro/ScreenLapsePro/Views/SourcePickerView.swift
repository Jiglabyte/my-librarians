// ScreenLapsePro
// Views/SourcePickerView.swift
// Lets the user pick a display or window as the capture source

import SwiftUI
import ScreenCaptureKit

// MARK: - SourcePickerView

struct SourcePickerView: View {

    /// Called when the user selects a source. Passes the filter and a human-readable label.
    var onSelect: (SCContentFilter, String) -> Void

    @State private var content: SCShareableContent?
    @State private var loadError: String?
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose Source")
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            Group {
                if isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading sources…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                } else if let errorMsg = loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundStyle(.orange)
                        Text(errorMsg)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding()
                } else if let content {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            displaySection(content.displays)
                            windowSection(content.windows)
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 340)
                } else {
                    Text("No sources found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding()
                }
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .task {
            await loadContent()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func displaySection(_ displays: [SCDisplay]) -> some View {
        if displays.isEmpty {
            EmptyView()
        } else {
            sectionHeader("Displays")

            ForEach(Array(displays.enumerated()), id: \.offset) { index, display in
                let label = "Display \(index + 1)"
                SourceRow(
                    icon: "display",
                    title: label,
                    subtitle: "\(display.width) × \(display.height)"
                ) {
                    let filter = SCContentFilter(
                        display: display,
                        excludingApplications: [],
                        exceptingWindows: []
                    )
                    onSelect(filter, label)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func windowSection(_ windows: [SCWindow]) -> some View {
        let eligible = windows.filter { window in
            guard let title = window.title, !title.isEmpty else { return false }
            // Exclude ScreenLapsePro's own windows
            if let appName = window.owningApplication?.applicationName,
               appName.localizedCaseInsensitiveContains("ScreenLapsePro") ||
               appName.localizedCaseInsensitiveContains("ScreenLapse Pro") {
                return false
            }
            return true
        }

        if !eligible.isEmpty {
            sectionHeader("Windows")

            ForEach(eligible, id: \.windowID) { window in
                let title    = window.title ?? "Untitled"
                let appName  = window.owningApplication?.applicationName ?? ""
                let subtitle = appName.isEmpty ? nil : appName

                SourceRow(
                    icon: "macwindow",
                    title: title,
                    subtitle: subtitle
                ) {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    onSelect(filter, title)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: - Load

    private func loadContent() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            content = result
        } catch {
            loadError = "Could not load sources: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - SourceRow

private struct SourceRow: View {

    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in isHovered = over }
    }
}
