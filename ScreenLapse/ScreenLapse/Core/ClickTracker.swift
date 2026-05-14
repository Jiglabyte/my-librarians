import Foundation
import AppKit
import CoreGraphics

struct ClickEvent {
    let timestamp: TimeInterval
    let globalPoint: CGPoint
    let isRight: Bool
}

final class ClickTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let lock = NSLock()
    private var events: [ClickEvent] = []
    private let maxAgeSeconds: TimeInterval = 1.0

    func start() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
            let tracker = Unmanaged<ClickTracker>.fromOpaque(userInfo).takeUnretainedValue()
            tracker.record(event: event,
                           isRight: type == .rightMouseDown)
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: userInfo) else {
            return
        }
        self.eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        lock.lock()
        events.removeAll()
        lock.unlock()
    }

    private func record(event: CGEvent, isRight: Bool) {
        let click = ClickEvent(timestamp: CACurrentMediaTime(),
                               globalPoint: event.location,
                               isRight: isRight)
        lock.lock()
        events.append(click)
        let cutoff = click.timestamp - maxAgeSeconds
        events.removeAll(where: { $0.timestamp < cutoff })
        lock.unlock()
    }

    func recentEvents(now: TimeInterval = CACurrentMediaTime()) -> [ClickEvent] {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now - maxAgeSeconds
        return events.filter { $0.timestamp >= cutoff }
    }
}
