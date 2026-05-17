// ScreenLapsePro
// App/AppDelegate.swift
// Menu-bar application delegate; manages the status item, popover, and floating toolbar panel

import AppKit
import SwiftUI
import ScreenCaptureKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Status Item

    private var statusItem:         NSStatusItem?
    private var popover:            NSPopover?

    // MARK: Floating Toolbar Panel

    private var toolbarPanel:       NSPanel?
    private var toolbarHostVC:      NSViewController?

    // MARK: Recording state (mirrored for toolbar)

    /// The manager lives inside PopoverView as a @StateObject, but we also need
    /// a reference here for the toolbar panel. We pass it via a notification's
    /// userInfo or by storing a weak ref when recording starts.
    private weak var recordingManager: RecordingManager?
    private var currentMode: RecordingMode = .normal(fps: 30)

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register defaults before any view reads them.
        _ = Prefs.shared

        // Keep app hidden from the Dock (backup in case Info.plist key is missing).
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()
        subscribeToRecordingNotifications()
    }

    // MARK: - Status Item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            let img = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "ScreenLapse Pro")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        let pop = makePopoverIfNeeded()
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    private func makePopoverIfNeeded() -> NSPopover {
        if let existing = popover { return existing }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates  = true

        let rootView = PopoverView()
        let hostVC   = NSHostingController(rootView: rootView)
        // Let the view determine its own size
        hostVC.view.translatesAutoresizingMaskIntoConstraints = false

        pop.contentViewController = hostVC
        pop.contentSize = NSSize(width: 320, height: 480)
        popover = pop
        return pop
    }

    // MARK: - Recording Notifications

    private func subscribeToRecordingNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingDidStart(_:)),
            name: .recordingDidStart,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingDidStop(_:)),
            name: .recordingDidStop,
            object: nil
        )
    }

    @objc private func handleRecordingDidStart(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Tint status icon red to indicate active recording.
            if let button = self.statusItem?.button {
                let img = NSImage(systemSymbolName: "record.circle.fill",
                                  accessibilityDescription: "Recording")
                img?.isTemplate = false
                button.image = img
                button.contentTintColor = .systemRed
            }

            // Retrieve manager & mode from notification if available
            if let mgr = note.object as? RecordingManager {
                self.recordingManager = mgr
            }

            self.showToolbarPanel()
        }
    }

    @objc private func handleRecordingDidStop(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Restore status icon
            if let button = self.statusItem?.button {
                let img = NSImage(systemSymbolName: "record.circle",
                                  accessibilityDescription: "ScreenLapse Pro")
                img?.isTemplate = true
                button.image = img
                button.contentTintColor = nil
            }

            self.hideToolbarPanel()
            self.recordingManager = nil
        }
    }

    // MARK: - Floating Toolbar Panel

    private func showToolbarPanel() {
        let panel = makeToolbarPanel()
        positionToolbarPanel(panel)
        panel.orderFrontRegardless()
        toolbarPanel = panel
    }

    private func hideToolbarPanel() {
        toolbarPanel?.orderOut(nil)
        toolbarPanel = nil
        toolbarHostVC = nil
    }

    private func makeToolbarPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect:   NSRect(x: 0, y: 0, width: 500, height: 56),
            styleMask:     [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing:       .buffered,
            defer:         false
        )
        panel.level                    = .floating
        panel.isOpaque                 = false
        panel.backgroundColor          = .clear
        panel.hasShadow                = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior       = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Use a placeholder manager if the real one isn't available yet.
        let manager = recordingManager ?? RecordingManager()
        let mode    = currentMode

        let toolbarView = ToolbarView(manager: manager, mode: mode) { [weak self] in
            Task { await manager.stopRecording() }
            self?.hideToolbarPanel()
        }

        let hostVC = NSHostingController(rootView: toolbarView)
        hostVC.view.wantsLayer       = true
        hostVC.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostVC.sizingOptions         = []

        panel.contentViewController = hostVC
        toolbarHostVC = hostVC

        return panel
    }

    private func positionToolbarPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame  = screen.visibleFrame
        // Place in the top-right of the main display, with a small inset.
        let panelWidth:  CGFloat = 480
        let panelHeight: CGFloat = 56
        let x = screenFrame.maxX - panelWidth - 20
        let y = screenFrame.maxY - panelHeight - 12
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                       display: false)
    }
}
