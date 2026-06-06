import SwiftUI
import UpNextCore

struct SearchView: View {
    @ObservedObject var model: PanelModel
    @State private var focusTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchRow
            Divider().opacity(0.5)
            resultsArea
            footer
        }
        .onAppear { focusSoon(); model.loadAgenda() }
        .onChange(of: model.mode) { if model.mode == .search { focusSoon(); model.loadAgenda() } }
    }

    private var searchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
            SearchField(
                text: $model.searchText,
                placeholder: L("Search reminders & events…", "搜索提醒和日历…", "リマインダー・予定を検索…"),
                focusTick: focusTick,
                onMoveUp: { model.moveSelection(-1) },
                onMoveDown: { model.moveSelection(1) },
                onSubmit: { model.activateSelected() },
                onCancel: { model.onClose?() }
            )
            .frame(height: 26)
            if model.isSearching { ProgressView().controlSize(.small) }
            ModeToggle(mode: $model.mode)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    @ViewBuilder
    private var resultsArea: some View {
        if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            if model.agenda.isEmpty { emptyHint } else { agendaList }
        } else if model.results.isEmpty && !model.isSearching {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text(L("No matches", "没有匹配项", "一致なし")).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 28)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, hit in
                            SearchRow(hit: hit,
                                      isSelected: index == model.selectedIndex,
                                      onToggle: { model.toggleComplete(hit) },
                                      onDelete: { model.delete(hit) },
                                      onReschedule: { model.reschedule(hit, to: $0) })
                                .id(index)
                            Divider().opacity(0.35).padding(.leading, 44)
                        }
                    }
                }
                .frame(height: min(CGFloat(model.results.count) * 54 + 4, 380))
                .onChange(of: model.selectedIndex) { _, idx in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }

    private var agendaList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L("Today", "今天", "今日"), systemImage: "sun.max")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.agenda.count)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 2)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.agenda) { hit in
                        SearchRow(hit: hit,
                                  onToggle: { model.agendaToggle(hit) },
                                  onDelete: { model.agendaDelete(hit) },
                                  onReschedule: { model.reschedule(hit, to: $0) })
                        Divider().opacity(0.35).padding(.leading, 44)
                    }
                }
            }
            .frame(height: min(CGFloat(model.agenda.count) * 54 + 4, 340))
        }
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Filters", "筛选语法", "フィルタ")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            ForEach(Self.filterHints(), id: \.0) { hint in
                HStack(spacing: 8) {
                    Text(hint.0)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                        .frame(width: 120, alignment: .leading)
                    Text(hint.1).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↑↓", label: L("Navigate", "导航", "移動"))
            KeyHint(key: "↩", label: L("Complete", "完成", "完了"))
            KeyHint(key: "esc", label: L("Close", "关闭", "閉じる"))
            Spacer()
            if !model.results.isEmpty {
                Text(Self.resultsLabel(model.results.count))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.black.opacity(0.04))
    }

    private func focusSoon() { focusTick &+= 1 }

    static func filterHints() -> [(String, String)] {
        [
            ("is:event", L("only calendar events", "只看日历事件", "予定のみ")),
            ("is:reminder", L("only reminders", "只看提醒", "リマインダーのみ")),
            ("is:done / is:open", L("by completion", "按完成状态", "完了状態で")),
            ("due:today / week", L("overdue, today, this week", "逾期、今天、本周", "期限切れ・今日・今週")),
            ("~List   #tag", L("by list or tag", "按清单或标签", "リスト・タグで")),
            ("!!!  / priority:high", L("by priority", "按优先级", "優先度で"))
        ]
    }

    static func resultsLabel(_ n: Int) -> String {
        switch L10n.lang {
        case .en: return "\(n) result\(n == 1 ? "" : "s")"
        case .zh: return "\(n) 条结果"
        case .ja: return "\(n) 件"
        }
    }
}

struct SearchRow: View {
    let hit: SearchHit
    var isSelected = false
    var onToggle: () -> Void
    var onDelete: () -> Void
    var onReschedule: ((Date) -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.title.isEmpty ? "Untitled" : hit.title)
                        .font(.system(size: 13, weight: .medium))
                        .strikethrough(hit.isCompleted)
                        .foregroundStyle(hit.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    PriorityFlag(priority: hit.priority)
                }
                Text(DateFormatting.rowSubtitle(hit))
                    .font(.system(size: 11))
                    .foregroundStyle(overdue ? .red : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if hovering {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Delete")
                .help("Delete")
            }
            Image(systemName: hit.kind == .event ? "calendar" : "checklist")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(rowBackground)
        .onHover { hovering = $0 }
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let onReschedule {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            Menu(L("Reschedule", "改期", "日付を変更")) {
                Button(L("Today", "今天", "今日")) { onReschedule(today) }
                Button(L("Tomorrow", "明天", "明日")) { onReschedule(cal.date(byAdding: .day, value: 1, to: today) ?? today) }
                Button(L("Next week", "下周", "来週")) { onReschedule(cal.date(byAdding: .day, value: 7, to: today) ?? today) }
            }
        }
        if hit.kind == .reminder {
            Button(hit.isCompleted ? L("Mark incomplete", "标记未完成", "未完了にする")
                                   : L("Complete", "完成", "完了")) { onToggle() }
        }
        Button(L("Delete", "删除", "削除"), role: .destructive) { onDelete() }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.18)
        } else if hovering {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var leading: some View {
        if hit.kind == .reminder {
            Button(action: onToggle) {
                Image(systemName: hit.isCompleted ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(hit.isCompleted ? Color.accentColor : Color(hit.calendarColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hit.isCompleted ? "Mark incomplete" : "Mark complete")
        } else {
            Circle().fill(Color(hit.calendarColor)).frame(width: 10, height: 10).padding(.horizontal, 3)
        }
    }

    private var overdue: Bool {
        guard let d = hit.date, !hit.isCompleted, hit.kind == .reminder else { return false }
        return d < Date()
    }
}
