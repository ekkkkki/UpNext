import AppKit

/// End-to-end check against the **real** panel — the actual `PanelController` / `FloatingPanel`
/// / `show()` path and the live SwiftUI view tree — not a stand-in harness. Run with
/// `UpNext --selftest-live-panel`. Exit 0 pass / 1 fail.
///
/// Why this exists: synthetic keystrokes are blocked without an Accessibility grant, so this is
/// the closest automated stand-in for "paste the blob and type some 中文/日本語 into the panel".
/// A surviving layout feedback loop would hang the runloop spins below (a watchdog catches it).
@MainActor
enum LivePanelSelfTest {
    static let logPath = "/tmp/upnext_livetest.txt"

    static func run(panel: PanelController, model: PanelModel) -> Int {
        // Log incrementally to a file so results survive even when launched via `open` (which
        // detaches stdout) — and so a crash still leaves the lines logged up to that point.
        FileManager.default.createFile(atPath: logPath, contents: nil)
        let fh = FileHandle(forWritingAtPath: logPath)
        var failures = 0
        func log(_ s: String) {
            print(s)
            if let d = (s + "\n").data(using: .utf8) { fh?.write(d); try? fh?.synchronize() }
        }
        func check(_ cond: Bool, _ msg: String) {
            log(cond ? "  ✓ \(msg)" : "  ✗ FAIL: \(msg)")
            if !cond { failures += 1 }
        }
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        log("▸ Live panel self-test")

        let blob = """
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

        // 1) Open the real panel. Measure both a cold open and a pre-warmed open (what the user
        //    actually gets, since the app pre-warms the panel shortly after launch).
        let tCold = Date()
        panel.show(mode: .add)
        let coldMs = Date().timeIntervalSince(tCold) * 1000
        spin(0.2)
        check(panel.isVisible, "real panel opened")
        panel.hide(); spin(0.05)
        panel.prewarm(); spin(0.05)
        let tWarm = Date()
        panel.show(mode: .add)
        let warmMs = Date().timeIntervalSince(tWarm) * 1000
        spin(0.15)
        log("    panel open — cold \(Int(coldMs)) ms · prewarmed \(Int(warmMs)) ms")
        check(warmMs < 60, "pre-warmed open is instant (<60ms)")
        // Reopen a few times — a regression here would show as climbing times.
        var reopenMax = 0.0
        for _ in 0..<3 {
            panel.hide(); spin(0.05)
            let t = Date(); panel.show(mode: .add); reopenMax = max(reopenMax, Date().timeIntervalSince(t) * 1000)
            spin(0.08)
        }
        log("    worst reopen \(Int(reopenMax)) ms")
        check(reopenMax < 400, "reopening stays fast")

        // 2) Paste the blob into the live panel. If sizeThatFits still looped, the runloop spin
        //    below would never settle and the external watchdog would kill us.
        model.ingestDocumentPaste(blob)   // the real paste path: collapse the field to the name
        let tPaste = Date()
        panel.liveContentView?.window?.layoutIfNeeded()
        let pasteMs = Date().timeIntervalSince(tPaste) * 1000
        spin(0.15)
        log("    document paste layout: \(Int(pasteMs)) ms · field=\(model.input.count) chars")
        check(pasteMs < 250, "document paste lays out instantly (field collapsed to the name)")
        check(model.input.count < 80, "field shows just the event name, not the blob")
        check(model.parsed.kind == .event, "paste still extracted as an event")

        // 3) Type into the (now large) live field — must stay responsive.
        model.input = ""
        spin(0.1)
        let tType = Date()
        for s in ["明", "日", "の", "会", "議"] { model.input += s; spin(0.02) }
        let typeMs = Date().timeIntervalSince(tType) * 1000
        log("    5 keystrokes in \(Int(typeMs)) ms")
        check(typeMs < 800, "typing in the live panel stays responsive")

        // 4) Drive a real IME composition on the actual field, then push a model update (as a
        //    re-render would) and confirm the composition is not disturbed.
        if let tv = firstTextView(in: panel.liveContentView) {
            tv.string = "现在"
            tv.setSelectedRange(NSRange(location: 2, length: 0))
            tv.setMarkedText("zenme", selectedRange: NSRange(location: 5, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
            check(tv.hasMarkedText(), "composition active in the live field (setup)")
            model.input = "现在好"            // a re-render arriving mid-composition
            spin(0.2)
            check(tv.hasMarkedText(), "live composition survives a model update")
            check((tv.string as NSString).contains("zenme"), "marked text still present in the live field")
        } else {
            check(false, "found the live NSTextView")
        }

        panel.hide()
        spin(0.1)
        log(failures == 0 ? "✓ live panel self-test passed" : "✗ live panel self-test had \(failures) failure(s)")
        log("DONE \(failures == 0 ? "PASS" : "FAIL(\(failures))")")
        try? fh?.close()
        return failures == 0 ? 0 : 1
    }

    private static func firstTextView(in view: NSView?) -> QATextView? {
        guard let view else { return nil }
        if let tv = view as? QATextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }
}
