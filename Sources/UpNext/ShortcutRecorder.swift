import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A click-to-record control for the global shortcut. Click it, press a combo (with at
/// least one of ⌘/⌃/⌥), and it reports the new `Shortcut`. Esc cancels.
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut
    var onCapture: (Shortcut) -> Void

    func makeNSView(context: Context) -> RecorderControl {
        let v = RecorderControl()
        v.shortcut = shortcut
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: RecorderControl, context: Context) {
        nsView.onCapture = onCapture
        if !nsView.isRecording { nsView.shortcut = shortcut }
    }
}

final class RecorderControl: NSView {
    var shortcut: Shortcut = ShortcutStore.defaultShortcut { didSet { needsDisplay = true } }
    var onCapture: ((Shortcut) -> Void)?
    private(set) var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 140, height: 26) }

    override func mouseDown(with event: NSEvent) {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) } else { window?.makeFirstResponder(nil) }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // While recording, intercept combos that would otherwise be menu key-equivalents.
        if isRecording { return handle(event) }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording, handle(event) { return }
        super.keyDown(with: event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Escape {           // cancel
            isRecording = false
            window?.makeFirstResponder(nil)
            return true
        }
        let flags = event.modifierFlags
        let mods = carbonModifiers(from: flags)
        // Require at least one of ⌘ / ⌃ / ⌥ so the global hot key can't be a bare key.
        guard mods & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            NSSound.beep()
            return true
        }
        let label = keyLabel(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        let captured = Shortcut(keyCode: UInt32(event.keyCode),
                                carbonModifiers: mods,
                                display: modifierSymbols(flags) + label)
        shortcut = captured
        isRecording = false
        window?.makeFirstResponder(nil)
        onCapture?(captured)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Press keys… (⎋ cancels)" : shortcut.display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: isRecording ? 11 : 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }
}
