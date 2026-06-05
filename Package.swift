// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickAdd",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuickAdd", targets: ["QuickAdd"]),
        .executable(name: "QuickAddTests", targets: ["QuickAddTests"]),
        .library(name: "QuickAddCore", targets: ["QuickAddCore"])
    ],
    targets: [
        // Pure-logic core: natural-language parsing, models. No UI / EventKit deps,
        // so it is fully unit-testable and fast to iterate on.
        .target(
            name: "QuickAddCore",
            path: "Sources/QuickAddCore"
        ),
        // The macOS app: menu-bar agent, global hot key, quick-add panel, search,
        // and the EventKit bridge that turns parsed input into Reminders / Calendar items.
        .executableTarget(
            name: "QuickAdd",
            dependencies: ["QuickAddCore"],
            path: "Sources/QuickAdd",
            // FoundationModels (Apple Intelligence) is macOS 26+. Disable autolink and
            // weak-link it so the app still launches on macOS 14–25; all usage is behind
            // `#available(macOS 26)` + an availability check.
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-autolink-framework", "-Xfrontend", "FoundationModels"])
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "FoundationModels"])
            ]
        ),
        // Self-contained test runner. XCTest/swift-testing are unavailable under the
        // Command Line Tools toolchain, so the parser suite is plain Swift assertions
        // runnable via `swift run QuickAddTests`. Doubles as a functional harness.
        .executableTarget(
            name: "QuickAddTests",
            dependencies: ["QuickAddCore"],
            path: "Sources/QuickAddTests"
        )
    ]
)
