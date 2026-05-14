import AppKit
import Carbon.HIToolbox

final class Hotkey {

    private var hotkeyRef: EventHotKeyRef?
    private var handler: () -> Void

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, handler: @escaping () -> Void) {
        self.handler = handler
        register(keyCode: keyCode, modifiers: modifiers)
    }

    deinit {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
    }

    private func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        var carbonMods: UInt32 = 0
        if modifiers.contains(.command)  { carbonMods |= UInt32(cmdKey) }
        if modifiers.contains(.option)   { carbonMods |= UInt32(optionKey) }
        if modifiers.contains(.control)  { carbonMods |= UInt32(controlKey) }
        if modifiers.contains(.shift)    { carbonMods |= UInt32(shiftKey) }

        var hotkeyID = EventHotKeyID(signature: OSType(0x534C_5053), id: 1) // 'SLPS'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, carbonMods, hotkeyID,
                                          GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return }
        self.hotkeyRef = ref

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let userData else { return noErr }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.handler() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
}
