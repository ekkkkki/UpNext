import SwiftUI
import UpNextCore

struct AddView: View {
    @ObservedObject var model: PanelModel
    @State private var focusTick = 0

    private var parsed: ParsedItem { model.parsed }
    private var isEvent: Bool { parsed.kind == .event }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            Divider().opacity(0.5)
            if let toast = model.toast {
                banner(toast.symbol, toast.text, .green)
            } else if let error = model.errorText {
                banner("exclamationmark.triangle.fill", error, .orange)
            }
            contentArea
            footer
        }
        .onAppear { focusSoon(); model.loadUpcoming() }
        .onChange(of: model.mode) { if model.mode == .add { focusSoon(); model.loadUpcoming() } }
        .onChange(of: model.toast) { if model.toast != nil { focusSoon() } }
        .onChange(of: model.focusNonce) { focusSoon() }
    }

    @ViewBuilder
    private var contentArea: some View {
        if !model.input.isEmpty {
            interpretation
        } else if !model.upcoming.isEmpty {
            upcomingList
        } else {
            hintRow
        }
    }

    @ViewBuilder
    private func banner(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 12.5, weight: .medium)).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background(color.opacity(0.10))
        .transition(.opacity)
    }

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isEvent ? "calendar.badge.clock" : "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(isEvent ? Color.purple : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .padding(.top, 3)

            GrowingTextView(
                text: $model.input,
                placeholder: L("Add a reminder or event…", "添加提醒或日程…", "リマインダー・予定を追加…"),
                focusTick: focusTick,
                highlights: parsed.highlights.map {
                    (NSRange(location: $0.location, length: $0.length), Theme.nsColor(for: $0.kind))
                },
                onSubmit: { model.submit() },
                onCancel: { model.onClose?() },
                onSubmitAll: { model.submitAll() }
            )
            .padding(.top, 1)

            ModeToggle(mode: $model.mode)
                .padding(.top, 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: Upcoming agenda (shown when the input is empty)

    private var upcomingList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedUpcoming, id: \.label) { group in
                    Section {
                        ForEach(group.items) { hit in
                            SearchRow(hit: hit,
                                      onToggle: { model.upcomingToggle(hit) },
                                      onDelete: { model.upcomingDelete(hit) },
                                      onReschedule: { model.reschedule(hit, to: $0) })
                            Divider().opacity(0.3).padding(.leading, 44)
                        }
                    } header: {
                        Text(group.label.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(group.overdue ? Color.red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 3)
                            .background(.bar)
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private struct UpcomingGroup { let label: String; let overdue: Bool; let items: [SearchHit] }

    private var groupedUpcoming: [UpcomingGroup] {
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let overdueLabel = L("Overdue", "已逾期", "期限切れ")
        let noDateLabel = L("No date", "无日程", "日付なし")

        var order: [String] = []
        var map: [String: [SearchHit]] = [:]
        var ranks: [String: Double] = [:]
        var overdueLabels: Set<String> = []

        func bucket(_ label: String, _ hit: SearchHit, rank: Double, overdue: Bool = false) {
            if map[label] == nil { order.append(label); map[label] = []; ranks[label] = rank }
            map[label]?.append(hit)
            if overdue { overdueLabels.insert(label) }
        }

        // Dated items, chronological. Overdue reminders → one group (rank -1); each day → its
        // offset from today (today 0, tomorrow 1, …).
        let dated = model.upcoming.filter { $0.date != nil }.sorted { $0.date! < $1.date! }
        for hit in dated {
            let d = hit.date!
            if hit.kind == .reminder && d < startToday {
                bucket(overdueLabel, hit, rank: -1, overdue: true)
            } else {
                let label = DateFormatting.relativeDay(d, calendar: cal, now: now)
                let days = cal.dateComponents([.day], from: startToday, to: cal.startOfDay(for: d)).day ?? 0
                bucket(label, hit, rank: Double(days))
            }
        }
        // No-date reminders sit right after Today (rank 0.5), before Tomorrow — a jotted
        // reminder is usually something to do soon.
        for hit in model.upcoming where hit.date == nil {
            bucket(noDateLabel, hit, rank: 0.5)
        }

        return order
            .sorted { (ranks[$0] ?? 0) < (ranks[$1] ?? 0) }
            .map { UpcomingGroup(label: $0, overdue: overdueLabels.contains($0), items: map[$0] ?? []) }
    }

    private var hintRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Examples", "示例", "例")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            ForEach(Self.examples(), id: \.self) { ex in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(.quaternary)
                    Text(ex).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var interpretation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: isEvent ? "calendar" : "checklist")
                    .foregroundStyle(isEvent ? Color.purple : Color.accentColor)
                Text(parsed.title.isEmpty ? "—" : parsed.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(isEvent ? L("Calendar Event", "日历事件", "カレンダー予定") : L("Reminder", "提醒", "リマインダー"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            chips
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if let summary = DateFormatting.summary(start: parsed.startDate, end: parsed.endDate,
                                                    isAllDay: parsed.isAllDay, hasTime: parsed.hasTime) {
                Chip(text: summary, systemImage: parsed.hasTime ? "clock" : "calendar", color: .blue)
            }
            if let rec = parsed.recurrence {
                Chip(text: rec.humanDescription, systemImage: "repeat", color: .indigo)
            }
            if parsed.priority != .none {
                Chip(text: parsed.priority.localizedName, systemImage: "flag.fill",
                     color: Theme.priorityColor(parsed.priority))
            }
            if let location = parsed.location {
                Chip(text: location.count > 26 ? String(location.prefix(26)) + "…" : location,
                     systemImage: "mappin.and.ellipse", color: .red)
            }
            if let lead = parsed.leadTimeSeconds {
                Chip(text: Self.leadLabel(lead), systemImage: "bell", color: .blue)
            }
            if let list = parsed.listName {
                Chip(text: list, systemImage: "folder", color: .green)
            }
            ForEach(parsed.tags, id: \.self) { tag in
                Chip(text: tag, systemImage: "number", color: .pink)
            }
            if let url = parsed.url, let host = url.host() {
                Chip(text: host, systemImage: "link", color: .teal)
            }
            if let notes = parsed.notes, !notes.isEmpty {
                Chip(text: L("Notes", "备注", "メモ"), systemImage: "note.text", color: .gray)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: model.canSubmit ? L("Add", "添加", "追加") : "…")
            if model.lineCount > 1 {
                KeyHint(key: "⌥↩", label: L("Add \(model.lineCount)", "添加 \(model.lineCount) 项", "\(model.lineCount) 件追加"))
            } else {
                KeyHint(key: "⌘F", label: L("Search", "搜索", "検索"))
            }
            KeyHint(key: "esc", label: L("Close", "关闭", "閉じる"))
            Spacer()
            if let list = model.defaultReminderList, parsed.listName == nil, !isEvent {
                Label(list, systemImage: "tray").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.black.opacity(0.04))
    }

    private func focusSoon() {
        focusTick &+= 1
    }

    static func leadLabel(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let n: Int
        let unit: (en: String, zh: String, ja: String)
        if s % 86400 == 0 { n = s / 86400; unit = ("d", "天", "日") }
        else if s % 3600 == 0 { n = s / 3600; unit = ("h", "小时", "時間") }
        else { n = s / 60; unit = ("m", "分钟", "分") }
        switch L10n.lang {
        case .en: return "\(n)\(unit.en) before"
        case .zh: return "提前\(n)\(unit.zh)"
        case .ja: return "\(n)\(unit.ja)前"
        }
    }

    static func examples() -> [String] {
        switch L10n.lang {
        case .en:
            return [
                "Lunch with Sam tomorrow 12-1pm   →  event",
                "Client meeting tomorrow 3pm 250 Main St   →  event + 📍",
                "Submit report Friday 5pm !!   →  reminder",
                "Standup every Monday 10am   →  repeating"
            ]
        case .zh:
            return [
                "明天下午3点 开会 30min   →  日历事件",
                "周五 9am-10am 团队会议   →  带时间段的事件",
                "买牛奶 ~杂货 !!   →  高优先级提醒",
                "每周一 上午10点 周会   →  重复提醒"
            ]
        case .ja:
            return [
                "明日15時 会議 30分   →  カレンダー予定",
                "明日14時-15時 1on1   →  時間範囲の予定",
                "牛乳を買う ~買い物 !!   →  リマインダー",
                "毎週月曜 午前10時 定例   →  繰り返し"
            ]
        }
    }
}

/// Compact Add/Search switch.
struct ModeToggle: View {
    @Binding var mode: PanelModel.Mode
    var body: some View {
        HStack(spacing: 2) {
            segment("plus", .add)
            segment("magnifyingglass", .search)
        }
        .padding(2)
        .background(.secondary.opacity(0.12), in: Capsule())
    }

    private func segment(_ symbol: String, _ value: PanelModel.Mode) -> some View {
        Button { mode = value } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(mode == value ? Color.accentColor.opacity(0.9) : .clear, in: Capsule())
                .foregroundStyle(mode == value ? .white : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == .add ? "Quick add" : "Search")
        .help(value == .add ? "Quick add (⌘N)" : "Search (⌘F)")
    }
}
