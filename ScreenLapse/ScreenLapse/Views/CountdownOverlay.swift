import AppKit
import SwiftUI

@MainActor
enum CountdownOverlayController {
    private static var controllers: [NSWindowController] = []
    private static var finishContinuation: CheckedContinuation<Void, Never>?
    private static var autoFinishTask: Task<Void, Never>?

    static func runCountdown(seconds: Int) async {
        guard seconds > 0 else { return }

        // Briefly promote to .regular so the countdown panels can become key
        // (required for Escape to work and for the panel to be interactive).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // NSApp.activate is processed on the next main-queue turn, but
        // withCheckedContinuation's body runs synchronously. Drain one dispatch
        // cycle so AppKit processes the activation before we create the panels.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation

            let onSkip: @MainActor () -> Void = { Self.finish() }

            controllers = NSScreen.screens.map { screen -> NSWindowController in
                let panel = CountdownPanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .screenSaver
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.ignoresMouseEvents = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.hasShadow = false
                panel.onEscape = onSkip
                panel.contentView = NSHostingView(
                    rootView: CountdownView(seconds: seconds, onSkip: onSkip)
                )
                panel.setFrame(screen.frame, display: true)
                panel.orderFrontRegardless()
                return NSWindowController(window: panel)
            }
            controllers.first?.window?.makeKey()

            autoFinishTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                await MainActor.run { Self.finish() }
            }
        }

        autoFinishTask?.cancel()
        autoFinishTask = nil
        for c in controllers { c.window?.close() }
        controllers.removeAll()

        NSLog("ScreenLapse: countdown complete – demoting activation policy")
        // Demote back to menu-bar-only — recording is about to start.
        NSApp.setActivationPolicy(.accessory)
        NSLog("ScreenLapse: activation policy demoted – handing off to internalStart")
    }

    private static func finish() {
        let cont = finishContinuation
        finishContinuation = nil
        cont?.resume()
    }
}

private final class CountdownPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private struct CountdownView: View {
    let seconds: Int
    let onSkip: () -> Void
    @State private var remaining: Int

    init(seconds: Int, onSkip: @escaping () -> Void) {
        self.seconds = seconds
        self.onSkip = onSkip
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 32) {
                Text("\(remaining)")
                    .font(.system(size: 220, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 24)
                    .transition(.scale.combined(with: .opacity))
                    .id(remaining)

                Button(action: onSkip) {
                    HStack(spacing: 8) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Skip")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Esc")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .onAppear { tick() }
    }

    private func tick() {
        guard remaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation(.easeOut(duration: 0.35)) {
                remaining -= 1
            }
            if remaining > 0 { tick() }
        }
    }
}
