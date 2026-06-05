import SwiftUI
import QuickAddCore

struct AddView: View {
    @ObservedObject var model: PanelModel
    @State private var focusTick = 0

    private var parsed: ParsedItem { model.parsed }
    private var isEvent: Bool { parsed.kind == .event }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputRow
            Divider().opacity(0.5)
            previewArea
            footer
        }
        .onAppear { focusSoon() }
        .onChange(of: model.mode) { if model.mode == .add { focusSoon() } }
        .onChange(of: model.toast) { if model.toast != nil { focusSoon() } }
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
                placeholder: "Add a reminder or event…",
                focusTick: focusTick,
                highlights: parsed.highlights.map {
                    (NSRange(location: $0.location, length: $0.length), Theme.nsColor(for: $0.kind))
                },
                onSubmit: { model.submit() },
                onCancel: { model.onClose?() }
            )
            .padding(.top, 1)

            ModeToggle(mode: $model.mode)
                .padding(.top, 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var previewArea: some View {
        if let toast = model.toast {
            HStack(spacing: 8) {
                Image(systemName: toast.symbol).foregroundStyle(.green)
                Text(toast.text).font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .transition(.opacity)
        } else if let error = model.errorText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        } else if model.input.isEmpty {
            hintRow
        } else {
            interpretation
        }
    }

    private var hintRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Examples").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            ForEach(Self.examples, id: \.self) { ex in
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
                Text(isEvent ? "Calendar Event" : "Reminder")
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
            if let list = parsed.listName {
                Chip(text: list, systemImage: "folder", color: .green)
            }
            ForEach(parsed.tags, id: \.self) { tag in
                Chip(text: tag, systemImage: "number", color: .pink)
            }
            if let url = parsed.url, let host = url.host() {
                Chip(text: host, systemImage: "link", color: .teal)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: model.canSubmit ? "Add" : "…")
            KeyHint(key: "⌘F", label: "Search")
            KeyHint(key: "esc", label: "Close")
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

    static let examples = [
        "明天下午3点 开会 30min   →  calendar event",
        "周五 9am-10am 团队会议   →  event with range",
        "买牛奶 ~Groceries !!   →  reminder, high priority",
        "每周一 上午10点 周会   →  repeating reminder"
    ]
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
