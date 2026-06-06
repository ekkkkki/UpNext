import SwiftUI
import AppKit
import NextorCore

/// A multi-line text field that grows with its content (then scrolls), wrapping long
/// lines instead of clipping. Return submits; ⇧/⌥Return inserts a newline; Esc cancels.
/// Backed by NSTextView so paste, undo, and IME all work natively.
///
/// Sizing contract (important): `sizeThatFits` *measures and returns* the height — it must
/// never call `invalidateIntrinsicContentSize()` (or anything that does). Doing so makes
/// SwiftUI re-measure, which calls `sizeThatFits` again → an unbounded layout loop that
/// froze the app on large / multi-line input. The scroll view therefore exposes pure
/// measurement helpers with no side effects.
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: NSFont = .systemFont(ofSize: 20)
    var minHeight: CGFloat = 28
    var maxHeight: CGFloat = 168
    /// Bump to request first-responder focus.
    var focusTick: Int
    /// Ranges (into the current text) to tint, for live token highlighting.
    var highlights: [(range: NSRange, color: NSColor)] = []
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onSubmitAll: () -> Void = {}
    /// Called when a long multi-line blob is pasted, instead of inserting it — lets the model
    /// collapse the field to the event name and route the body to notes.
    var onDocumentPaste: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> GrowingScrollView {
        let textView = QATextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.placeholderString = placeholder
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.onDocumentPaste = onDocumentPaste
        context.coordinator.lastSyncedText = text

        let scroll = GrowingScrollView()
        scroll.minHeight = minHeight
        scroll.maxHeight = maxHeight
        scroll.drawsBackground = false
        // Overlay scroller: invisible until the content actually overflows maxHeight, so we never
        // need to toggle it (toggling mutates layout — see sizeThatFits).
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ scroll: GrowingScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = context.coordinator.textView else { return }
        tv.placeholderString = placeholder
        tv.onDocumentPaste = onDocumentPaste
        scroll.minHeight = minHeight
        scroll.maxHeight = maxHeight

        // Push *external / programmatic* text changes only — e.g. cleared after a submit, or
        // restored by undo. syncExternalText ignores echoes of the user's own keystrokes and
        // refuses to touch the view mid-IME-composition (re-setting the string or selection
        // cancels the composition, so half-typed 中文/日本語 vanishes until the next commit).
        context.coordinator.syncExternalText(text)

        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                guard let win = tv.window, !tv.hasMarkedText() else { return }
                win.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        // Re-tinting sets attributes across the whole string and nudges TextKit, so skip it when
        // neither the text nor the highlight ranges changed since the last render.
        var hasher = Hasher()
        hasher.combine(text)
        for hl in highlights { hasher.combine(hl.range.location); hasher.combine(hl.range.length) }
        let sig = hasher.finalize()
        if context.coordinator.lastHighlightSig != sig {
            context.coordinator.lastHighlightSig = sig
            applyHighlights(to: tv)
        }
    }

    /// Report the content-driven height so SwiftUI lays the field out at the right size.
    ///
    /// This MUST be a pure measurement — it must not mutate the view hierarchy (frame, scroller,
    /// text storage, …). Mutating anything here re-triggers AppKit/SwiftUI layout, and in a
    /// *presented* window that becomes an every-display-cycle feedback loop that pegs the main
    /// thread at 100% (the paste freeze). The text view's width is already managed by the scroll
    /// view's autoresizing, so we only need to compute and return the height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GrowingScrollView, context: Context) -> CGSize? {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 480, height: minHeight)).width
        let h = context.coordinator.measuredHeight(text: text, width: width, font: font,
                                                    minHeight: minHeight, maxHeight: maxHeight)
        return CGSize(width: width, height: h)
    }

    /// Tint recognized token ranges. Skips while an IME composition is active (so we don't
    /// disturb marked text) and for long pastes (invisible work that hurts responsiveness).
    private func applyHighlights(to tv: NSTextView) {
        guard !tv.hasMarkedText(), let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font, value: font, range: full)
        if storage.length <= 400 {
            for hl in highlights where hl.range.location != NSNotFound && NSMaxRange(hl.range) <= storage.length {
                storage.addAttribute(.foregroundColor, value: hl.color, range: hl.range)
            }
        }
        storage.endEditing()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var textView: QATextView?
        weak var scrollView: GrowingScrollView?
        var lastFocusTick = Int.min
        /// The text we last wrote into / read out of the view, to distinguish the user's own
        /// edits (echo — ignore) from external changes that must be pushed in.
        var lastSyncedText = "\u{1}"
        /// Offscreen text view used purely for height measurement, so sizeThatFits never has to
        /// touch (and thus re-trigger layout on) the live field. TextKit caches its layout, so
        /// repeated measurements — including SwiftUI's probing — are cheap.
        private let measurer: NSTextView = {
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
            tv.textContainerInset = NSSize(width: 0, height: 3)
            tv.textContainer?.lineFragmentPadding = 0
            tv.textContainer?.widthTracksTextView = false
            return tv
        }()
        private var measureCache: (text: String, width: CGFloat, height: CGFloat)?
        /// Signature of the last-applied (text + highlight ranges), to skip redundant re-tinting.
        var lastHighlightSig = 0

        init(_ parent: GrowingTextView) { self.parent = parent }

        /// Clamped content height for `text` at `width`. Pure w.r.t. the live view (it measures on
        /// an offscreen text view) and memoized, so SwiftUI's repeated size probes are O(1).
        func measuredHeight(text: String, width: CGFloat, font: NSFont,
                            minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
            let w = max(width, 1)
            if let c = measureCache, c.text == text, abs(c.width - w) < 0.5 { return c.height }
            measurer.font = font
            if measurer.string != text { measurer.string = text }
            measurer.textContainer?.size = NSSize(width: w, height: .greatestFiniteMagnitude)
            var h = minHeight
            if let lm = measurer.layoutManager, let tc = measurer.textContainer {
                lm.ensureLayout(for: tc)
                h = min(max(lm.usedRect(for: tc).height + measurer.textContainerInset.height * 2, minHeight), maxHeight)
            }
            measureCache = (text, w, h)
            return h
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            // While composing (marked text present), don't propagate to SwiftUI — the
            // partial 拼音/かな isn't real input yet, and the re-render round-trip is what
            // used to disturb the composition. The committed text arrives here on commit.
            guard !tv.hasMarkedText() else { return }
            if tv.string != lastSyncedText {
                lastSyncedText = tv.string
                parent.text = tv.string
            }
        }

        /// Push an external/programmatic text change (clear-after-submit, undo-restore) into the
        /// view. Returns true iff it actually wrote. Never echoes the user's own edits, and
        /// never disturbs an active IME composition. Factored out so it's unit-testable.
        @discardableResult
        func syncExternalText(_ newText: String) -> Bool {
            guard let tv = textView else { return false }
            guard !tv.hasMarkedText() else { return false }       // composing → never touch
            guard newText != lastSyncedText, tv.string != newText else { return false } // echo / no-op
            tv.string = newText
            lastSyncedText = newText
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let mods = NSApp.currentEvent?.modifierFlags ?? []
                if mods.contains(.option) {
                    parent.onSubmitAll()            // ⌥↩ → add each line as its own item
                } else if mods.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(self) // ⇧↩ → newline
                } else {
                    parent.onSubmit()               // ↩ → add as one item
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

/// NSTextView that paints a placeholder when empty.
final class QATextView: NSTextView {
    var placeholderString: String = ""
    var onDocumentPaste: ((String) -> Void)?

    /// Intercept a paste of a long multi-line blob: hand it to the model (which collapses the
    /// field to the event name and routes the body to notes) instead of inserting the whole
    /// thing — that's what kept the field from having to lay out hundreds of characters.
    override func paste(_ sender: Any?) {
        if let handler = onDocumentPaste,
           let s = NSPasteboard.general.string(forType: .string),
           InputParser.looksLikeDocument(s) {
            handler(s)
            return
        }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: 20)
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        placeholderString.draw(at: origin, withAttributes: attrs)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        needsDisplay = true
        return result
    }
}

/// Scroll view for the growing field. Exposes pure measurement helpers (no intrinsic-size
/// override, no recompute-in-layout) so the SwiftUI sizing path can't form a feedback loop.
final class GrowingScrollView: NSScrollView {
    var minHeight: CGFloat = 28
    var maxHeight: CGFloat = 168

    /// Clamped content height for the current document — used by the UI self-test.
    func idealHeight() -> CGFloat {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return minHeight }
        lm.ensureLayout(for: tc)
        return min(max(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2, minHeight), maxHeight)
    }
}
