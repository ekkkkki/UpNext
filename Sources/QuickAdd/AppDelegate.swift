import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let eventKit = EventKitService()
    private lazy var model = PanelModel(eventKit: eventKit)
    private lazy var panelController = PanelController(model: model, eventKit: eventKit)
    private lazy var settingsController = SettingsWindowController(eventKit: eventKit)
    private let hotKey = HotKeyManager()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        hotKey.register(keyCode: HotKeyManager.defaultKeyCode, modifiers: HotKeyManager.defaultModifiers)

        // Headless boot check: verify wiring, then exit without prompting for access.
        if CommandLine.arguments.contains("--smoke-test") {
            FileHandle.standardError.write("smoke-test: launched ok\n".data(using: .utf8)!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }
            return
        }

        // Prompt for access at launch so consent dialogs don't interrupt the panel later.
        Task { await eventKit.requestAccess() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "calendar.badge.plus", accessibilityDescription: "QuickAdd")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let add = NSMenuItem(title: "Quick Add", action: #selector(showAdd), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let search = NSMenuItem(title: "Search…", action: #selector(showSearch), keyEquivalent: "")
        search.target = self
        menu.addItem(search)
        menu.addItem(.separator())

        let hint = NSMenuItem(title: "Shortcut: ⇧⌘A", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About QuickAdd", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickAdd", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func showAdd() { panelController.show(mode: .add) }
    @objc private func showSearch() { panelController.show(mode: .search) }
    @objc private func openSettings() { settingsController.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "QuickAdd",
            .credits: NSAttributedString(
                string: "Quickly capture reminders and calendar events with natural language.\nPress ⇧⌘A from anywhere.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }
}
