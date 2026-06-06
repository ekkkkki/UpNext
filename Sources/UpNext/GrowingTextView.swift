import SwiftUI
import AppKit

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
        context.coordinator.lastSyncedText = text

        let scroll = GrowingScrollView()
        scroll.minHeight = minHeight
        scroll.maxHeight = maxHeight
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
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
        scroll.minHeight = minHeight
        scroll.maxHeight = maxHeight

        // Push *external / programmatic* text changes only — e.g. cleared after a submit, or
        // restored by undo. Never echo the user's own keystrokes back into the view (that
        // round-trip caused churn), and never touch the view mid-IME-composition: re-setting
        // the string or selection cancels the composition, so half-typed 中文/日本語 vanishes
        // until the next space/return.
        if !tv.hasMarkedText(), text != context.coordinator.lastSyncedText, tv.string != text {
            tv.string = text
            context.coordinator.lastSyncedText = text
        }

        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                guard let win = tv.window, !tv.hasMarkedText() else { return }
                win.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        applyHighlights(to: tv)
    }

    /// Report the content-driven height so SwiftUI lays the field out at the right size.
    /// Pure measurement: it must NOT invalidate intrinsic size (that loops — see the type doc).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GrowingScrollView, context: Context) -> CGSize? {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 480, height: minHeight)).width
        guard let tv = context.coordinator.textView else {
            return CGSize(width: width, height: minHeight)
        }
        // Lay the text out at the width SwiftUI is proposing so wrapping is correct.
        if abs(tv.frame.width - width) > 0.5 { tv.frame.size.width = width }
        let used = nsView.usedContentHeight()
        let needsScroller = used > maxHeight + 1
        if nsView.hasVerticalScroller != needsScroller { nsView.hasVerticalScroller = needsScroller }
        return CGSize(width: width, height: min(max(used, minHeight), maxHeight))
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

        init(_ parent: GrowingTextView) { self.parent = parent }

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

    /// Laid-out content height (unclamped). Pure: lays text out and measures, nothing else.
    func usedContentHeight() -> CGFloat {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return minHeight }
        lm.ensureLayout(for: tc)
        return lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
    }

    /// Content height clamped to [minHeight, maxHeight] — what the field should render at.
    func idealHeight() -> CGFloat {
        min(max(usedContentHeight(), minHeight), maxHeight)
    }
}
