import AppKit
import SwiftUI

@MainActor
enum CountdownOverlayController {
    private static var controllers: [NSWindowController] = []

    static func runCountdown(seconds: Int) async {
        guard seconds > 0 else { return }

        let windows = NSScreen.screens.map { screen -> NSWindowController in
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: CountdownView(seconds: seconds))
            panel.setFrame(screen.frame, display: true)
            panel.orderFrontRegardless()
            return NSWindowController(window: panel)
        }
        controllers = windows

        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        for controller in controllers {
            controller.window?.close()
        }
        controllers.removeAll()
    }
}

private struct CountdownView: View {
    let seconds: Int
    @State private var remaining: Int

    init(seconds: Int) {
        self.seconds = seconds
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            Text("\(remaining)")
                .font(.system(size: 240, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(radius: 16)
                .transition(.scale.combined(with: .opacity))
                .id(remaining)
        }
        .onAppear { tick() }
    }

    private func tick() {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeOut(duration: 0.4)) {
                remaining -= 1
            }
            tick()
        }
    }
}
