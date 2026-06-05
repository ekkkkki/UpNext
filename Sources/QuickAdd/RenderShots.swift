import AppKit
import SwiftUI
import QuickAddCore

/// Renders polished screenshots of the panel headlessly (no manual capture needed),
/// for the README and landing page. Run: `QuickAdd --render-shots <dir>`.
@MainActor
enum RenderShots {
    static func run(outDir: String) -> Int {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let eventKit = EventKitService()
        var count = 0

        func shot(_ name: String, configure: (PanelModel) -> Void) {
            let model = PanelModel(eventKit: eventKit)
            configure(model)

            // Measure the panel's intrinsic height first.
            let probe = NSHostingController(rootView: RootPanelView(model: model, eventKit: eventKit, solidBackground: true))
            let probeWin = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 1400),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
            probeWin.appearance = NSAppearance(named: .darkAqua)
            probeWin.contentViewController = probe
            probeWin.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            let panelHeight = max(probe.view.fittingSize.height, 120)
            probeWin.close()

            let containerHeight = panelHeight + 168
            let content = ShotContainer(height: containerHeight) {
                RootPanelView(model: model, eventKit: eventKit, solidBackground: true)
            }
            .preferredColorScheme(.dark)

            let hc = NSHostingController(rootView: content)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: containerHeight),
                               styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = NSAppearance(named: .darkAqua)
            win.contentViewController = hc
            hc.view.frame = NSRect(x: 0, y: 0, width: 860, height: containerHeight)
            win.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))

            if let data = snapshot(hc.view) {
                let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
                try? data.write(to: url)
                count += 1
                print("  ✓ \(name).png")
            } else {
                print("  ✗ failed \(name)")
            }
            win.close()
        }

        shot("hero") { m in
            m.reset()
            m.input = "6/8 15:30 東京都中央区晴海1-8-10 トリトンスクエア オフィスタワーX棟 7階"
        }
        shot("add-reminder") { m in
            m.reset()
            m.input = "买菜 ~Groceries #weekend 明天 !!"
        }
        shot("add-event") { m in
            m.reset()
            m.input = "Team sync tomorrow 2-3pm ~Work !!"
        }
        shot("search") { m in
            m.reset()
            m.liveSearchEnabled = false
            m.mode = .search
            m.searchText = "due:week"
            m.setPreviewResults(sampleHits())
        }

        print("rendered \(count) screenshot(s) → \(outDir)")
        return count > 0 ? 0 : 1
    }

    private static func snapshot(_ view: NSView) -> Data? {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private static func sampleHits() -> [SearchHit] {
        let cal = Calendar.current
        let now = Date()
        func at(_ dayOffset: Int, _ h: Int, _ m: Int) -> Date {
            let base = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: now))!
            return cal.date(byAdding: DateComponents(hour: h, minute: m), to: base)!
        }
        return [
            SearchHit(id: "1", title: "Team weekly sync", notes: nil, kind: .event,
                      date: at(1, 10, 0), endDate: at(1, 11, 0), isAllDay: false, isCompleted: false,
                      priority: .none, calendarName: "Work", calendarColor: .systemBlue,
                      location: "会議室A · Room A", reminder: nil, event: nil),
            SearchHit(id: "2", title: "买牛奶和鸡蛋", notes: nil, kind: .reminder,
                      date: at(0, 18, 0), endDate: nil, isAllDay: false, isCompleted: false,
                      priority: .medium, calendarName: "Groceries", calendarColor: .systemGreen,
                      location: nil, reminder: nil, event: nil),
            SearchHit(id: "3", title: "提交季度报告", notes: nil, kind: .reminder,
                      date: at(-1, 17, 0), endDate: nil, isAllDay: false, isCompleted: false,
                      priority: .high, calendarName: "Work", calendarColor: .systemOrange,
                      location: nil, reminder: nil, event: nil),
            SearchHit(id: "4", title: "查酒店地址", notes: nil, kind: .event,
                      date: at(3, 9, 0), endDate: at(3, 10, 0), isAllDay: false, isCompleted: false,
                      priority: .none, calendarName: "Travel", calendarColor: .systemPurple,
                      location: "Tokyo Station Hotel", reminder: nil, event: nil)
        ]
    }
}

private struct ShotContainer<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.15),
                    Color(red: 0.20, green: 0.13, blue: 0.30)
                ]),
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            content()
                .shadow(color: .black.opacity(0.55), radius: 34, y: 16)
        }
        .frame(width: 860, height: height)
    }
}
