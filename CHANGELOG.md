# Changelog

All notable changes to QuickAdd. Dates are when the work landed on `main`.

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
