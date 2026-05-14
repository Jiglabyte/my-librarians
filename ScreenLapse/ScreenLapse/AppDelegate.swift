import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let recordingManager = RecordingManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingToolbar: FloatingToolbarController?
    private var hotkey: Hotkey?
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var pulseOn = false
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            .sink { [weak self] _ in self?.popover.performClose(nil) }
            .store(in: &cancellables)

        recordingManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                if recording { self?.popover.performClose(nil) }
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

    func applicationWillTerminate(_ notification: Notification) {
        guard recordingManager.isRecording else { return }
        Task { await recordingManager.stopRecording() }
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

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettings),
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
            let host = NSHostingController(
                rootView: SettingsView().environmentObject(recordingManager)
            )
            let win = NSWindow(contentViewController: host)
            win.title = "ScreenLapse Settings"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.setFrameAutosaveName("ScreenLapseSettings")
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleRecording() {
        Task { @MainActor in
            if recordingManager.isRecording {
                await recordingManager.stopRecording()
            } else {
                do {
                    try await recordingManager.startRecording()
                } catch {
                    NSLog("ScreenLapse: startRecording failed: \(error)")
                }
            }
        }
    }

    private func updateStatusItemIcon(recording: Bool) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseOn = false
        guard let button = statusItem.button else { return }
        if recording {
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
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
