# Changelog

All notable changes to Nextor. Dates are when the work landed on `main`.

## v1.5.1 — 2026-06-07

A correctness + performance pass on the ⇧⌘A panel.

- **Fixed the paste freeze.** Pasting a long, multi-line blob (an event page, an invite) no
  longer hangs the app. Root cause: the input field's `sizeThatFits` mutated the view *during*
  SwiftUI's measurement, which re-entered layout every display cycle in a presented window
  (100% CPU). Sizing is now a pure, cached, offscreen measurement.
- **Fixed IME composition.** Half-typed 中文 / 日本語 no longer disappears while the candidate
  window is up — the field is never re-synced or disturbed while a composition is active; the
  text commits as one piece.
- **Snappier overall.** Parsing is debounced off the keystroke path, the field no longer echoes
  your own typing back, and redundant re-tinting is skipped. Measured in-app: panel opens in
  ~15 ms on reopen, typing ~22 ms/keystroke, a long paste settles well under a second.
- A pasted multi-line blob is parsed as **one event** — first line as the name, date/time and
  location pulled from the whole text, and the rest kept as notes.

## v1.5.0 — 2026-06-06

- **QuickAdd is now Nextor.** The panel grew from an add-only box into a glance-and-add command
  center, so the name caught up. New bundle identifier (`com.ericzhao.nextor`) — macOS will ask
  for Reminders and Calendar access once more on first launch.
- ⇧⌘A now **opens to your agenda** (overdue / today / next days) as the default view; the landing
  pages and docs relaunched around *“See what's next. Add what's new.”*

## v1.4.0 — 2026-06-05

- **Glance + add.** Opening ⇧⌘A now shows an **Upcoming** list — overdue + today + the
  next ~7 days, grouped by day (Overdue / Today / Tomorrow / weekday) — so you see what's
  next before typing. Complete, delete, or reschedule items right from the panel; the list
  refreshes after you add. Fully localized (en/zh/ja).

## v1.3.0 — 2026-06-05

- **Multi-weekday recurrence**: `每周一三五` / `毎週月水金` / `every mon wed fri` →
  weekly on several days at once.
- Titles drop dangling date-connector words ("meeting on Friday" → "meeting").
- Parser at 235 deterministic checks.

## v1.2.0 — 2026-06-05

- **Explicit `@place` location** marker (e.g. `lunch tomorrow 12pm @Blue Bottle`),
  overriding cue detection; ignores email addresses.
- **Menu-bar today-count badge** — the icon shows how many items are due today
  (refreshed on open and every 5 minutes).
- Standalone priority keywords are now stripped from the title (`buy milk urgent` →
  `buy milk`), while embedded ones stay (`重要会议`).
- Menu items and the today/next header are fully localized (en/zh/ja).
- Parser suite at 223 deterministic checks (incl. adversarial/combined inputs).

## v1.1.0 — 2026-06-05

A large parsing + UX iteration. The natural-language parser grew from 124 to 215
deterministic checks, with first-class **中文 / 日本語 / English** parity throughout.

### Added — parsing
- **Vague-time defaults**: `下午` → 14:00, `早上`/`morning` → 9:00, `今晚`/`tonight` → 19:00.
- **Lead-time alarms**: `提前30分钟`, `30分前`, `1 day before` → a real alert offset.
- **All-day**: `全天`, `all day`, `終日`.
- **Priority keywords**: `urgent` / `紧急` / `重要` / `至急` → high (standalone ones are stripped
  from the title; embedded ones kept).
- **Recurrence end conditions**: count (`共7次` / `10 times`), for-a-duration
  (`for 2 weeks` / `持续两周`), and until-a-weekday (`until Friday` / `到周五` / `金曜まで`).
- **Relative weeks/months**: `in 2 weeks` / `两周后`, `in 3 months` / `3个月后`.
- **Start / end of month**: `月初` / `start of month`, `月底` / `end of month`.
- **First-class Japanese**: weekdays (月曜…日曜), 午前/午後/朝/夜/昼, 明後日, 来週/来月,
  毎日/毎週<曜>, 時間 / 時間半 durations.

### Added — app
- **Customizable global hot key** (recorder in Settings; ⇧⌘A default).
- **Undo last add** (⌘Z) — removes the just-created item(s) and restores the text.
- **Batch add** (⌥↩) — one item per line when you paste a list.
- **Today agenda** as the default Search view, plus a menu-bar “Today: N · next …” glance.
- **Right-click reschedule** of reminders *and* events (Today / Tomorrow / Next week).
- **First-run onboarding** window.
- **Configurable default alerts** (all-day reminder hour; default event alert).
- **Localized UI** (en/zh/ja) — chrome follows the system language.
- Live **colored token highlighting** in the input.

### Performance
- Memoized the date/time regexes (were recompiled every keystroke): ~4× faster parsing.

### Changed
- Notes split only on an explicit ` // ` (a bare newline is kept, so multi-line
  addresses stay intact).

## v1.0.0 — 2026-06-05

Initial release: ⇧⌘A quick-add panel, reminder-vs-event classification with location
extraction, bilingual natural-language parsing, unified search across Reminders +
Calendar, menu-bar agent, optional on-device Apple Intelligence refinement, packaged
`.app` + DMG.
