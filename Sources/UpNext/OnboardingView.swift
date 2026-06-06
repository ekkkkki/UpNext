import SwiftUI
import AppKit

/// First-run welcome: explains the hot key, requests access, and sets the onboarded flag.
struct OnboardingView: View {
    @ObservedObject var eventKit: EventKitService
    var shortcutDisplay: String
    var onDone: () -> Void

    private var granted: Bool { eventKit.remindersAuthorized && eventKit.calendarAuthorized }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 46))
                .foregroundStyle(LinearGradient(colors: [.accentColor, .purple], startPoint: .top, endPoint: .bottom))
                .padding(.top, 6)

            Text(L("Welcome to UpNext", "欢迎使用 UpNext", "UpNext へようこそ"))
                .font(.title2.bold())
            Text(L("Capture reminders and calendar events from anywhere — just type the way you think.",
                   "在任何地方记下提醒和日历事件——像说话一样打字即可。",
                   "どこからでもリマインダーや予定を登録。思ったまま入力するだけ。"))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Text(L("Press", "按", "ショートカット")).foregroundStyle(.secondary)
                Text(shortcutDisplay)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                Text(L("anytime to open it.", "随时呼出。", "でいつでも開けます。")).foregroundStyle(.secondary)
            }
            .font(.callout)

            VStack(alignment: .leading, spacing: 8) {
                bullet("🌏", L("Understands 中文 / 日本語 / English", "看得懂中文 / 日本語 / English", "中文 / 日本語 / English を理解"))
                bullet("📍", L("A meeting with a place becomes a calendar event", "带地点的会议会变成日历事件", "場所つきの会議はカレンダー予定に"))
                bullet("🔎", L("Search reminders and calendar together", "提醒和日历一起搜索", "リマインダーとカレンダーを横断検索"))
            }
            .padding(.vertical, 4)

            if granted {
                Label(L("Reminders & Calendar access granted", "已获得提醒与日历权限", "リマインダー・カレンダーへのアクセス許可済み"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            } else {
                Button(L("Grant Access to Reminders & Calendar", "授权访问提醒与日历", "リマインダー・カレンダーへのアクセスを許可")) {
                    Task { await eventKit.requestAccess() }
                }
                .controlSize(.large)
            }

            Button(L("Get Started", "开始使用", "はじめる"), action: onDone)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 2)
        }
        .padding(36)
        .frame(width: 460)
    }

    private func bullet(_ emoji: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji)
            Text(text).font(.callout).foregroundStyle(.primary.opacity(0.9))
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let eventKit: EventKitService
    private let onFinish: () -> Void

    init(eventKit: EventKitService, onFinish: @escaping () -> Void) {
        self.eventKit = eventKit
        self.onFinish = onFinish
    }

    func show() {
        eventKit.refreshAuthorization()
        let root = OnboardingView(eventKit: eventKit, shortcutDisplay: ShortcutStore.current.display) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: hosting)
        w.title = "UpNext"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.close()
        window = nil
        onFinish()
    }
}
