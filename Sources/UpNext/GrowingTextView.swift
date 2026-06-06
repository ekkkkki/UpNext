import SwiftUI
import AppKit

/// A multi-line text field that grows with its content (then scrolls), wrapping long
/// lines instead of clipping. Return submits; ⇧/⌥Return inserts a newline; Esc cancels.
/// Backed by NSTextView so paste, undo, and IME all work natively.
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
        if tv.string != text { tv.string = text; scroll.recompute() }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                guard let win = tv.window else { return }
                win.makeFirstResponder(tv)
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            }
        }
        applyHighlights(to: tv)
    }

    /// Report the content-driven height so SwiftUI doesn't stretch the field to fill
    /// the panel (which left a big empty gap).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GrowingScrollView, context: Context) -> CGSize? {
        let width = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 480, height: minHeight)).width
        if let tv = context.coordinator.textView, abs(tv.frame.width - width) > 0.5 {
            tv.frame.size.width = width
        }
        nsView.recompute()
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    /// Tint recognized token ranges. Skips while an IME composition is active so we
    /// don't disturb marked text.
    private func applyHighlights(to tv: NSTextView) {
        guard !tv.hasMarkedText(), let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font, value: font, range: full)
        // Skip per-token tinting for long pastes — it's invisible work on a big string and
        // keeps typing/pasting responsive.
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

        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            scrollView?.recompute()
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

/// Scroll view whose intrinsic height tracks the text content (clamped), so SwiftUI
/// lays it out at the right height and the panel grows downward instead of clipping.
final class GrowingScrollView: NSScrollView {
    var minHeight: CGFloat = 28
    var maxHeight: CGFloat = 168
    private var contentHeight: CGFloat = 28

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func layout() {
        // NB: do *not* call recompute() here. recompute() can invalidate the intrinsic
        // content size, which schedules another layout pass — recomputing on every layout
        // creates a feedback loop that hangs the UI on large / multi-line input. Height is
        // recomputed on text changes and whenever SwiftUI measures us (sizeThatFits).
        super.layout()
    }

    func recompute() {
        guard let tv = documentView as? NSTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        let clamped = min(max(used, minHeight), maxHeight)
        if abs(clamped - contentHeight) > 0.5 {
            contentHeight = clamped
            invalidateIntrinsicContentSize()
        }
        // Only toggle the scroller when it actually changes — flipping it every pass churns
        // the layout (it changes the text width, which feeds back into height).
        let needsScroller = used > maxHeight + 1
        if hasVerticalScroller != needsScroller { hasVerticalScroller = needsScroller }
    }
}
