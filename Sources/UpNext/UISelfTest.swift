import AppKit
import SwiftUI

/// Headless UI/layout checks — the kind that would have caught the multi-line
/// clipping bug. Run with `UpNext --selftest-ui`. Exit 0 pass / 1 fail.
@MainActor
enum UISelfTest {
    static func run() -> Int {
        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            print(cond ? "  ✓ \(msg)" : "  ✗ FAIL: \(msg)")
            if !cond { failures += 1 }
        }
        print("▸ UI layout self-test")

        // 1) The growing text view must grow with content and clamp at maxHeight.
        let tv = QATextView(frame: NSRect(x: 0, y: 0, width: 540, height: 30))
        tv.font = .systemFont(ofSize: 20)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainerInset = NSSize(width: 0, height: 3)
        let scroll = GrowingScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 30))
        scroll.minHeight = 28
        scroll.maxHeight = 168
        scroll.documentView = tv

        tv.string = "single line"
        let h1 = scroll.idealHeight()

        tv.string = "line one\nline two\nline three"
        let h3 = scroll.idealHeight()

        tv.string = String(repeating: "とても長い住所のテキストです ", count: 14)
        let hWrap = scroll.idealHeight()

        print("    field heights — 1-line=\(Int(h1)) 3-line=\(Int(h3)) wrapped=\(Int(hWrap))")
        check(h1 >= 22 && h1 <= 42, "single line is ~one row")
        check(h3 > h1 + 30, "three lines grow taller than one")
        check(hWrap > h1 + 20, "a long line wraps and grows (no clipping)")
        check(hWrap <= 168 + 1, "growth is clamped to maxHeight, then scrolls")

        // 2) The whole panel must grow with multi-line input.
        let ek = EventKitService()
        let model = PanelModel(eventKit: ek)
        func panelHeight(_ input: String) -> CGFloat {
            model.reset()
            model.input = input
            let hc = NSHostingController(rootView: RootPanelView(model: model, eventKit: ek))
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 1200),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentViewController = hc
            win.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            let height = hc.view.fittingSize.height
            win.close()
            return height
        }
        let single = panelHeight("买牛奶")
        let multi = panelHeight("6/8 15:30 東京都中央区晴海1-8-10\nトリトンスクエア オフィスタワーX棟 7階\nもう一行追加")
        print("    panel heights — single=\(Int(single)) multi=\(Int(multi))")
        check(single > 0, "panel measures a height")
        check(multi > single, "panel grows for multi-line input (was clipped before)")

        // 3) A big multi-line paste must lay out promptly and stay clamped. Regression for
        //    the freeze: a layout feedback loop would blow far past this budget (or hang).
        let blobInput = """
        起業家＆事業会社・CVC集合！ 6月ピッチ＆交流会 by JAFCO
        2026/06/18(木) 12:00 - 13:00
        イベント概要
        スタートアップ起業家とCVCが集う交流会を開催します。
        本イベントは、大企業とスタートアップの情報交換やシナジー創出を目的とした場です。
        当日は参加起業家の中から希望者によるピッチセッションも実施予定です。
        ネットワーキングを通じて、新たな連携のきっかけを見つけてください。
        ■ 開催場所
        ・東京都港区虎ノ門1-23-1 虎ノ門ヒルズ森タワー24階
        　ジャフコ グループ株式会社 本社オフィス内 Jラウンジ
        さらに本文を足して十分な長さにします。
        もう一行。
        """
        let t0 = Date()
        let blobH = panelHeight(blobInput)
        let blobMs = Date().timeIntervalSince(t0) * 1000
        print("    big-paste render: \(Int(blobMs)) ms, height=\(Int(blobH))")
        check(blobMs < 1500, "big multi-line paste lays out promptly (no freeze)")
        check(blobH > single && blobH < 1200, "big paste height is bounded (field clamps + scrolls)")

        // 4) IME composition safety — regression for the vanishing 中文/日本語 bug. Drive a real
        //    NSTextView through an actual composition and check the field is never disturbed and
        //    the partial text isn't propagated until it commits.
        final class Box { var s = "现在" }
        let box = Box()
        let gtv = GrowingTextView(text: Binding(get: { box.s }, set: { box.s = $0 }),
                                  placeholder: "", focusTick: 0, onSubmit: {}, onCancel: {})
        let coord = gtv.makeCoordinator()
        let imeTV = QATextView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        coord.textView = imeTV
        coord.parent = gtv
        imeTV.string = "现在"
        coord.lastSyncedText = "现在"
        // Begin composing pinyin after "现在".
        imeTV.setSelectedRange(NSRange(location: 2, length: 0))
        imeTV.setMarkedText("zenme", selectedRange: NSRange(location: 5, length: 0),
                            replacementRange: NSRange(location: NSNotFound, length: 0))
        check(imeTV.hasMarkedText(), "composition is active (test setup)")
        // A re-render carrying a different binding value must not touch the field mid-composition.
        box.s = "现在你好"
        let wrote = coord.syncExternalText("现在你好")
        check(!wrote, "binding sync refused during composition")
        check(imeTV.hasMarkedText() && (imeTV.string as NSString).contains("zenme"), "marked text survives")
        // textDidChange while composing must not push the partial text up.
        box.s = "现在"
        coord.textDidChange(Notification(name: NSText.didChangeNotification, object: imeTV))
        check(box.s == "现在", "partial composition not propagated to the model")
        // After commit, the real text propagates.
        imeTV.unmarkText()
        imeTV.string = "现在怎么样"
        coord.textDidChange(Notification(name: NSText.didChangeNotification, object: imeTV))
        check(box.s == "现在怎么样", "committed text propagates to the model")

        // 5) The real freeze scenario: paste into an *already-open* panel, then type. A layout
        //    feedback loop would hang here (layoutIfNeeded never settles); we assert it's prompt.
        do {
            let ek2 = EventKitService()
            let m = PanelModel(eventKit: ek2)
            let hc = NSHostingController(rootView: RootPanelView(model: m, eventKit: ek2))
            hc.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.contentViewController = hc
            win.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            let tPaste = Date()
            m.input = blobInput                       // same path a paste drives
            win.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let pasteMs = Date().timeIntervalSince(tPaste) * 1000

            let tType = Date()
            for s in ["あ", "い", "う", "え", "お"] { m.input += s; win.layoutIfNeeded() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            let typeMs = Date().timeIntervalSince(tType) * 1000
            win.close()
            print("    live paste settle: \(Int(pasteMs)) ms · 5 keystrokes: \(Int(typeMs)) ms")
            check(pasteMs < 1500, "paste into an open panel settles promptly (no freeze loop)")
            check(typeMs < 600, "typing after a big paste stays responsive")
        }

        print(failures == 0 ? "✓ UI layout self-test passed" : "✗ UI self-test had \(failures) failure(s)")
        return failures == 0 ? 0 : 1
    }
}
