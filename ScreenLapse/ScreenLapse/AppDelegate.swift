import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let recordingManager = RecordingManager()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var floatingToolbar: FloatingToolbarController?
    private var hotkey: Hotkey?
    private var cancellables = Set<AnyCancellable>()
    private var pulseTimer: Timer?
    private var pulseOn = false

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
        popover.contentSize = NSSize(width: 340, height: 460)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover()
                .environmentObject(recordingManager)
        )

        recordingManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.updateStatusItemIcon(recording: recording)
                self?.updateFloatingToolbar(recording: recording)
            }
            .store(in: &cancellables)

        hotkey = Hotkey(keyCode: 0x0F, modifiers: [.control, .shift]) { [weak self] in
            self?.toggleRecording()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recordingManager.isRecording {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await recordingManager.stopRecording()
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 5)
        }
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
        menu.addItem(NSMenuItem(title: recordingManager.isRecording
                                ? "Stop Recording"
                                : "Start Recording",
                                action: #selector(menuToggleRecording),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Recordings Folder",
                                action: #selector(openRecordingsFolder),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…",
                                action: #selector(openSettings),
                                keyEquivalent: ","))
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

    @objc private func openSettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
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
