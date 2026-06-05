import Foundation

/// Importance level. Maps to EventKit's numeric reminder priority on the app side.
public enum Priority: Int, CaseIterable, Codable, Sendable, Comparable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// EventKit / CalDAV numeric priority (1 = high … 9 = low, 0 = unset).
    public var eventKitValue: Int {
        switch self {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    /// Reconstruct a semantic priority from an EventKit numeric value.
    public init(eventKitValue value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    public var symbol: String {
        switch self {
        case .none: return ""
        case .low: return "!"
        case .medium: return "!!"
        case .high: return "!!!"
        }
    }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Whether the parsed text should become a Reminder or a timed Calendar event.
public enum ItemKind: String, Codable, Sendable {
    case reminder
    case event
}

public enum RecurrenceFrequency: String, Codable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

/// A simple recurrence description (EventKit rule is built from this on the app side).
public struct RecurrenceRule: Equatable, Codable, Sendable {
    public var frequency: RecurrenceFrequency
    public var interval: Int
    /// Calendar weekday numbers (1 = Sunday … 7 = Saturday) for weekly rules on specific days.
    public var weekdays: [Int]

    public init(frequency: RecurrenceFrequency, interval: Int = 1, weekdays: [Int] = []) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
    }

    public var humanDescription: String {
        let every = interval > 1 ? "every \(interval) " : "every "
        switch frequency {
        case .daily: return interval > 1 ? "\(every)days" : "daily"
        case .weekly:
            if weekdays.isEmpty { return interval > 1 ? "\(every)weeks" : "weekly" }
            let names = weekdays.sorted().map { Self.weekdayShortNames[$0 - 1] }.joined(separator: ", ")
            return "weekly on \(names)"
        case .monthly: return interval > 1 ? "\(every)months" : "monthly"
        case .yearly: return interval > 1 ? "\(every)years" : "yearly"
        }
    }

    static let weekdayShortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
}

/// A span of the original input string that the parser recognized as structured data,
/// used by the UI to highlight tokens (date, priority, etc.) live as the user types.
public struct Highlight: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case date
        case time
        case duration
        case priority
        case list
        case tag
        case recurrence
        case url
        case location
    }
    /// UTF-16 offset range into the *original* input (compatible with NSAttributedString).
    public var location: Int
    public var length: Int
    public var kind: Kind

    public init(location: Int, length: Int, kind: Kind) {
        self.location = location
        self.length = length
        self.kind = kind
    }

    public var nsRange: NSRange { NSRange(location: location, length: length) }
}

/// The fully-resolved result of parsing a quick-add line.
public struct ParsedItem: Equatable, Sendable {
    public var title: String
    public var notes: String?
    public var kind: ItemKind
    public var priority: Priority

    /// Due date (reminder) or start (event). `nil` means no date was specified.
    public var startDate: Date?
    /// End of a calendar event. Non-nil only when `kind == .event`.
    public var endDate: Date?
    /// True when only a calendar day was given with no clock time.
    public var isAllDay: Bool
    /// True when a specific time-of-day was recognized.
    public var hasTime: Bool

    /// Target Reminders list or Calendar name, from `~name`.
    public var listName: String?
    /// Hashtags, from `#tag`.
    public var tags: [String]
    public var url: URL?
    public var recurrence: RecurrenceRule?
    /// Physical place / address (events). Set the event's location on creation.
    public var location: String?
    /// Seconds before the start to alert ("remind 30 min before" / 提前30分钟 / 30分前).
    public var leadTimeSeconds: TimeInterval?

    /// Recognized spans in the original input (for live highlighting).
    public var highlights: [Highlight]

    public init(
        title: String = "",
        notes: String? = nil,
        kind: ItemKind = .reminder,
        priority: Priority = .none,
        startDate: Date? = nil,
        endDate: Date? = nil,
        isAllDay: Bool = false,
        hasTime: Bool = false,
        listName: String? = nil,
        tags: [String] = [],
        url: URL? = nil,
        recurrence: RecurrenceRule? = nil,
        location: String? = nil,
        leadTimeSeconds: TimeInterval? = nil,
        highlights: [Highlight] = []
    ) {
        self.title = title
        self.notes = notes
        self.kind = kind
        self.priority = priority
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.hasTime = hasTime
        self.listName = listName
        self.tags = tags
        self.url = url
        self.recurrence = recurrence
        self.location = location
        self.leadTimeSeconds = leadTimeSeconds
        self.highlights = highlights
    }

    /// Duration of the event in seconds, if both ends are known.
    public var durationSeconds: TimeInterval? {
        guard let s = startDate, let e = endDate else { return nil }
        return e.timeIntervalSince(s)
    }
}
