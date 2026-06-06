import Foundation
import EventKit
import NextorCore

/// End-to-end EventKit check: parse → create a reminder + an event → search for
/// them → delete them. Requires Reminders/Calendar access. Run with
/// `Nextor --selftest-eventkit`. Exit codes: 0 pass, 1 fail, 2 skipped (no access).
@MainActor
enum IntegrationSelfTest {
    static let marker = "Nextor self-test ✓"

    /// Result file so the outcome is readable when the app is launched via `open`
    /// (which detaches stdout). Read this after running `open --args --selftest-eventkit`.
    static let resultPath = "/tmp/nextor_selftest_result.txt"

    static func run(eventKit: EventKitService) async -> Int {
        var buffer = ""
        func flush() { try? buffer.write(toFile: resultPath, atomically: true, encoding: .utf8) }
        func log(_ s: String) { print(s); buffer += s + "\n"; flush() }
        log("▸ EventKit integration self-test")

        await eventKit.requestAccess()
        log("  reminders access: \(eventKit.remindersAuthorized ? "granted" : "denied")")
        log("  calendar  access: \(eventKit.calendarAuthorized ? "granted" : "denied")")
        guard eventKit.remindersAuthorized || eventKit.calendarAuthorized else {
            log("  ⚠︎ No access granted — skipping. Grant access in System Settings and retry.")
            log("EXIT 2")
            return 2
        }

        // Clean any leftovers from a previous run.
        await deleteMarked(eventKit)

        var failures = 0
        func check(_ cond: Bool, _ msg: String) {
            log(cond ? "  ✓ \(msg)" : "  ✗ FAIL: \(msg)")
            if !cond { failures += 1 }
        }

        let parser = InputParser()

        if eventKit.remindersAuthorized {
            let item = parser.parse("\(marker) reminder 明天 9am !!")
            do {
                let outcome = try eventKit.create(from: item)
                check(outcome.kind == .reminder, "created reminder (\(outcome.listName))")
            } catch { check(false, "create reminder threw: \(error.localizedDescription)") }

            // Recurrence count + lead-time round-trip through EventKit.
            let recItem = parser.parse("\(marker) 每天 喝水 提前30分钟 共3次")
            check(recItem.recurrence?.occurrenceCount == 3, "parsed occurrence count 3")
            check(recItem.leadTimeSeconds == 1800, "parsed lead time 30m")
            do {
                let outcome = try eventKit.create(from: recItem)
                if let r = outcome.calendarItem as? EKReminder {
                    check(r.hasRecurrenceRules, "recurrence rule attached")
                    check(r.recurrenceRules?.first?.recurrenceEnd?.occurrenceCount == 3, "EK occurrence count 3")
                    check(r.hasAlarms, "lead-time alarm attached")
                } else { check(false, "no reminder object returned") }
            } catch { check(false, "create recurring reminder threw: \(error.localizedDescription)") }
        }

        if eventKit.calendarAuthorized {
            let item = parser.parse("\(marker) event 明天 3pm-4pm")
            check(item.kind == .event, "parsed as event")
            do {
                let outcome = try eventKit.create(from: item)
                check(outcome.kind == .event, "created event (\(outcome.listName))")
            } catch { check(false, "create event threw: \(error.localizedDescription)") }

            // The user's case: date + time + address -> event with a location.
            let addr = parser.parse("\(marker) 6/8 15:30 東京都中央区晴海1-8-10 トリトンスクエア 7階")
            check(addr.kind == .event, "address parsed as event")
            check(addr.location != nil, "address location extracted")
            do {
                let outcome = try eventKit.create(from: addr)
                check(outcome.kind == .event, "created address event")
            } catch { check(false, "create address event threw: \(error.localizedDescription)") }
        }

        // Give the stores a moment to settle, then search.
        try? await Task.sleep(nanoseconds: 400_000_000)
        let hits = await eventKit.search(SearchQueryParser.parse(marker))
        let found = hits.filter { $0.title.contains(marker) }
        log("  search '\(marker)' → \(found.count) hit(s)")
        let expected = (eventKit.remindersAuthorized ? 1 : 0) + (eventKit.calendarAuthorized ? 2 : 0)
        check(found.count >= expected, "search found created item(s) (expected \(expected))")
        if eventKit.calendarAuthorized {
            let withLocation = found.contains { $0.location?.contains("トリトンスクエア") ?? false }
            check(withLocation, "event location round-trips through EventKit")
        }

        // Clean up.
        let removed = await deleteMarked(eventKit)
        log("  cleaned up \(removed) test item(s)")
        let after = await eventKit.search(SearchQueryParser.parse(marker))
        check(after.filter { $0.title.contains(marker) }.isEmpty, "no test items left behind")

        log(failures == 0 ? "✓ integration self-test passed" : "✗ integration self-test had \(failures) failure(s)")
        log("EXIT \(failures == 0 ? 0 : 1)")
        return failures == 0 ? 0 : 1
    }

    @discardableResult
    private static func deleteMarked(_ eventKit: EventKitService) async -> Int {
        let hits = await eventKit.search(SearchQueryParser.parse(marker))
        let marked = hits.filter { $0.title.contains(marker) }
        for hit in marked { eventKit.delete(hit) }
        return marked.count
    }
}
