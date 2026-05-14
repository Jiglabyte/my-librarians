import AppKit
import SwiftUI

final class FloatingToolbarController {
    private var panel: NSPanel?
    private let manager: RecordingManager
    private let onStop: () -> Void

    init(manager: RecordingManager, onStop: @escaping () -> Void) {
        self.manager = manager
        self.onStop = onStop
    }

    func show() {
        if panel != nil { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let view = NSHostingView(rootView: FloatingToolbarView(onStop: { [weak self] in
            self?.onStop()
        })
            .environmentObject(manager))
        view.frame = panel.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(view)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = CGPoint(x: frame.midX - 140, y: frame.maxY - 90)
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct FloatingToolbarView: View {
    @EnvironmentObject var manager: RecordingManager
    let onStop: () -> Void
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(pulse ? 0.6 : 1.0))
                    .frame(width: 14, height: 14)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(badgeText)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.85))
                        .cornerRadius(4)
                    Text(manager.formattedElapsed)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text(manager.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer(minLength: 4)

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(2)
    }

    private var badgeText: String {
        switch manager.mode {
        case .normal: return "REC"
        case .timeLapse(let mult): return "⏵⏵ \(mult)×"
        }
    }
}
