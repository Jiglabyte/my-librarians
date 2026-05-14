import AppKit
import CoreGraphics

enum RegionSelectorOverlay {
    struct Result {
        let rect: CGRect
        let displayID: CGDirectDisplayID
    }

    private static var controllers: [RegionWindowController] = []

    static func pickRegion(completion: @escaping (Result?) -> Void) {
        controllers.removeAll()
        var didComplete = false

        let onFinish: (Result?) -> Void = { result in
            guard !didComplete else { return }
            didComplete = true
            controllers.forEach { $0.window?.close() }
            controllers.removeAll()
            DispatchQueue.main.async { completion(result) }
        }

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let controller = RegionWindowController(screen: screen,
                                                    displayID: displayID,
                                                    onFinish: onFinish)
            controllers.append(controller)
            controller.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

private final class RegionWindowController: NSWindowController {
    private let displayID: CGDirectDisplayID
    private let onFinish: (RegionSelectorOverlay.Result?) -> Void

    init(screen: NSScreen,
         displayID: CGDirectDisplayID,
         onFinish: @escaping (RegionSelectorOverlay.Result?) -> Void) {
        self.displayID = displayID
        self.onFinish = onFinish

        let panel = RegionWindow(contentRect: screen.frame,
                                 styleMask: .borderless,
                                 backing: .buffered,
                                 defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = RegionSelectorView(frame: screen.frame, screen: screen)
        view.onSelected = { [displayID, weak self] rect in
            let result = RegionSelectorOverlay.Result(rect: rect, displayID: displayID)
            self?.onFinish(result)
        }
        view.onCancel = { [weak self] in self?.onFinish(nil) }
        panel.contentView = view
        panel.makeKey()

        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class RegionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // escape
            (contentView as? RegionSelectorView)?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class RegionSelectorView: NSView {
    var onSelected: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private weak var screen: NSScreen?

    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero

    init(frame: NSRect, screen: NSScreen) {
        self.screen = screen
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = event.locationInWindow
        currentRect = CGRect(x: min(start.x, p.x),
                             y: min(start.y, p.y),
                             width: abs(p.x - start.x),
                             height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let screen, currentRect.width > 10, currentRect.height > 10 else {
            cancel(); return
        }
        let frame = screen.frame
        let globalRect = CGRect(x: frame.minX + currentRect.minX,
                                y: frame.minY + currentRect.minY,
                                width: currentRect.width,
                                height: currentRect.height)
        onSelected?(globalRect)
    }

    func cancel() {
        onCancel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        if currentRect.width > 0, currentRect.height > 0 {
            NSColor.clear.setFill()
            let path = NSBezierPath(rect: currentRect)
            NSGraphicsContext.current?.compositingOperation = .clear
            path.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSColor.systemBlue.setStroke()
            let stroke = NSBezierPath(rect: currentRect)
            stroke.lineWidth = 2
            stroke.stroke()

            let sizeText = "\(Int(currentRect.width)) × \(Int(currentRect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
                .backgroundColor: NSColor.black.withAlphaComponent(0.7)
            ]
            (sizeText as NSString).draw(at: CGPoint(x: currentRect.midX - 40,
                                                    y: currentRect.minY - 24),
                                        withAttributes: attrs)
        }

        let hint = "Drag to select region · Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.6)
        ]
        (hint as NSString).draw(at: CGPoint(x: 20, y: bounds.height - 36),
                                withAttributes: attrs)
    }
}
