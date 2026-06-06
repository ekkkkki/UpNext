import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let eventKit = EventKitService()
    private lazy var model = PanelModel(eventKit: eventKit)
    private lazy var panelController = PanelController(model: model, eventKit: eventKit)
    private lazy var settingsController = SettingsWindowController(eventKit: eventKit)
    private lazy var onboardingController = OnboardingWindowController(eventKit: eventKit) { [weak self] in
        UserDefaults.standard.set(true, forKey: "hasOnboarded")
        self?.panelController.show(mode: .add)
    }
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem?
    private weak var shortcutHintItem: NSMenuItem?
    private weak var agendaHintItem: NSMenuItem?
    private var badgeTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Theme.userDefaultsAllDayHour: 9,
            Theme.userDefaultsEventAlarmMinutes: 5
        ])
        NSApp.setActivationPolicy(.accessory) // menu-bar agent, no Dock icon

        // Render marketing screenshots (no permissions needed).
        if let idx = CommandLine.arguments.firstIndex(of: "--render-shots") {
            let next = CommandLine.arguments.indices.contains(idx + 1) ? CommandLine.arguments[idx + 1] : ""
            let dir = (!next.isEmpty && !next.hasPrefix("--")) ? next
                : FileManager.default.currentDirectoryPath + "/docs/shots"
            exit(Int32(RenderShots.run(outDir: dir)))
        }

        // Headless UI/layout check (no permissions needed).
        if CommandLine.arguments.contains("--selftest-ui") {
            let code = UISelfTest.run()
            exit(Int32(code))
        }

        // End-to-end EventKit check (creates + deletes real items). Needs access.
        if CommandLine.arguments.contains("--selftest-eventkit") {
            Task { @MainActor in
                let code = await IntegrationSelfTest.run(eventKit: eventKit)
                exit(Int32(code))
            }
            return
        }

        setupStatusItem()

        hotKey.onTrigger = { [weak self] in self?.panelController.toggle(mode: .add) }
        registerHotKey()
        NotificationCenter.default.addObserver(forName: ShortcutStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKey() }
        }

        // Headless boot check: verify wiring, then exit without prompting for access.
        if CommandLine.arguments.contains("--smoke-test") {
            FileHandle.standardError.write("smoke-test: launched ok\n".data(using: .utf8)!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }
            return
        }

        // First run shows onboarding (which requests access); afterwards just refresh.
        if UserDefaults.standard.bool(forKey: "hasOnboarded") {
            Task { await eventKit.requestAccess() }
        } else {
            onboardingController.show()
        }

        // Keep the menu-bar today-count badge fresh.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await updateAgendaHint()
        }
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.updateAgendaHint() }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func registerHotKey() {
        let s = ShortcutStore.current
        hotKey.register(keyCode: s.keyCode, modifiers: s.carbonModifiers)
        shortcutHintItem?.title = "Shortcut: \(s.display)"
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "UpNext")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.delegate = self
        let agendaHint = NSMenuItem(title: "Today: …", action: nil, keyEquivalent: "")
        agendaHint.isEnabled = false
        menu.addItem(agendaHint)
        agendaHintItem = agendaHint
        menu.addItem(.separator())

        let add = NSMenuItem(title: L("Quick Add", "快速添加", "クイック追加"), action: #selector(showAdd), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let search = NSMenuItem(title: L("Search…", "搜索…", "検索…"), action: #selector(showSearch), keyEquivalent: "")
        search.target = self
        menu.addItem(search)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "\(L("Shortcut", "快捷键", "ショートカット")): \(ShortcutStore.current.display)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        shortcutHintItem = hint
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L("Settings…", "设置…", "設定…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: L("About UpNext", "关于 UpNext", "UpNext について"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: L("Quit UpNext", "退出 UpNext", "UpNext を終了"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in await updateAgendaHint() }
    }

    private func updateAgendaHint() async {
        eventKit.refreshAuthorization()
        guard eventKit.remindersAuthorized || eventKit.calendarAuthorized else {
            agendaHintItem?.title = L("Grant access to see today", "授权后显示今日待办", "許可すると今日を表示")
            statusItem?.button?.title = ""
            return
        }
        let items = await eventKit.agenda()
        statusItem?.button?.title = items.isEmpty ? "" : " \(items.count)"
        guard !items.isEmpty else {
            agendaHintItem?.title = L("Nothing due today 🎉", "今天没有待办 🎉", "今日の予定なし 🎉")
            return
        }
        var title = L("Today: \(items.count)", "今天：\(items.count) 项", "今日：\(items.count) 件")
        if let next = items.first(where: { ($0.date ?? .distantPast) >= Date() }), let date = next.date {
            let f = DateFormatter()
            f.locale = L10n.locale
            f.dateFormat = L10n.uses24Hour ? "HH:mm" : "h:mm a"
            let name = next.title.count > 22 ? String(next.title.prefix(22)) + "…" : next.title
            title += "  ·  " + L("next: \(name) \(f.string(from: date))",
                                 "下一个：\(name) \(f.string(from: date))",
                                 "次：\(name) \(f.string(from: date))")
        }
        agendaHintItem?.title = title
    }

    @objc private func showAdd() { panelController.show(mode: .add) }
    @objc private func showSearch() { panelController.show(mode: .search) }
    @objc private func openSettings() { settingsController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "UpNext",
            .credits: NSAttributedString(
                string: "Quickly capture reminders and calendar events with natural language.\nPress ⇧⌘A from anywhere.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }
}
