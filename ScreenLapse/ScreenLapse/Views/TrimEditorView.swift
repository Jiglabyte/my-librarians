import SwiftUI
import AVKit
import AVFoundation

struct TrimEditorView: View {
    let url: URL
    let originalDuration: TimeInterval
    let onClose: (URL?) -> Void

    @State private var player: AVPlayer
    @State private var duration: Double = 0
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @State private var exporting = false
    @State private var errorText: String?

    init(url: URL, originalDuration: TimeInterval, onClose: @escaping (URL?) -> Void) {
        self.url = url
        self.originalDuration = originalDuration
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(spacing: 12) {
            VideoPlayer(player: player)
                .frame(minHeight: 320)
                .onAppear {
                    loadDuration()
                    player.play()
                }

            VStack(alignment: .leading, spacing: 6) {
                Text("Trim").font(.headline)

                HStack {
                    Text("Start: \(formatTime(startTime))")
                        .font(.system(.body, design: .monospaced))
                    Slider(value: $startTime, in: 0...max(duration, 0.1)) { _ in
                        if startTime > endTime - 0.1 { startTime = max(0, endTime - 0.1) }
                        seek(to: startTime)
                    }
                }

                HStack {
                    Text("End:   \(formatTime(endTime))")
                        .font(.system(.body, design: .monospaced))
                    Slider(value: $endTime, in: 0...max(duration, 0.1)) { _ in
                        if endTime < startTime + 0.1 { endTime = min(duration, startTime + 0.1) }
                        seek(to: endTime)
                    }
                }
                Text("Output: \(formatTime(endTime - startTime))  ·  Original: \(formatTime(duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            if let err = errorText {
                Text(err).foregroundColor(.red).font(.caption)
            }

            HStack {
                Button("Cancel") {
                    player.pause()
                    onClose(nil)
                }
                Spacer()
                Button {
                    Task { await export(replace: false) }
                } label: {
                    Text("Save as new")
                }
                Button {
                    Task { await export(replace: true) }
                } label: {
                    Text("Replace original")
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding([.horizontal, .bottom], 16)
            .disabled(exporting)

            if exporting {
                ProgressView("Exporting…")
            }
        }
    }

    private func loadDuration() {
        let asset = AVURLAsset(url: url)
        Task {
            let d = (try? await asset.load(.duration).seconds) ?? originalDuration
            await MainActor.run {
                duration = d
                endTime = d
            }
        }
    }

    private func seek(to time: Double) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func export(replace: Bool) async {
        exporting = true
        defer { exporting = false }

        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetPassthrough) else {
            errorText = "Could not create export session"
            return
        }
        let outFile = replace
            ? url.deletingLastPathComponent()
                 .appendingPathComponent("trim-\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            : url.deletingLastPathComponent()
                 .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-trimmed.\(url.pathExtension)")

        try? FileManager.default.removeItem(at: outFile)
        export.outputURL = outFile
        let fileType: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        export.outputFileType = fileType

        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let end = CMTime(seconds: endTime, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: start, end: end)

        await export.export()
        if export.status == .completed {
            if replace {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.moveItem(at: outFile, to: url)
                onClose(url)
            } else {
                onClose(outFile)
            }
        } else {
            errorText = "Export failed: \(export.error?.localizedDescription ?? "unknown")"
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        if t.isNaN || t.isInfinite { return "0:00.0" }
        let total = max(0, t)
        let m = Int(total) / 60
        let s = total - Double(m * 60)
        return String(format: "%d:%05.2f", m, s)
    }
}
