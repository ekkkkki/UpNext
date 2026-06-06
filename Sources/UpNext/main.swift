import AppKit

// Entry point. Using a main.swift bootstrap (instead of @main) keeps full control
// over the AppKit lifecycle for a menu-bar accessory with a Carbon global hot key.
// Top-level code runs on the main thread, so we assume main-actor isolation to
// construct the (main-actor-isolated) app delegate.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
