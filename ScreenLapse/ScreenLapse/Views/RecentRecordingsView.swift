import SwiftUI
import AppKit

struct RecentRecordingsView: View {
    @State private var items: [RecentRecording] = []
    @State private var trimming: RecentRecording?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Recordings")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            if items.isEmpty {
                VStack {
                    Spacer()
                    Text("No recordings yet")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(items) { item in
                            row(for: item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear {
            RecentRecordings.shared.reload()
            items = RecentRecordings.shared.items
        }
        .sheet(item: $trimming) { item in
            TrimEditorView(url: item.url, originalDuration: item.outputDuration) { newURL in
                trimming = nil
                if newURL != nil {
                    items = RecentRecordings.shared.items
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }

    private func row(for item: RecentRecording) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "film")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .lineLimit(1)
                    .font(.system(.body, design: .default))
                HStack(spacing: 8) {
                    Text(item.modeLabel)
                    Text("•")
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    Text("•")
                    Text(item.capturedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                actionButton("scissors", help: "Trim") { trimming = item }
                actionButton("square.and.arrow.up", help: "Share") { share(url: item.url) }
                actionButton("folder", help: "Reveal in Finder") {
                    ShareHelper.revealInFinder(item.url)
                }
                actionButton("trash", help: "Delete") { delete(item) }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
        )
        .contextMenu {
            Button("Open") { ShareHelper.openWithDefaultApp(item.url) }
            Button("Reveal in Finder") { ShareHelper.revealInFinder(item.url) }
            Button("Trim…") { trimming = item }
            Divider()
            Button(role: .destructive) { delete(item) } label: { Text("Delete") }
        }
    }

    private func actionButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func share(url: URL) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first,
              let contentView = window.contentView else { return }
        ShareHelper.share(url: url, from: contentView)
    }

    private func delete(_ item: RecentRecording) {
        try? FileManager.default.removeItem(at: item.url)
        RecentRecordings.shared.remove(id: item.id)
        items = RecentRecordings.shared.items
    }
}
