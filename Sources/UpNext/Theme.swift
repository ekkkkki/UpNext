import SwiftUI
import AppKit
import UpNextCore

/// Colors and formatting shared across the UI.
enum Theme {
    static func color(for kind: Highlight.Kind) -> Color {
        switch kind {
        case .date, .recurrence: return .blue
        case .time, .duration: return .purple
        case .priority: return .orange
        case .list: return .green
        case .tag: return .pink
        case .url: return .teal
        case .location: return .red
        }
    }

    /// AppKit color for a recognized token, used to tint ranges in the input field.
    static func nsColor(for kind: Highlight.Kind) -> NSColor {
        switch kind {
        case .date, .recurrence: return .systemBlue
        case .time, .duration: return .systemPurple
        case .priority: return .systemOrange
        case .list: return .systemGreen
        case .tag: return .systemPink
        case .url: return .systemTeal
        case .location: return .systemRed
        }
    }

    static func priorityColor(_ p: Priority) -> Color {
        switch p {
        case .none: return .secondary
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    static let userDefaultsDefaultList = "defaultReminderList"
    static let userDefaultsDefaultCalendar = "defaultCalendarName"
    static let userDefaultsAllDayHour = "allDayReminderHour"
    static let userDefaultsEventAlarmMinutes = "defaultEventAlarmMinutes"
    static let userDefaultsUseAI = "useAppleIntelligence"
}

/// Human-friendly date/time formatting for previews and result rows.
enum DateFormatting {
    static func summary(start: Date?, end: Date?, isAllDay: Bool, hasTime: Bool, calendar: Calendar = .current) -> String? {
        guard let start else { return nil }
        let now = Date()
        let dayString = relativeDay(start, calendar: calendar, now: now)

        if isAllDay && end == nil {
            return dayString
        }
        if !hasTime && end == nil {
            return dayString
        }

        let timeFmt = DateFormatter()
        timeFmt.locale = L10n.locale
        if L10n.uses24Hour {
            timeFmt.dateFormat = "HH:mm"
        } else {
            timeFmt.dateFormat = "h:mm a"
            timeFmt.amSymbol = "AM"; timeFmt.pmSymbol = "PM"
        }

        if let end {
            // Event with a range.
            if calendar.isDate(start, inSameDayAs: end) || end.timeIntervalSince(start) <= 86400 {
                if isAllDay {
                    let endDay = relativeDay(end, calendar: calendar, now: now)
                    return dayString == endDay ? dayString : "\(dayString) – \(endDay)"
                }
                return "\(dayString) \(timeFmt.string(from: start)) – \(timeFmt.string(from: end))"
            } else {
                let endDay = relativeDay(end, calendar: calendar, now: now)
                return "\(dayString) – \(endDay)"
            }
        }
        return "\(dayString) \(timeFmt.string(from: start))"
    }

    static func relativeDay(_ date: Date, calendar: Calendar = .current, now: Date = Date()) -> String {
        let startToday = calendar.startOfDay(for: now)
        let startTarget = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
        switch days {
        case 0: return L("Today", "今天", "今日")
        case 1: return L("Tomorrow", "明天", "明日")
        case -1: return L("Yesterday", "昨天", "昨日")
        case 2...6:
            let f = DateFormatter(); f.locale = L10n.locale; f.dateFormat = "EEEE"
            return f.string(from: date)
        default:
            let f = DateFormatter(); f.locale = L10n.locale
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            if L10n.lang == .en {
                f.dateFormat = sameYear ? "EEE, MMM d" : "MMM d, yyyy"
            } else {
                f.dateFormat = sameYear ? "M月d日" : "yyyy年M月d日"
            }
            return f.string(from: date)
        }
    }

    static func rowSubtitle(_ hit: SearchHit, calendar: Calendar = .current) -> String {
        var parts: [String] = []
        if let date = hit.date {
            parts.append(summary(start: date, end: hit.endDate, isAllDay: hit.isAllDay,
                                 hasTime: !hit.isAllDay, calendar: calendar) ?? "")
        }
        parts.append(hit.calendarName)
        if let loc = hit.location, !loc.isEmpty {
            parts.append("📍 " + (loc.count > 30 ? String(loc.prefix(30)) + "…" : loc))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }
}
