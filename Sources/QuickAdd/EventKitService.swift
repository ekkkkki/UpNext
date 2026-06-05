import Foundation
import EventKit
import AppKit
import QuickAddCore

/// A unified, UI-friendly row for search results across Reminders and Calendar.
struct SearchHit: Identifiable {
    let id: String
    var title: String
    var notes: String?
    var kind: ItemKind
    var date: Date?
    var endDate: Date?
    var isAllDay: Bool
    var isCompleted: Bool
    var priority: Priority
    var calendarName: String
    var calendarColor: NSColor
    var location: String?
    let reminder: EKReminder?
    let event: EKEvent?
}

/// Describes what `create` produced, for the confirmation toast.
struct CreateOutcome {
    var kind: ItemKind
    var title: String
    var date: Date?
    var endDate: Date?
    var isAllDay: Bool
    var listName: String
    /// The created object, so the caller can undo (delete) it.
    var calendarItem: EKCalendarItem?
}

enum EventKitError: LocalizedError {
    case notAuthorized(String)
    case noCalendar(String)
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let what): return "Access to \(what) was not granted. Enable it in System Settings ▸ Privacy & Security."
        case .noCalendar(let what): return "No \(what) is available to save into."
        case .emptyTitle: return "Please enter a title."
        }
    }
}

/// Bridges parsed input to EventKit and runs searches. `@MainActor` because it
/// publishes state to SwiftUI and EventKit completion handlers hop back to UI.
@MainActor
final class EventKitService: ObservableObject {
    let store = EKEventStore()

    @Published var remindersAuthorized = false
    @Published var calendarAuthorized = false

    init() {
        refreshAuthorization()
    }

    // MARK: Authorization

    func refreshAuthorization() {
        remindersAuthorized = Self.isAuthorized(EKEventStore.authorizationStatus(for: .reminder))
        calendarAuthorized = Self.isAuthorized(EKEventStore.authorizationStatus(for: .event))
    }

    private static func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func requestAccess() async {
        // Request sequentially: macOS shows only one TCC prompt at a time, so firing
        // both concurrently makes the second one auto-deny.
        let reminders = (try? await store.requestFullAccessToReminders()) ?? false
        remindersAuthorized = reminders
        let events = (try? await store.requestFullAccessToEvents()) ?? false
        calendarAuthorized = events
    }

    // MARK: Lists

    func reminderLists() -> [EKCalendar] {
        store.calendars(for: .reminder).sorted { $0.title < $1.title }
    }

    func eventCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    // MARK: Creation

    @discardableResult
    func create(from item: ParsedItem, defaultListName: String? = nil) throws -> CreateOutcome {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw EventKitError.emptyTitle }

        let listName = item.listName ?? defaultListName
        return item.kind == .event
            ? try createEvent(item, title: title, listName: listName)
            : try createReminder(item, title: title, listName: listName)
    }

    private func composedNotes(_ item: ParsedItem) -> String? {
        var parts: [String] = []
        if let n = item.notes, !n.isEmpty { parts.append(n) }
        if !item.tags.isEmpty { parts.append(item.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func createReminder(_ item: ParsedItem, title: String, listName: String?) throws -> CreateOutcome {
        guard remindersAuthorized else { throw EventKitError.notAuthorized("Reminders") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = composedNotes(item)
        reminder.priority = item.priority.eventKitValue
        if let url = item.url { reminder.url = url }
        if let location = item.location, !location.isEmpty { reminder.location = location }

        let calendar = resolveCalendar(named: listName, for: .reminder)
            ?? store.defaultCalendarForNewReminders()
        guard let calendar else { throw EventKitError.noCalendar("Reminders list") }
        reminder.calendar = calendar

        var cal = Calendar.current
        cal.timeZone = .current
        if let due = item.startDate {
            let lead = item.leadTimeSeconds ?? 0
            if item.hasTime {
                reminder.dueDateComponents = cal.dateComponents([.year, .month, .day, .hour, .minute], from: due)
                reminder.addAlarm(EKAlarm(absoluteDate: due.addingTimeInterval(-lead)))
            } else {
                reminder.dueDateComponents = cal.dateComponents([.year, .month, .day], from: due)
                // All-day reminders alert at 9:00 local on the day (minus any lead time).
                if let alarmDate = cal.date(bySettingHour: 9, minute: 0, second: 0, of: due) {
                    reminder.addAlarm(EKAlarm(absoluteDate: alarmDate.addingTimeInterval(-lead)))
                }
            }
        }
        if let rule = recurrenceRule(from: item.recurrence) {
            reminder.addRecurrenceRule(rule)
        }

        try store.save(reminder, commit: true)
        return CreateOutcome(kind: .reminder, title: title, date: item.startDate, endDate: nil,
                             isAllDay: item.isAllDay, listName: calendar.title, calendarItem: reminder)
    }

    private func createEvent(_ item: ParsedItem, title: String, listName: String?) throws -> CreateOutcome {
        guard calendarAuthorized else { throw EventKitError.notAuthorized("Calendar") }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = composedNotes(item)
        if let url = item.url { event.url = url }
        if let location = item.location, !location.isEmpty { event.location = location }

        let calendar = resolveCalendar(named: listName, for: .event)
            ?? store.defaultCalendarForNewEvents
        guard let calendar else { throw EventKitError.noCalendar("calendar") }
        event.calendar = calendar

        let start = item.startDate ?? Date()
        event.startDate = start
        if item.isAllDay {
            event.isAllDay = true
            // For a day range, endDate is the exclusive day-after; EventKit wants inclusive.
            event.endDate = item.endDate.map { $0.addingTimeInterval(-1) } ?? start
        } else {
            event.endDate = item.endDate ?? start.addingTimeInterval(3600)
            event.addAlarm(EKAlarm(relativeOffset: -(item.leadTimeSeconds ?? 5 * 60))) // default 5 min before
        }
        if let rule = recurrenceRule(from: item.recurrence) {
            event.addRecurrenceRule(rule)
        }

        try store.save(event, span: .thisEvent, commit: true)
        return CreateOutcome(kind: .event, title: title, date: event.startDate, endDate: event.endDate,
                             isAllDay: event.isAllDay, listName: calendar.title, calendarItem: event)
    }

    private func resolveCalendar(named name: String?, for type: EKEntityType) -> EKCalendar? {
        guard let name, !name.isEmpty else { return nil }
        let lower = name.lowercased()
        return store.calendars(for: type).first { $0.title.lowercased() == lower }
            ?? store.calendars(for: type).first { $0.title.lowercased().contains(lower) }
    }

    private func recurrenceRule(from rule: RecurrenceRule?) -> EKRecurrenceRule? {
        guard let rule else { return nil }
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days = rule.weekdays.compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: max(1, rule.interval),
            daysOfTheWeek: days.isEmpty ? nil : days,
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil
        )
    }

    // MARK: Mutations on results

    func toggleCompletion(_ hit: SearchHit) {
        guard let reminder = hit.reminder else { return }
        reminder.isCompleted.toggle()
        try? store.save(reminder, commit: true)
    }

    /// Delete a just-created item (undo).
    func undoCreate(_ item: EKCalendarItem) {
        if let reminder = item as? EKReminder {
            try? store.remove(reminder, commit: true)
        } else if let event = item as? EKEvent {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
    }

    func delete(_ hit: SearchHit) {
        if let reminder = hit.reminder {
            try? store.remove(reminder, commit: true)
        } else if let event = hit.event {
            try? store.remove(event, span: .thisEvent, commit: true)
        }
    }

    // MARK: Search

    /// Today's glance: incomplete reminders due today or overdue, plus events occurring
    /// today. Used as the default view when search is opened with no query.
    func agenda(now: Date = Date()) async -> [SearchHit] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        guard let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) else { return [] }
        var hits: [SearchHit] = []
        let reminders = await fetchReminders(query: SearchQuery(), now: now, cal: cal)
        hits += reminders.filter { h in
            guard !h.isCompleted, let d = h.date else { return false }
            return d < endOfToday // overdue or due today
        }
        let events = fetchEvents(query: SearchQuery(), now: now, cal: cal)
        hits += events.filter { h in
            guard let d = h.date else { return false }
            return d >= startOfToday && d < endOfToday
        }
        return Array(hits.sorted(by: Self.ordering).prefix(50))
    }

    func search(_ query: SearchQuery, now: Date = Date(), limit: Int = 200) async -> [SearchHit] {
        var hits: [SearchHit] = []
        let cal = Calendar.current

        if query.kind != .event {
            hits += await fetchReminders(query: query, now: now, cal: cal)
        }
        if query.kind != .reminder {
            hits += fetchEvents(query: query, now: now, cal: cal)
        }

        let filtered = hits.filter { passesFilters($0, query: query, now: now, cal: cal) }
        let sorted = filtered.sorted(by: Self.ordering)
        return Array(sorted.prefix(limit))
    }

    private func fetchReminders(query: SearchQuery, now: Date, cal: Calendar) async -> [SearchHit] {
        guard remindersAuthorized else { return [] }
        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        return reminders.map { r in
            let due = r.dueDateComponents.flatMap { cal.date(from: $0) }
            return SearchHit(
                id: r.calendarItemIdentifier,
                title: r.title ?? "",
                notes: r.notes,
                kind: .reminder,
                date: due,
                endDate: nil,
                isAllDay: r.dueDateComponents?.hour == nil,
                isCompleted: r.isCompleted,
                priority: Priority(eventKitValue: r.priority),
                calendarName: r.calendar?.title ?? "Reminders",
                calendarColor: r.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemGray } ?? .systemGray,
                location: r.location,
                reminder: r, event: nil
            )
        }
    }

    private func fetchEvents(query: SearchQuery, now: Date, cal: Calendar) -> [SearchHit] {
        guard calendarAuthorized else { return [] }
        let start = cal.date(byAdding: .day, value: -180, to: now) ?? now
        let end = cal.date(byAdding: .day, value: 540, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { e in
            SearchHit(
                id: e.eventIdentifier ?? UUID().uuidString,
                title: e.title ?? "",
                notes: e.notes,
                kind: .event,
                date: e.startDate,
                endDate: e.endDate,
                isAllDay: e.isAllDay,
                isCompleted: false,
                priority: .none,
                calendarName: e.calendar?.title ?? "Calendar",
                calendarColor: e.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
                location: e.location,
                reminder: nil, event: e
            )
        }
    }

    private func passesFilters(_ hit: SearchHit, query: SearchQuery, now: Date, cal: Calendar) -> Bool {
        if !query.matchesText(title: hit.title, notes: hit.notes) { return false }
        if let p = query.priority, hit.priority != p { return false }
        if let c = query.completion {
            if c == .open && hit.isCompleted { return false }
            if c == .done && !hit.isCompleted { return false }
        }
        if let list = query.listName, !hit.calendarName.lowercased().contains(list.lowercased()) { return false }
        for tag in query.tags {
            if !(hit.notes?.lowercased().contains("#\(tag.lowercased())") ?? false) { return false }
        }
        if let due = query.due, !matchesDue(hit, due: due, now: now, cal: cal) { return false }
        return true
    }

    private func matchesDue(_ hit: SearchHit, due: SearchQuery.Due, now: Date, cal: Calendar) -> Bool {
        let startOfToday = cal.startOfDay(for: now)
        switch due {
        case .noDate: return hit.date == nil
        case .hasDate: return hit.date != nil
        case .overdue:
            guard let d = hit.date else { return false }
            return d < now && !hit.isCompleted
        case .today:
            guard let d = hit.date, let tomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) else { return false }
            return d >= startOfToday && d < tomorrow
        case .tomorrow:
            guard let d = hit.date,
                  let t0 = cal.date(byAdding: .day, value: 1, to: startOfToday),
                  let t1 = cal.date(byAdding: .day, value: 2, to: startOfToday) else { return false }
            return d >= t0 && d < t1
        case .thisWeek:
            guard let d = hit.date, let weekEnd = cal.date(byAdding: .day, value: 7, to: startOfToday) else { return false }
            return d >= startOfToday && d < weekEnd
        }
    }

    /// Open/overdue items with dates first; then by date; undated last; ties by priority.
    private static func ordering(_ a: SearchHit, _ b: SearchHit) -> Bool {
        switch (a.date, b.date) {
        case let (da?, db?):
            if da != db { return da < db }
            return a.priority > b.priority
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil):
            if a.priority != b.priority { return a.priority > b.priority }
            return a.title < b.title
        }
    }
}
