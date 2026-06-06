import SwiftUI
import AppKit
import ServiceManagement
import UpNextCore

struct SettingsView: View {
    @ObservedObject var eventKit: EventKitService
    @AppStorage(Theme.userDefaultsDefaultList) private var defaultList = ""
    @AppStorage(Theme.userDefaultsDefaultCalendar) private var defaultCalendar = ""
    @AppStorage(Theme.userDefaultsUseAI) private var useAI = false
    @AppStorage(Theme.userDefaultsAllDayHour) private var allDayHour = 9
    @AppStorage(Theme.userDefaultsEventAlarmMinutes) private var eventAlarmMinutes = 5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var shortcut = ShortcutStore.current

    var body: some View {
        Form {
            Section("Access") {
                accessRow(title: "Reminders", granted: eventKit.remindersAuthorized)
                accessRow(title: "Calendar", granted: eventKit.calendarAuthorized)
                HStack {
                    Button("Request Access") { Task { await eventKit.requestAccess() } }
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Section("Defaults") {
                Picker("New reminders go to", selection: $defaultList) {
                    Text("Default list").tag("")
                    ForEach(eventKit.reminderLists(), id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal.title)
                    }
                }
                Picker("New events go to", selection: $defaultCalendar) {
                    Text("Default calendar").tag("")
                    ForEach(eventKit.eventCalendars(), id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal.title)
                    }
                }
                Picker("All-day reminders alert at", selection: $allDayHour) {
                    ForEach(Array(stride(from: 6, through: 22, by: 1)), id: \.self) { h in
                        Text(String(format: "%02d:00", h)).tag(h)
                    }
                }
                Picker("Default event alert", selection: $eventAlarmMinutes) {
                    Text("None").tag(-1)
                    Text("At start time").tag(0)
                    Text("5 minutes before").tag(5)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                }
                Text("Override per item with ~ListName, or “提前30分钟 / 1 day before” for a custom alert.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Intelligence") {
                Toggle("Refine with Apple Intelligence (on-device)", isOn: $useAI)
                    .disabled(!LLMRefiner.shared.isAvailable)
                LabeledContent("Status") {
                    let a = LLMRefiner.shared.availability
                    Label(a.userText, systemImage: a == .available ? "sparkles" : "info.circle")
                        .foregroundStyle(a == .available ? .green : .secondary)
                        .font(.callout).labelStyle(.titleAndIcon)
                }
                Text("The built-in parser always runs. When enabled and available, the on-device model refines tricky cases (named venues, ambiguous meetings). Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                LabeledContent("Quick-add shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: shortcut) { s in
                            shortcut = s
                            ShortcutStore.current = s
                        }
                        .frame(width: 160, height: 26)
                        Button("Reset") {
                            shortcut = ShortcutStore.defaultShortcut
                            ShortcutStore.current = ShortcutStore.defaultShortcut
                        }
                        .controlSize(.small)
                    }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UpNext \(appVersion)").font(.headline)
                    Text("Capture reminders and calendar events from anywhere with natural language.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 480)
        .onAppear { eventKit.refreshAuthorization() }
    }

    private func accessRow(title: String, granted: Bool) -> some View {
        LabeledContent(title) {
            Label(granted ? "Granted" : "Not granted", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .orange)
                .labelStyle(.titleAndIcon)
                .font(.callout)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Hosts `SettingsView` in a normal titled window (kept around between opens).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let eventKit: EventKitService

    init(eventKit: EventKitService) { self.eventKit = eventKit }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(eventKit: eventKit))
            let w = NSWindow(contentViewController: hosting)
            w.title = "UpNext Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
