import AppKit
import Carbon.HIToolbox

final class Hotkey {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var localMonitor: Any?
    private let handler: () -> Void

    // keyCode: Carbon/NSEvent physical key code (e.g. kVK_ANSI_R = 0x0F)
    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.handler = handler
        registerCarbon(keyCode: keyCode, modifiers: modifiers)
        installLocalMonitor(keyCode: UInt16(keyCode), modifiers: modifiers)
    }

    deinit {
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    // Carbon global hotkey — fires even when no app window is key.
    private func registerCarbon(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        var carbonMods: UInt32 = 0
        if modifiers.contains(.command)  { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option)   { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control)  { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift)    { carbonMods |= UInt32(shiftKey) }

        var hotkeyID = EventHotKeyID(signature: OSType(0x534C_5053), id: 1)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, carbonMods, hotkeyID,
                                  GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return }
        self.hotkeyRef = ref

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        var hRef: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let p = userData else { return OSStatus(eventNotHandledErr) }
                let h = Unmanaged<Hotkey>.fromOpaque(p).takeUnretainedValue()
                DispatchQueue.main.async { h.handler() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hRef
        )
        self.handlerRef = hRef
    }

    // Local NSEvent monitor — fires when any of our windows (popover, settings) is key.
    private func installLocalMonitor(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let targetCode = keyCode
        let targetMods = modifiers
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == targetCode, flags == targetMods {
                DispatchQueue.main.async { self?.handler() }
                return nil  // consume event
            }
            return event
        }
    }
}
