// ScreenLapsePro
// App/AppDelegate.swift
// Menu-bar application delegate; manages the status item, popover, and floating toolbar panel

import AppKit
import SwiftUI
import ScreenCaptureKit

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Status Item

    private var statusItem: NSStatusItem?
    private var popover:    NSPopover?

    // MARK: Floating Toolbar Panel

    private var toolbarPanel:  NSPanel?
    private var toolbarHostVC: NSViewController?

    // MARK: Recording state

    private weak var recordingManager: RecordingManager?
    private var statusTimer:       Timer?
    private var recordingStartDate: Date?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Prefs.shared
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        subscribeToRecordingNotifications()
    }

    // MARK: - Status Item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

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
        hostVC.view.translatesAutoresizingMaskIntoConstraints = false

        pop.contentViewController = hostVC
        pop.contentSize = NSSize(width: 320, height: 520)
        popover = pop
        return pop
    }

    // MARK: - Recording Notifications

    private func subscribeToRecordingNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRecordingDidStart(_:)),
            name: .recordingDidStart, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRecordingDidStop(_:)),
            name: .recordingDidStop, object: nil
        )
    }

    @objc private func handleRecordingDidStart(_ note: Notification) {
        if let mgr = note.object as? RecordingManager {
            recordingManager = mgr
        }
        recordingStartDate = Date()

        if Prefs.showStatusBarTimer {
            startStatusBarTimer()
        } else {
            // Just tint the icon red
            if let button = statusItem?.button {
                let img = NSImage(systemSymbolName: "record.circle.fill",
                                  accessibilityDescription: "Recording")
                img?.isTemplate = false
                button.image = img
                button.contentTintColor = .systemRed
            }
        }

        if Prefs.showFloatingPill {
            showToolbarPanel()
        }
    }

    @objc private func handleRecordingDidStop(_ note: Notification) {
        stopStatusBarTimer()
        hideToolbarPanel()
        recordingManager   = nil
        recordingStartDate = nil
    }

    // MARK: - Status Bar Live Timer

    private func startStatusBarTimer() {
        // Show first tick immediately
        updateStatusBarTimer()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusBarTimer() }
        }
        RunLoop.main.add(statusTimer!, forMode: .common)
    }

    private func stopStatusBarTimer() {
        statusTimer?.invalidate()
        statusTimer = nil

        // Restore icon
        if let button = statusItem?.button {
            button.title = ""
            button.image = NSImage(systemSymbolName: "record.circle",
                                   accessibilityDescription: "ScreenLapse Pro")
            button.image?.isTemplate = true
            button.contentTintColor  = nil
        }
    }

    private func updateStatusBarTimer() {
        guard let start = recordingStartDate,
              let button = statusItem?.button else { return }
        let elapsed = Int(Date().timeIntervalSince(start))
        let m = elapsed / 60
        let s = elapsed % 60
        button.image = nil
        button.title = String(format: "● %02d:%02d", m, s)
        button.contentTintColor = .systemRed
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
        toolbarPanel   = nil
        toolbarHostVC  = nil
    }

    private func makeToolbarPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 56),
            styleMask:   [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing:     .buffered,
            defer:       false
        )
        panel.level    = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let manager     = recordingManager ?? RecordingManager()
        let toolbarView = ToolbarView(manager: manager, onStop: { [weak self] in
            Task { await manager.stopRecording() }
            self?.hideToolbarPanel()
        })

        let hostVC = NSHostingController(rootView: toolbarView)
        hostVC.view.wantsLayer         = true
        hostVC.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostVC.sizingOptions           = []

        panel.contentViewController = hostVC
        toolbarHostVC = hostVC
        return panel
    }

    private func positionToolbarPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let w: CGFloat = 500
        let h: CGFloat = 56
        panel.setFrame(NSRect(x: frame.maxX - w - 20,
                              y: frame.maxY - h - 12,
                              width: w, height: h),
                       display: false)
    }
}
