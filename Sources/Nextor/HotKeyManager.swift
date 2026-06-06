import Foundation
import Carbon.HIToolbox

/// Registers a single system-wide hot key via Carbon's RegisterEventHotKey.
/// This works without Accessibility permissions (unlike a CGEventTap) and is the
/// long-standing supported API for app-global shortcuts.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x514B4144 // 'QKAD'

    /// `keyCode` is a virtual key (e.g. kVK_ANSI_A); `modifiers` uses Carbon masks
    /// (cmdKey, shiftKey, optionKey, controlKey).
    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger?() }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef); self.hotKeyRef = nil }
        if let handlerRef { RemoveEventHandler(handlerRef); self.handlerRef = nil }
    }

    deinit { unregister() }

    // Convenience: ⇧⌘A
    static var defaultKeyCode: UInt32 { UInt32(kVK_ANSI_A) }
    static var defaultModifiers: UInt32 { UInt32(cmdKey | shiftKey) }
}
