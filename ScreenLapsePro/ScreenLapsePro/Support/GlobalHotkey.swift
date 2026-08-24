// ScreenLapsePro
// Support/GlobalHotkey.swift
// Carbon RegisterEventHotKey wrapper for a single global keyboard shortcut

import Foundation
import Carbon.HIToolbox
import AppKit

// MARK: - GlobalHotkey

/// Registers a single system-wide keyboard shortcut and invokes a callback when pressed.
/// The shortcut works regardless of which app is frontmost.
final class GlobalHotkey {

    // MARK: State

    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandler:   EventHandlerRef?
    private var hotKeyID: EventHotKeyID
    private var callback: (() -> Void)?

    // MARK: Init

    /// - Parameter id: Distinct identifier per hotkey. Two GlobalHotkey instances
    ///   in the same app must use different ids or their events collide.
    init(id: UInt32 = 1) {
        self.hotKeyID = EventHotKeyID(signature: OSType(0x534C5052), // "SLPR"
                                      id: id)
    }

    // MARK: Register

    /// Registers `⌃⇧R` (control + shift + R) by default. Safe to call more than once.
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_R),
                  modifiers: UInt32 = UInt32(controlKey | shiftKey),
                  onFire: @escaping () -> Void) {

        unregister()

        callback = onFire

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind:  UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            { (_, event, userData) -> OSStatus in
                                guard let userData else { return noErr }
                                let this = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()

                                var pressedID = EventHotKeyID()
                                let status = GetEventParameter(event,
                                                               EventParamName(kEventParamDirectObject),
                                                               EventParamType(typeEventHotKeyID),
                                                               nil,
                                                               MemoryLayout<EventHotKeyID>.size,
                                                               nil,
                                                               &pressedID)
                                guard status == noErr else { return status }
                                if pressedID.id == this.hotKeyID.id {
                                    DispatchQueue.main.async { this.callback?() }
                                }
                                return noErr
                            },
                            1,
                            &eventType,
                            selfPtr,
                            &eventHandler)

        RegisterEventHotKey(keyCode,
                            modifiers,
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &eventHotKeyRef)
    }

    // MARK: Unregister

    func unregister() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
