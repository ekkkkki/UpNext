import SwiftUI
import Combine
import EventKit
import UpNextCore

/// Observable state driving the quick-add / search panel.
@MainActor
final class PanelModel: ObservableObject {
    enum Mode: Equatable { case add, search }

    @Published var mode: Mode = .add

    // Add
    @Published var input: String = "" { didSet { scheduleReparse() } }
    @Published private(set) var parsed = ParsedItem()
    @Published var toast: ToastMessage?
    @Published var errorText: String?

    // Search
    @Published var searchText: String = "" { didSet { scheduleSearch() } }
    @Published private(set) var results: [SearchHit] = []
    @Published private(set) var isSearching = false
    @Published var selectedIndex = 0
    /// Today/overdue glance shown when search opens with no query.
    @Published private(set) var agenda: [SearchHit] = []
    /// Overdue + today + next-days list shown in the add panel when the input is empty.
    @Published private(set) var upcoming: [SearchHit] = []
    /// Disabled during offscreen screenshot rendering so injected results aren't clobbered.
    var liveSearchEnabled = true

    let eventKit: EventKitService

    /// Bumped by the panel controller each time the panel is shown, so the input field
    /// re-focuses even though the SwiftUI view is reused across opens.
    @Published var focusNonce = 0
    func requestFocus() { focusNonce &+= 1 }

    /// Hooks wired up by the panel controller.
    var onClose: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?
    private var reparseTask: Task<Void, Never>?

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var symbol: String
    }

    init(eventKit: EventKitService) {
        self.eventKit = eventKit
    }

    // MARK: Add flow

    /// Debounce parsing off the keystroke path. Parsing publishes `parsed`, which re-renders
    /// the preview — doing that on every keystroke (worst of all on a long paste) is what made
    /// typing feel laggy. An empty field updates instantly so the agenda shows right away.
    private func scheduleReparse() {
        errorText = nil
        reparseTask?.cancel()
        let snapshot = input
        if snapshot.isEmpty {
            parsed = ParsedItem()
            return
        }
        reparseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000) // ~60ms
            guard let self, !Task.isCancelled, self.input == snapshot else { return }
            self.reparse()
        }
    }

    private func reparse() {
        let base = InputParser(now: Date()).parse(input)
        parsed = base
        scheduleRefine(base)
    }

    /// Optionally refine the heuristic result with the on-device LLM (debounced,
    /// non-blocking). Updates the preview if the input hasn't changed meanwhile.
    private func scheduleRefine(_ base: ParsedItem) {
        refineTask?.cancel()
        let useAI = UserDefaults.standard.bool(forKey: Theme.userDefaultsUseAI)
        guard useAI, LLMRefiner.shared.isAvailable,
              !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let snapshot = input
        refineTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            let refined = await LLMRefiner.shared.refine(input: snapshot, base: base)
            if Task.isCancelled { return }
            guard let self, self.input == snapshot else { return }
            self.parsed = refined
        }
    }

    var canSubmit: Bool {
        !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var defaultReminderList: String? {
        let v = UserDefaults.standard.string(forKey: Theme.userDefaultsDefaultList) ?? ""
        return v.isEmpty ? nil : v
    }

    /// The most recent creation(s), so ⌘Z can delete them and restore the text.
    private var lastCreated: (items: [EKCalendarItem], input: String)?
    @Published private(set) var canUndo = false

    /// Number of non-empty lines in the input (for the "Add N items" hint).
    var lineCount: Int {
        input.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.count
    }

    func submit() {
        // Parse the current text synchronously: the live parse is debounced, so typing and
        // immediately pressing ↩ must not depend on whether the debounce has fired yet.
        reparseTask?.cancel()
        let item = InputParser(now: Date()).parse(input)
        parsed = item
        guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let original = input
        do {
            let outcome = try eventKit.create(from: item, defaultListName: defaultReminderList)
            let symbol = outcome.kind == .event ? "calendar" : "checklist"
            var text = outcome.kind == .event
                ? L("Event added", "已添加日历事件", "予定を追加しました")
                : L("Reminder added", "已添加提醒", "リマインダーを追加しました")
            if let summary = DateFormatting.summary(start: outcome.date, end: outcome.endDate,
                                                    isAllDay: outcome.isAllDay, hasTime: !outcome.isAllDay) {
                text += " · \(summary)"
            }
            if let created = outcome.calendarItem {
                lastCreated = ([created], original)
                canUndo = true
                text += "  ·  " + L("⌘Z to undo", "⌘Z 撤销", "⌘Z で取り消し")
            }
            toast = ToastMessage(text: text, symbol: symbol)
            input = ""
            parsed = ParsedItem()
            loadUpcoming()
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Add one item per non-empty line (⌥↩). Falls back to `submit()` for a single line.
    func submitAll() {
        let lines = input.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count > 1 else { submit(); return }
        let original = input
        let parser = InputParser(now: Date())
        var created: [EKCalendarItem] = []
        var failures = 0
        for line in lines {
            let item = parser.parse(line)
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            do {
                if let ci = try eventKit.create(from: item, defaultListName: defaultReminderList).calendarItem {
                    created.append(ci)
                }
            } catch { failures += 1 }
        }
        guard !created.isEmpty else {
            errorText = L("Couldn't add those items.", "无法添加这些项目。", "追加できませんでした。")
            return
        }
        lastCreated = (created, original)
        canUndo = true
        let n = created.count
        var text = L("Added \(n) items", "已添加 \(n) 项", "\(n) 件追加しました")
        if failures > 0 { text += L(" (\(failures) skipped)", "（跳过 \(failures) 项）", "（\(failures) 件スキップ）") }
        text += "  ·  " + L("⌘Z to undo", "⌘Z 撤销", "⌘Z で取り消し")
        toast = ToastMessage(text: text, symbol: "checklist")
        input = ""
        parsed = ParsedItem()
        loadUpcoming()
    }

    /// Delete the last-created item(s) and restore the text for editing.
    func undoLast() {
        guard let last = lastCreated else { return }
        last.items.forEach { eventKit.undoCreate($0) }
        lastCreated = nil
        canUndo = false
        loadUpcoming()
        let msg = last.items.count > 1
            ? L("Removed \(last.items.count) items", "已撤销 \(last.items.count) 项", "\(last.items.count) 件取り消しました")
            : L("Removed — edit and add again", "已撤销，可修改后重新添加", "取り消しました — 編集して再追加")
        toast = ToastMessage(text: msg, symbol: "arrow.uturn.backward")
        input = last.input
    }

    func reset() {
        input = ""
        searchText = ""
        parsed = ParsedItem()
        results = []
        toast = nil
        errorText = nil
        mode = .add
        lastCreated = nil
        canUndo = false
        agenda = []
    }

    func agendaToggle(_ hit: SearchHit) {
        eventKit.toggleCompletion(hit)
        loadAgenda()
    }
    func agendaDelete(_ hit: SearchHit) {
        eventKit.delete(hit)
        agenda.removeAll { $0.id == hit.id }
    }

    func reschedule(_ hit: SearchHit, to date: Date) {
        eventKit.reschedule(hit, to: date)
        loadAgenda()
        loadUpcoming()
        refreshSearch()
    }

    // MARK: Search flow

    private func scheduleSearch() {
        searchTask?.cancel()
        guard liveSearchEnabled else { return }
        let text = searchText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000) // debounce
            if Task.isCancelled { return }
            guard let self else { return }
            let query = SearchQueryParser.parse(text)
            let hits = await self.eventKit.search(query)
            if Task.isCancelled { return }
            self.results = hits
            self.selectedIndex = 0
            self.isSearching = false
        }
    }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    /// Activate the highlighted result: complete/uncomplete a reminder (events have no
    /// primary toggle).
    func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let hit = results[selectedIndex]
        if hit.kind == .reminder { toggleComplete(hit) }
    }

    func refreshSearch() { scheduleSearch() }

    /// Load the Today/overdue glance (when search is opened with no query).
    func loadAgenda() {
        guard liveSearchEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let items = await self.eventKit.agenda()
            self.agenda = items
        }
    }

    /// Load the upcoming glance for the add panel (overdue + today + next ~7 days).
    func loadUpcoming() {
        guard liveSearchEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let items = await self.eventKit.upcoming(days: 7)
            self.upcoming = items
        }
    }
    func upcomingToggle(_ hit: SearchHit) {
        eventKit.toggleCompletion(hit)
        loadUpcoming()
    }
    func upcomingDelete(_ hit: SearchHit) {
        eventKit.delete(hit)
        upcoming.removeAll { $0.id == hit.id }
    }

    /// Inject results/agenda/upcoming for offscreen screenshot rendering (no EventKit fetch).
    func setPreviewResults(_ hits: [SearchHit]) {
        results = hits
        selectedIndex = 0
        isSearching = false
    }
    func setPreviewAgenda(_ hits: [SearchHit]) { agenda = hits }
    func setPreviewUpcoming(_ hits: [SearchHit]) { upcoming = hits }

    func toggleComplete(_ hit: SearchHit) {
        eventKit.toggleCompletion(hit)
        refreshSearch()
    }

    func delete(_ hit: SearchHit) {
        eventKit.delete(hit)
        results.removeAll { $0.id == hit.id }
    }
}
