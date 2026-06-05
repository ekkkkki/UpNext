import SwiftUI
import QuickAddCore

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
        .onAppear { focusSoon() }
        .onChange(of: model.mode) { if model.mode == .search { focusSoon() } }
    }

    private var searchRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
            SearchField(
                text: $model.searchText,
                placeholder: "Search reminders & events…",
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
            emptyHint
        } else if model.results.isEmpty && !model.isSearching {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("No matches").font(.system(size: 13)).foregroundStyle(.secondary)
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
                                      onDelete: { model.delete(hit) })
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

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filters").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            ForEach(Self.filterHints, id: \.0) { hint in
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
            KeyHint(key: "↑↓", label: "Navigate")
            KeyHint(key: "↩", label: "Complete")
            KeyHint(key: "esc", label: "Close")
            Spacer()
            if !model.results.isEmpty {
                Text("\(model.results.count) result\(model.results.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.black.opacity(0.04))
    }

    private func focusSoon() { focusTick &+= 1 }

    static let filterHints: [(String, String)] = [
        ("is:event", "only calendar events"),
        ("is:reminder", "only reminders"),
        ("is:done / is:open", "by completion"),
        ("due:today / week", "overdue, today, this week"),
        ("~List   #tag", "by list or tag"),
        ("!!!  / priority:high", "by priority")
    ]
}

struct SearchRow: View {
    let hit: SearchHit
    var isSelected = false
    var onToggle: () -> Void
    var onDelete: () -> Void
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
