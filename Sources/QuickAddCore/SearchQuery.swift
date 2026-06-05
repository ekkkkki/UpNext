import Foundation

/// A structured search request parsed from a free-form query like
/// `团队 is:event due:week ~Work #urgent !!`.
public struct SearchQuery: Equatable, Sendable {
    public enum Completion: String, Sendable { case open, done }
    public enum Due: Equatable, Sendable {
        case today, tomorrow, thisWeek, overdue, noDate, hasDate
    }

    public var text: String = ""
    public var kind: ItemKind?
    public var completion: Completion?
    public var priority: Priority?
    public var listName: String?
    public var tags: [String] = []
    public var due: Due?

    public var isEmpty: Bool {
        text.isEmpty && kind == nil && completion == nil && priority == nil
            && listName == nil && tags.isEmpty && due == nil
    }

    /// Case-insensitive substring match against an item's text fields.
    public func matchesText(title: String, notes: String?) -> Bool {
        guard !text.isEmpty else { return true }
        let needle = text.lowercased()
        if title.lowercased().contains(needle) { return true }
        if let n = notes?.lowercased(), n.contains(needle) { return true }
        return false
    }
}

/// Parses the search mini-language. Unknown tokens fall through to free text.
public enum SearchQueryParser {
    public static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()
        var textTokens: [String] = []

        for token in raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            let t = String(token)
            let lower = t.lowercased()

            if lower.hasPrefix("is:") {
                switch String(lower.dropFirst(3)) {
                case "event", "events", "calendar", "cal": query.kind = .event
                case "reminder", "reminders", "todo", "task": query.kind = .reminder
                case "done", "completed", "complete", "finished": query.completion = .done
                case "open", "incomplete", "todo:": query.completion = .open
                default: break
                }
                continue
            }
            if lower.hasPrefix("due:") {
                switch String(lower.dropFirst(4)) {
                case "today": query.due = .today
                case "tomorrow", "tmr": query.due = .tomorrow
                case "week", "thisweek", "this-week": query.due = .thisWeek
                case "overdue", "late": query.due = .overdue
                case "none", "nodate", "no-date": query.due = .noDate
                case "any", "dated": query.due = .hasDate
                default: break
                }
                continue
            }
            if lower.hasPrefix("priority:") || lower.hasPrefix("p:") {
                let val = String(lower.split(separator: ":", maxSplits: 1).last ?? "")
                query.priority = priorityFromWord(val)
                continue
            }
            if lower.hasPrefix("list:") || lower.hasPrefix("in:") {
                query.listName = String(t.split(separator: ":", maxSplits: 1).last ?? "")
                continue
            }
            if t.hasPrefix("~"), t.count > 1 {
                query.listName = String(t.dropFirst())
                continue
            }
            if t.hasPrefix("#"), t.count > 1 {
                query.tags.append(String(t.dropFirst()))
                continue
            }
            if t == "!!!" { query.priority = .high; continue }
            if t == "!!" { query.priority = .medium; continue }
            if t == "!" { query.priority = .low; continue }

            textTokens.append(t)
        }

        query.text = textTokens.joined(separator: " ")
        return query
    }

    private static func priorityFromWord(_ w: String) -> Priority? {
        switch w {
        case "high", "h", "1", "p1", "!!!", "urgent": return .high
        case "medium", "med", "m", "2", "p2", "!!": return .medium
        case "low", "l", "3", "p3", "!": return .low
        case "none", "0": return Priority.none
        default: return nil
        }
    }
}
