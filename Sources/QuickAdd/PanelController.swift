import AppKit
import SwiftUI

/// Borderless panel that can still become key (so its text field accepts input)
/// even though the app runs as a menu-bar accessory.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// Returns true if ⌘Z was consumed as "undo last add" (only when the field is empty).
    var onCommandZ: (() -> Bool)?

    /// A menu-bar accessory app has no main menu, so the standard editing
    /// shortcuts (⌘C/⌘V/⌘X/⌘A/⌘Z) are never bound. Dispatch them to the focused
    /// field's responder chain ourselves so copy/paste work in the panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // "Undo last add" takes ⌘Z only when the field is empty; otherwise the text
        // field's own undo handles it (below).
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "z",
           onCommandZ?() == true {
            return true
        }
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }

        let selector: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "x": selector = #selector(NSText.cut(_:))
        case "c": selector = #selector(NSText.copy(_:))
        case "v": selector = #selector(NSText.paste(_:))
        case "a": selector = #selector(NSResponder.selectAll(_:))
        case "z": selector = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: selector = nil
        }
        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: self)
    }
}

/// Shows / hides the quick-add panel and restores focus to the previous app.
@MainActor
final class PanelController {
    private var panel: FloatingPanel?
    private let model: PanelModel
    private let eventKit: EventKitService
    private weak var previousApp: NSRunningApplication?

    init(model: PanelModel, eventKit: EventKitService) {
        self.model = model
        self.eventKit = eventKit
        model.onClose = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle(mode: PanelModel.Mode = .add) {
        if isVisible { hide() } else { show(mode: mode) }
    }

    func show(mode: PanelModel.Mode = .add) {
        eventKit.refreshAuthorization()
        if panel == nil { buildPanel() }
        guard let panel else { return }

        model.reset()
        model.mode = mode

        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }

        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Re-center once SwiftUI has laid out its intrinsic size.
        DispatchQueue.main.async { [weak self] in self?.position(panel) }
    }

    func hide() {
        panel?.orderOut(nil)
        if let prev = previousApp, prev.bundleIdentifier != Bundle.main.bundleIdentifier {
            prev.activate()
        }
    }

    private func buildPanel() {
        let root = RootPanelView(model: model, eventKit: eventKit)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        let p = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.contentViewController = hosting
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = true            // click outside / switch apps -> dismiss
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.animationBehavior = .utilityWindow
        p.onCommandZ = { [weak self] in
            guard let model = self?.model, model.mode == .add, model.input.isEmpty, model.canUndo else { return false }
            model.undoLast()
            return true
        }
        panel = p

        // Keep the panel's TOP edge fixed as its height changes (growing input),
        // so it expands downward instead of clipping at the top.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: p, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position(p) }
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.frame.size
        let vf = screen.visibleFrame
        let x = vf.midX - size.width / 2
        // Pin the top edge ~30% down from the top of the screen, Spotlight-style.
        let topY = vf.minY + vf.height * 0.78
        let y = topY - size.height
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}
