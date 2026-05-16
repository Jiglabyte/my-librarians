import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    let recordingManager = RecordingManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingToolbar: FloatingToolbarController?
    private var hotkey: Hotkey?
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var pulseOn = false
    private var settingsWindow: NSWindow?
    private var recentsWindow: NSWindow?
    private var pendingTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle",
                                   accessibilityDescription: "ScreenLapse")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 500)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover()
                .environmentObject(recordingManager)
        )

        // Close popover the moment recording preparation begins (before countdown),
        // so the popover never appears in the first frames of a capture.
        recordingManager.$isPreparing
            .receive(on: DispatchQueue.main)
            .filter { $0 }
            .sink { [weak self] _ in self?.hidePopover() }
            .store(in: &cancellables)

        recordingManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.hidePopover() }
                self?.updateStatusItemIcon(recording: recording)
                self?.updateFloatingToolbar(recording: recording)
            }
            .store(in: &cancellables)

        // Reveal finished recording in Finder so the user can find it immediately.
        recordingManager.$lastRecordingURL
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .store(in: &cancellables)

        hotkey = Hotkey(keyCode: 0x0F, modifiers: [.control, .shift]) { [weak self] in
            self?.toggleRecording()
        }
    }

    // Never quit just because windows closed — we're a menu-bar-only app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // Wait for a clean stop before letting macOS kill us — otherwise the MP4 is corrupt.
    // Also guard isPreparing: the countdown panels close before isRecording flips to true,
    // and without this guard, the app terminates in that gap.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recordingManager.isRecording || recordingManager.isPreparing,
              !pendingTermination else { return .terminateNow }
        pendingTermination = true
        Task { @MainActor in
            await recordingManager.stopRecording()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // Force-close the popover. NSPopover.close() is safe to call when not shown.
    func hidePopover() {
        popover.close()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let recItem = NSMenuItem(
            title: recordingManager.isRecording ? "Stop Recording" : "Start Recording",
            action: #selector(menuToggleRecording),
            keyEquivalent: "r"
        )
        recItem.keyEquivalentModifierMask = [.control, .shift]
        menu.addItem(recItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Open Recordings Folder",
                                action: #selector(openRecordingsFolder),
                                keyEquivalent: ""))

        menu.addItem(NSMenuItem(title: "Recent Recordings…",
                                action: #selector(openRecents(_:)),
                                keyEquivalent: ""))

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings(_:)),
                                      keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ScreenLapse",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        menu.items.last?.target = NSApp
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuToggleRecording() { toggleRecording() }

    @objc private func openRecordingsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([recordingManager.outputFolderURL])
    }

    @objc func openSettings(_ sender: Any? = nil) {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "ScreenLapse Settings",
                                        view: SettingsView(),
                                        size: NSSize(width: 520, height: 460),
                                        autosaveName: "ScreenLapseSettings")
        }
        bringWindowToFront(settingsWindow)
    }

    @objc func openRecents(_ sender: Any? = nil) {
        if recentsWindow == nil {
            recentsWindow = makeWindow(title: "Recent Recordings",
                                       view: RecentRecordingsView(),
                                       size: NSSize(width: 520, height: 480),
                                       autosaveName: "ScreenLapseRecents")
        }
        bringWindowToFront(recentsWindow)
    }

    private func makeWindow<V: View>(title: String,
                                     view: V,
                                     size: NSSize,
                                     autosaveName: String) -> NSWindow {
        let host = NSHostingController(rootView: view.environmentObject(recordingManager))
        let win = NSWindow(contentViewController: host)
        win.title = title
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.setContentSize(size)
        win.setFrameAutosaveName(autosaveName)
        win.center()
        win.delegate = self
        return win
    }

    // Menu-bar (.accessory) apps can't activate a window above other apps with
    // NSApp.activate alone. Briefly promote to .regular so the window reaches
    // the front; demote back when no managed windows are visible.
    private func bringWindowToFront(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // Wait a runloop tick so isVisible reflects the close.
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.demoteIfNoVisibleWindows()
        }
    }

    private func demoteIfNoVisibleWindows() {
        let anyVisible = (settingsWindow?.isVisible ?? false)
                      || (recentsWindow?.isVisible ?? false)
        if !anyVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func toggleRecording() {
        Task { @MainActor in
            if recordingManager.isRecording {
                await recordingManager.stopRecording()
            } else {
                hidePopover()
                do {
                    try await recordingManager.startRecording()
                } catch {
                    NSLog("ScreenLapse: startRecording failed: \(error)")
                    showError("Recording failed to start", detail: error.localizedDescription)
                }
            }
        }
    }

    func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func updateStatusItemIcon(recording: Bool) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseOn = false
        guard let button = statusItem.button else { return }
        if recording {
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pulseOn.toggle()
                    let name = self.pulseOn ? "record.circle.fill" : "record.circle"
                    let img = NSImage(systemSymbolName: name, accessibilityDescription: "Recording")
                    img?.isTemplate = false
                    if let img {
                        let tinted = NSImage(size: img.size, flipped: false) { rect in
                            NSColor.systemRed.set()
                            rect.fill()
                            img.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
                            return true
                        }
                        button.image = tinted
                    }
                }
            }
            pulseTimer?.fire()
        } else {
            let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenLapse")
            img?.isTemplate = true
            button.image = img
        }
    }

    private func updateFloatingToolbar(recording: Bool) {
        if recording {
            if floatingToolbar == nil {
                floatingToolbar = FloatingToolbarController(manager: recordingManager) { [weak self] in
                    Task { await self?.recordingManager.stopRecording() }
                }
            }
            floatingToolbar?.show()
        } else {
            floatingToolbar?.close()
            floatingToolbar = nil
        }
    }
}
