# Contributing to QuickAdd

Thanks for your interest! QuickAdd is a small, focused macOS app and contributions are welcome.

## Project layout

- `Sources/QuickAddCore` — pure parsing/logic, **no UI or EventKit**. Fully unit-tested and the
  best place to start. Most language/parsing improvements live here.
- `Sources/QuickAdd` — the macOS app (menu-bar agent, panel, EventKit, optional LLM).
- `Sources/QuickAddTests` — a self-contained test runner (plain Swift assertions, no XCTest —
  the Command Line Tools toolchain doesn't ship XCTest/swift-testing).

## Building & testing

```bash
swift run QuickAddTests            # unit tests (parsing, dates, recurrence, location, search, perf)
swift build -c release             # requires macOS 26 SDK (FoundationModels is weak-linked)
./package.sh                       # build the .app + .dmg
.build/debug/QuickAdd --selftest-ui        # headless UI/layout checks
QuickAdd --selftest-eventkit               # end-to-end against real Reminders/Calendar
```

Run the tests before opening a PR — `swift run QuickAddTests` must stay green (it includes a
performance regression guard).

## Adding a parsing rule

1. Add the rule in `QuickAddCore` (e.g. `DateTimeParser`, `LocationDetector`, `InputParser`).
2. Add deterministic cases to `Sources/QuickAddTests/main.swift` (the runner injects a fixed
   `now`, so date math is reproducible).
3. `swift run QuickAddTests`.

## Style

Match the surrounding code: clear names, comments that explain *why*, small focused types.
The core stays dependency-free (Foundation only) so it remains trivially testable.

## Reporting bugs / ideas

Open an issue with a sample input (the exact text you typed) and what you expected vs. got.
