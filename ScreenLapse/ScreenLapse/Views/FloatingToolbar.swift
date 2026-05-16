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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
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
        }).environmentObject(manager))
        view.frame = panel.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(view)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let origin = CGPoint(x: frame.midX - 160, y: frame.maxY - 96)
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
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((manager.isPaused ? Color.orange : Color.red).opacity(0.35))
                    .frame(width: 22, height: 22)
                    .scaleEffect(manager.isPaused ? 1.0 : pulseScale)
                Circle()
                    .fill(manager.isPaused ? Color.orange : Color.red)
                    .frame(width: 11, height: 11)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.5
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(badgeColor)
                        .cornerRadius(5)
                    Text(manager.formattedElapsed)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                HStack(spacing: 6) {
                    Text(manager.formattedFileSize)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                    Text("·")
                        .foregroundColor(.white.opacity(0.4))
                    Text("⌃⇧R to stop")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 4)

            Button {
                if manager.isPaused {
                    manager.resumeRecording()
                } else {
                    manager.pauseRecording()
                }
            } label: {
                Image(systemName: manager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(9)
                    .background(manager.isPaused ? Color.green : Color.orange)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(manager.isPaused ? "Resume recording" : "Pause recording")

            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording (⌃⇧R)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .padding(2)
    }

    private var badgeText: String {
        if manager.isPaused { return "PAUSED" }
        switch manager.mode {
        case .normal(let fps): return "REC \(fps)"
        case .timeLapse(let mult): return "⏵⏵ \(mult)×"
        }
    }

    private var badgeColor: Color {
        if manager.isPaused { return .orange.opacity(0.9) }
        switch manager.mode {
        case .normal: return .red.opacity(0.88)
        case .timeLapse: return .orange.opacity(0.9)
        }
    }
}
