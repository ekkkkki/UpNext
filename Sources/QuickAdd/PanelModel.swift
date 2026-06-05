import SwiftUI
import Combine
import QuickAddCore

/// Observable state driving the quick-add / search panel.
@MainActor
final class PanelModel: ObservableObject {
    enum Mode: Equatable { case add, search }

    @Published var mode: Mode = .add

    // Add
    @Published var input: String = "" { didSet { reparse() } }
    @Published private(set) var parsed = ParsedItem()
    @Published var toast: ToastMessage?
    @Published var errorText: String?

    // Search
    @Published var searchText: String = "" { didSet { scheduleSearch() } }
    @Published private(set) var results: [SearchHit] = []
    @Published private(set) var isSearching = false
    @Published var selectedIndex = 0
    /// Disabled during offscreen screenshot rendering so injected results aren't clobbered.
    var liveSearchEnabled = true

    let eventKit: EventKitService

    /// Hooks wired up by the panel controller.
    var onClose: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private var refineTask: Task<Void, Never>?

    struct ToastMessage: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var symbol: String
    }

    init(eventKit: EventKitService) {
        self.eventKit = eventKit
    }

    // MARK: Add flow

    private func reparse() {
        errorText = nil
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

    func submit() {
        guard canSubmit else { return }
        do {
            let outcome = try eventKit.create(from: parsed, defaultListName: defaultReminderList)
            let symbol = outcome.kind == .event ? "calendar" : "checklist"
            var text = outcome.kind == .event ? "Event added" : "Reminder added"
            if let summary = DateFormatting.summary(start: outcome.date, end: outcome.endDate,
                                                    isAllDay: outcome.isAllDay, hasTime: !outcome.isAllDay) {
                text += " · \(summary)"
            }
            toast = ToastMessage(text: text, symbol: symbol)
            input = ""
            parsed = ParsedItem()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func reset() {
        input = ""
        searchText = ""
        parsed = ParsedItem()
        results = []
        toast = nil
        errorText = nil
        mode = .add
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

    /// Inject results for offscreen screenshot rendering (no EventKit fetch).
    func setPreviewResults(_ hits: [SearchHit]) {
        results = hits
        selectedIndex = 0
        isSearching = false
    }

    func toggleComplete(_ hit: SearchHit) {
        eventKit.toggleCompletion(hit)
        refreshSearch()
    }

    func delete(_ hit: SearchHit) {
        eventKit.delete(hit)
        results.removeAll { $0.id == hit.id }
    }
}
