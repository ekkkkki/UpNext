import AppKit
import Carbon.HIToolbox

/// A user-configurable global shortcut (Carbon key code + modifier mask + display string).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String
}

/// Persistence + change notification for the global hot key.
enum ShortcutStore {
    static let key = "globalHotKey"
    static let changed = Notification.Name("UpNextShortcutChanged")

    static let defaultShortcut = Shortcut(
        keyCode: UInt32(kVK_ANSI_A),
        carbonModifiers: UInt32(cmdKey | shiftKey),
        display: "⇧⌘A"
    )

    static var current: Shortcut {
        get {
            if let data = UserDefaults.standard.data(forKey: key),
               let s = try? JSONDecoder().decode(Shortcut.self, from: data) { return s }
            return defaultShortcut
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }
}

// MARK: - Conversion helpers

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    return m
}

func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var s = ""
    if flags.contains(.control) { s += "⌃" }
    if flags.contains(.option) { s += "⌥" }
    if flags.contains(.shift) { s += "⇧" }
    if flags.contains(.command) { s += "⌘" }
    return s
}

/// Readable label for keys whose `charactersIgnoringModifiers` is empty or non-printing.
func keyLabel(keyCode: UInt16, characters: String?) -> String {
    let specials: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_ForwardDelete: "⌦",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
    ]
    if let s = specials[Int(keyCode)] { return s }
    if let c = characters, !c.isEmpty, c != " " { return c.uppercased() }
    return "Key\(keyCode)"
}
