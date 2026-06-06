import Foundation

/// Minimal assertion harness — XCTest/swift-testing aren't available under CLT.
final class Harness {
    private(set) var total = 0
    private(set) var failures = 0
    private var currentGroup = ""
    let dateFormatter: DateFormatter

    init(timeZone: TimeZone) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter = f
    }

    func group(_ name: String) {
        currentGroup = name
        print("\n\u{001B}[1m▸ \(name)\u{001B}[0m")
    }

    func ok(_ condition: Bool, _ message: @autoclosure () -> String, line: Int = #line) {
        total += 1
        if condition {
            print("  \u{001B}[32m✓\u{001B}[0m \(message())")
        } else {
            failures += 1
            print("  \u{001B}[31m✗ FAIL\u{001B}[0m (line \(line)) \(message())")
        }
    }

    func eq<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
        ok(actual == expected, "\(label): \(render(actual)) == \(render(expected))", line: line)
    }

    func render<T>(_ value: T) -> String {
        if let d = value as? Date { return dateFormatter.string(from: d) }
        if let d = value as? Date? { return d.map { dateFormatter.string(from: $0) } ?? "nil" }
        return "\(value)"
    }

    func summarize() -> Int {
        let passed = total - failures
        print("\n" + String(repeating: "─", count: 48))
        if failures == 0 {
            print("\u{001B}[32m✓ All \(total) checks passed\u{001B}[0m")
        } else {
            print("\u{001B}[31m✗ \(failures) of \(total) checks failed\u{001B}[0m (\(passed) passed)")
        }
        return failures == 0 ? 0 : 1
    }
}
