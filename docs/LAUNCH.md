# QuickAdd — launch & press kit

Everything you need to announce QuickAdd. Copy/paste and tweak. Replace `ekkkkki/QuickAdd`
and the release URL if the repo path changes.

- Repo: https://github.com/ekkkkki/QuickAdd
- Landing page: https://ekkkkki.github.io/QuickAdd/
- Download: https://github.com/ekkkkki/QuickAdd/releases/latest

---

## Positioning

**One-liner:** Press ⇧⌘A anywhere and type in plain language — QuickAdd files it as a Reminder or
Calendar event, in 中文 / 日本語 / English.

**Taglines (pick one):**
- Capture anything, one keystroke away.
- Quick-add for Apple Reminders & Calendar — native, free, bilingual.
- Stop switching apps to jot a reminder.
- TickTick-style quick capture, but native and open source.

**Short description (≤ 240 chars):**
A free, open-source macOS menu-bar app. Hit ⇧⌘A, type the way you think (中文/日本語/English), and it
decides Reminder vs. Calendar event, extracting time, location, priority, list, tags and recurrence
automatically. Local & private.

**Long description:**
QuickAdd is a tiny native macOS app for capturing to-dos and events without breaking flow. A global
hotkey (⇧⌘A) opens a Spotlight-style panel over any app. Type naturally — `明天下午3点 开会 30min`,
`Team sync tomorrow 2-3pm ~Work`, or paste a whole address — and QuickAdd's bilingual parser works out
whether it's a Reminder or a Calendar event, and pulls out the time, duration/range, location, priority,
target list, tags and recurrence. Tokens are color-coded live as you type, with a preview of exactly what
will be created. It also has a unified fuzzy search across both Reminders and Calendar
(`is:event due:week ~Work`). Everything runs locally; an optional on-device Apple Intelligence pass can
refine tricky cases, but nothing ever leaves your Mac. Free, MIT-licensed, no account, no tracking.

---

## Show HN

**Title:** Show HN: QuickAdd – ⇧⌘A to capture reminders/events on macOS (bilingual NL parsing)

**Body:**
I kept losing thoughts because adding a reminder or a calendar event meant switching apps and clicking
through forms. So I built QuickAdd: a menu-bar app where ⇧⌘A opens a quick box, you type in plain language,
and it saves to Apple Reminders or Calendar.

The part I'm most happy with is the parsing. It's bilingual (Chinese/Japanese/English) and decides Reminder
vs. Calendar event from the text: a time range or duration → event; a place or a meeting word → event;
otherwise a reminder. It also extracts location — paste a Japanese address block and it becomes an event
with the location field filled. There's a unified search across Reminders + Calendar with filters.

It's native Swift/SwiftUI, no Electron, runs as a menu-bar agent. The parser is a dependency-free core with
~120 deterministic tests; there's also a headless UI-layout test and an end-to-end EventKit test. Optional
on-device Apple Intelligence refinement, off by default — everything is local.

Free and MIT-licensed. Feedback on the parsing (especially edge cases / other languages) very welcome.

GitHub: https://github.com/ekkkkki/QuickAdd

---

## Product Hunt

**Name:** QuickAdd
**Tagline:** Capture reminders & events from anywhere — ⇧⌘A, in any language
**Description:**
QuickAdd is a free, open-source macOS menu-bar app for capturing to-dos and events without leaving what
you're doing. Press ⇧⌘A, type naturally in Chinese, Japanese or English, and it figures out whether you
mean a Reminder or a Calendar event — extracting the time, location, priority, list, tags and recurrence
for you. Plus a unified search across both. Native, local, private.

**Maker's first comment:**
Hey PH 👋 I built QuickAdd because quick-capture apps I liked (TickTick et al.) weren't native and didn't
handle my mixed Chinese/English/Japanese input well. This one is pure Swift, lives in the menu bar, and
leans hard on natural-language parsing — including turning a pasted address into an event with a location.
It's MIT-licensed and free forever. Would love your tricky inputs to test the parser against!

---

## X / Twitter thread

1/ I made QuickAdd: press ⇧⌘A anywhere on your Mac, type a reminder or event in plain language, done.
中文 / 日本語 / English. Native, free, open source. 🧵

2/ It decides Reminder vs Calendar event from how you type:
• `明天3点 开会 30min` → 30-min event
• `周五 9-10am 团队会议` → event (time range)
• `买牛奶 ~Groceries !!` → high-priority reminder

3/ Paste a whole address and it becomes a calendar event with the location filled in 📍 — the parser knows
"具体时间 + 地点 = 会议".

4/ Tokens are color-coded live as you type, and there's a unified search across Reminders + Calendar:
`is:event due:week ~Work`.

5/ All local. Optional on-device Apple Intelligence refinement, off by default — nothing leaves your Mac.
MIT-licensed, free. ⬇️ github.com/ekkkkki/QuickAdd

---

## Reddit (r/macapps, r/productivity)

**Title:** [Free/OSS] QuickAdd — ⇧⌘A to add a Reminder or Calendar event in plain language (中/日/EN)

**Body:**
Built a small native menu-bar app to scratch my own itch: capturing reminders/events without switching
apps. ⇧⌘A opens a quick box; type naturally and it saves to Apple Reminders or Calendar, choosing the right
one based on the text (time range/duration or a place → event; otherwise reminder). Extracts time, location,
priority, list, tags, recurrence; bilingual; unified search across both. Native Swift, local & private, MIT.
Not selling anything — feedback welcome, especially parsing edge cases. github.com/ekkkkki/QuickAdd

---

## 中文版（V2EX / 即刻 / 小红书 / 少数派）

**标题：** 做了个 macOS 小工具 QuickAdd：⇧⌘A 一下，用大白话加提醒/日历（中日英都行，免费开源）

**正文：**
一直嫌弃加个提醒还要切 App、点半天表单，于是写了个菜单栏小工具 **QuickAdd**。

按 **⇧⌘A** 在任何界面弹出输入框，像说话一样打字，它自动判断是「提醒事项」还是「日历事件」，并解析出时间、地点、重要度、清单、标签、重复规则：
- `明天下午3点 开会 30min` → 30 分钟的日历事件
- `周五 9am-10am 团队会议` → 带时间段的事件
- `6/8 15:30 东京都中央区晴海1-8-10 …` → 直接变成带 **location** 的会议 📍
- `买牛奶 ~Groceries !!` → 放进"Groceries"清单的高优先级提醒
- `每周一 上午10点 周会` → 每周重复

输入时 token 会实时高亮，还有横跨提醒+日历的智能搜索（`is:event due:week ~Work`）。
纯原生 Swift，数据全在本地；可选开启端侧 Apple Intelligence 做更聪明的识别，但**什么都不会离开你的电脑**。
**完全免费、MIT 开源**。

GitHub: https://github.com/ekkkkki/QuickAdd

---

## Assets

- App icon: gradient squircle + white “+” (generated by `Packaging/make_icon.swift`).
- Screenshots: `docs/shots/{hero,add-reminder,add-event,search}.png` (regenerate with
  `QuickAdd --render-shots docs/shots`).
- Suggested social image: `docs/shots/hero.png`.

## Suggested launch checklist

- [ ] Cut a GitHub Release with the `.dmg` attached.
- [ ] Enable GitHub Pages (Settings → Pages → Deploy from `main`/`docs`).
- [ ] Post Show HN in the morning (US Pacific), reply to every comment.
- [ ] Product Hunt (schedule 12:01am PT), line up the first comment.
- [ ] Cross-post to r/macapps, V2EX, 少数派.
- [ ] Add the repo topics: `macos`, `swift`, `swiftui`, `reminders`, `calendar`, `productivity`, `menubar`, `eventkit`.
