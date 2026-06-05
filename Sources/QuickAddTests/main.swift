import Foundation
import QuickAddCore

// Deterministic reference clock: Friday 2026-06-05 09:00 in a fixed zone.
let tz = TimeZone(identifier: "Asia/Shanghai")!
var cal = Calendar(identifier: .gregorian)
cal.locale = Locale(identifier: "en_US_POSIX")
cal.timeZone = tz
let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 9, minute: 0))!

func ymd(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}
let parser = InputParser(now: now, calendar: cal)
func parse(_ s: String) -> ParsedItem { parser.parse(s) }

let h = Harness(timeZone: tz)

h.group("Basics")
do {
    let p = parse("买牛奶")
    h.eq(p.title, "买牛奶", "title")
    h.eq(p.kind, .reminder, "kind")
    h.ok(p.startDate == nil, "no date")
    h.eq(p.priority, .none, "priority")
}
h.eq(parse("买牛奶 !!!").priority, .high, "!!! -> high")
h.eq(parse("买牛奶 !!").priority, .medium, "!! -> medium")
h.eq(parse("买牛奶 !").priority, .low, "! -> low")
h.eq(parse("买牛奶 !!!").title, "买牛奶", "priority stripped from title")
do {
    let p = parse("submit report p1")
    h.eq(p.priority, .high, "p1 -> high")
    h.eq(p.title, "submit report", "p1 title")
}
do {
    let p = parse("Wow great job!")
    h.eq(p.priority, .none, "trailing ! not priority")
    h.eq(p.title, "Wow great job!", "title keeps !")
}
h.eq(parse("紧急 修复线上bug").priority, .high, "紧急 -> high")
h.eq(parse("urgent fix login page").priority, .high, "urgent -> high")
h.eq(parse("至急 対応する").priority, .high, "至急 -> high (JA)")
do {
    let p = parse("重要会议 明天下午3点")
    h.eq(p.priority, .high, "重要 -> high (kept in title)")
    h.eq(p.title, "重要会议", "keyword stays in title")
}
h.eq(parse("买牛奶").priority, .none, "no keyword -> none")

h.group("Reminder with time")
do {
    // "开会" is a meeting keyword → now classified as an event (default 1h).
    let p = parse("明天下午3点 开会")
    h.eq(p.kind, .event, "meeting keyword -> event")
    h.ok(p.hasTime, "hasTime")
    h.eq(p.startDate, ymd(2026, 6, 6, 15, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 6, 16, 0), "default +1h")
    h.eq(p.title, "开会", "title")
}
do {
    let p = parse("晚上8点半 跑步")
    h.eq(p.startDate, ymd(2026, 6, 5, 20, 30), "8点半 evening")
    h.eq(p.title, "跑步", "title")
}
do {
    let p = parse("中午 吃饭")
    h.eq(p.startDate, ymd(2026, 6, 5, 12, 0), "中午 -> noon")
    h.eq(p.title, "吃饭", "title")
}
do {
    let p = parse("8am 晨跑")
    h.eq(p.startDate, ymd(2026, 6, 6, 8, 0), "past time rolls to tomorrow")
    h.eq(p.title, "晨跑", "title")
}
do {
    let p = parse("3pm coffee")
    h.eq(p.startDate, ymd(2026, 6, 5, 15, 0), "future time today")
    h.eq(p.title, "coffee", "title")
}
do {
    let p = parse("15:30 review")
    h.eq(p.startDate, ymd(2026, 6, 5, 15, 30), "24h colon")
    h.eq(p.title, "review", "title")
}

h.group("Events (duration or range)")
do {
    let p = parse("明天下午3点 开会 30min")
    h.eq(p.kind, .event, "duration -> event")
    h.eq(p.startDate, ymd(2026, 6, 6, 15, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 6, 15, 30), "end +30m")
    h.eq(p.title, "开会", "title")
}
do {
    let p = parse("明天 9am 健身 1.5h")
    h.eq(p.kind, .event, "1.5h -> event")
    h.eq(p.startDate, ymd(2026, 6, 6, 9, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 6, 10, 30), "end +1.5h")
}
do {
    let p = parse("周五 9am-10am 团队会议")
    h.eq(p.kind, .event, "range -> event")
    h.eq(p.startDate, ymd(2026, 6, 5, 9, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 5, 10, 0), "end")
    h.eq(p.title, "团队会议", "title")
}
do {
    let p = parse("3-4pm meeting")
    h.eq(p.startDate, ymd(2026, 6, 5, 15, 0), "range inherits pm (start)")
    h.eq(p.endDate, ymd(2026, 6, 5, 16, 0), "range inherits pm (end)")
    h.eq(p.kind, .event, "event")
}
do {
    let p = parse("下午3点到4点半 复盘")
    h.eq(p.kind, .event, "cn range -> event")
    h.eq(p.startDate, ymd(2026, 6, 5, 15, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 5, 16, 30), "end 4点半")
    h.eq(p.title, "复盘", "title")
}
do {
    let p = parse("晚上11点到凌晨1点 值班")
    h.eq(p.startDate, ymd(2026, 6, 5, 23, 0), "overnight start")
    h.eq(p.endDate, ymd(2026, 6, 6, 1, 0), "overnight end next day")
    h.eq(p.kind, .event, "event")
}
do {
    let p = parse("tomorrow 9am standup half an hour")
    h.eq(p.startDate, ymd(2026, 6, 6, 9, 0), "start")
    h.eq(p.endDate, ymd(2026, 6, 6, 9, 30), "half an hour")
    h.eq(p.kind, .event, "event")
}

h.group("Relative time")
do {
    let p = parse("30分钟后 提醒喝水")
    h.eq(p.startDate, ymd(2026, 6, 5, 9, 30), "now + 30m")
    h.ok(p.hasTime, "hasTime")
}
do {
    let p = parse("in 2 hours call mom")
    h.eq(p.startDate, ymd(2026, 6, 5, 11, 0), "now + 2h")
    h.eq(p.title, "call mom", "title")
}

h.group("Dates")
do {
    let p = parse("3月5日 交报告")
    h.eq(p.startDate, ymd(2027, 3, 5, 0, 0), "past date rolls to next year")
    h.ok(p.isAllDay, "all day")
    h.eq(p.title, "交报告", "title")
}
do {
    let p = parse("2026-12-31 年终总结")
    h.eq(p.startDate, ymd(2026, 12, 31, 0, 0), "ISO date")
    h.ok(p.isAllDay, "all day")
}
do {
    let p = parse("周一 牙医")
    h.eq(p.startDate, ymd(2026, 6, 8, 0, 0), "this-week Monday")
    h.eq(p.title, "牙医", "title")
}
h.eq(parse("下周一 体检").startDate, ymd(2026, 6, 15, 0, 0), "next Monday")
h.eq(parse("in 2 weeks 体检").startDate, ymd(2026, 6, 19, 0, 0), "in 2 weeks")
h.eq(parse("两周后 交报告").startDate, ymd(2026, 6, 19, 0, 0), "两周后 (zh)")
h.eq(parse("3个月后 复查").startDate, ymd(2026, 9, 5, 0, 0), "3个月后 (zh)")
h.eq(parse("2週間後 健康診断").startDate, ymd(2026, 6, 19, 0, 0), "2週間後 (ja)")
h.eq(parse("in 3 months review").startDate, ymd(2026, 9, 5, 0, 0), "in 3 months")
do {
    let p = parse("Jan 5 dentist")
    h.eq(p.startDate, ymd(2027, 1, 5, 0, 0), "English month date rolls forward")
    h.eq(p.title, "dentist", "title")
}
do {
    let p = parse("周末 大扫除")
    h.eq(p.startDate, ymd(2026, 6, 6, 0, 0), "weekend -> upcoming Saturday")
    h.eq(p.title, "大扫除", "title")
}
h.eq(parse("月底 交房租").startDate, ymd(2026, 6, 30, 0, 0), "month end -> last day")
h.eq(parse("交报告 by end of month").startDate, ymd(2026, 6, 30, 0, 0), "end of month (EN)")

h.group("Lists, tags, notes, URLs")
do {
    let p = parse("买菜 ~Groceries #home #errand")
    h.eq(p.listName, "Groceries", "list")
    h.eq(Set(p.tags), Set(["home", "errand"]), "tags")
    h.eq(p.title, "买菜", "title")
}
do {
    let p = parse("写周报 // 包括本周进展和下周计划")
    h.eq(p.title, "写周报", "title before //")
    h.eq(p.notes, "包括本周进展和下周计划", "notes after //")
}
do {
    let p = parse("看文章 https://example.com 明天")
    h.eq(p.url?.absoluteString, "https://example.com", "url")
    h.eq(p.startDate, ymd(2026, 6, 6, 0, 0), "tomorrow")
    h.eq(p.title, "看文章", "title")
}

h.group("Recurrence")
do {
    let p = parse("每天 喝水 !!")
    h.eq(p.recurrence?.frequency, .daily, "daily")
    h.eq(p.priority, .medium, "priority")
    h.eq(p.title, "喝水", "title")
    h.eq(p.startDate, ymd(2026, 6, 5, 0, 0), "anchored today")
    h.ok(p.isAllDay, "all day")
}
do {
    let p = parse("每周一 上午10点 团队会")
    h.eq(p.recurrence?.frequency, .weekly, "weekly")
    h.eq(p.recurrence?.weekdays ?? [], [2], "on Monday")
    h.ok(p.hasTime, "hasTime")
    h.eq(p.title, "团队会", "title")
}
do {
    let p = parse("every 3 days 浇花")
    h.eq(p.recurrence?.frequency, .daily, "every N days")
    h.eq(p.recurrence?.interval, 3, "interval 3")
}
do {
    let p = parse("每天 吃药 共7次")
    h.eq(p.recurrence?.frequency, .daily, "daily")
    h.eq(p.recurrence?.occurrenceCount, 7, "共7次 -> count 7")
    h.eq(p.title, "吃药", "count stripped from title")
}
h.eq(parse("毎日 散歩 5回").recurrence?.occurrenceCount, 5, "5回 -> count 5 (JA)")
h.eq(parse("daily standup 10 times").recurrence?.occurrenceCount, 10, "10 times -> count 10")
h.ok(parse("每天 喝水").recurrence?.occurrenceCount == nil, "no count -> nil")
do {
    let p = parse("每天 喝水 持续两周")
    h.eq(p.recurrence?.frequency, .daily, "daily")
    h.eq(p.recurrence?.endDate, ymd(2026, 6, 19, 0, 0), "持续两周 -> end +14d")
}
h.eq(parse("daily standup for 2 weeks").recurrence?.endDate, ymd(2026, 6, 19, 0, 0), "for 2 weeks -> end")
h.eq(parse("毎日 散歩 2週間").recurrence?.endDate, ymd(2026, 6, 19, 0, 0), "2週間 -> end (JA)")
h.eq(parse("every day for 3 months").recurrence?.endDate, ymd(2026, 9, 5, 0, 0), "for 3 months -> end")
h.eq(parse("每天 锻炼 到周三").recurrence?.endDate, ymd(2026, 6, 10, 0, 0), "到周三 -> end Wed")
h.eq(parse("daily standup until wednesday").recurrence?.endDate, ymd(2026, 6, 10, 0, 0), "until wednesday")
h.eq(parse("毎日 散歩 水曜まで").recurrence?.endDate, ymd(2026, 6, 10, 0, 0), "水曜まで (ja)")

h.group("Title cleanup & highlights")
do {
    let p = parse("lunch, 12pm")
    h.eq(p.title, "lunch", "trailing comma trimmed")
    h.eq(p.startDate, ymd(2026, 6, 5, 12, 0), "12pm")
}
do {
    let p = parse("明天下午3点 开会 !!!")
    h.ok(p.highlights.contains { $0.kind == .date }, "date highlight")
    h.ok(p.highlights.contains { $0.kind == .time }, "time highlight")
    h.ok(p.highlights.contains { $0.kind == .priority }, "priority highlight")
}

h.group("Location & meeting detection")
do {
    // The user's real example: date + time + multi-line address -> calendar event with location.
    let p = parse("6/8 15:30 東京都中央区晴海1-8-10\nトリトンスクエア オフィスタワーX棟 7階")
    h.eq(p.kind, .event, "time + address -> event")
    h.eq(p.startDate, ymd(2026, 6, 8, 15, 30), "start 6/8 15:30")
    h.eq(p.endDate, ymd(2026, 6, 8, 16, 30), "default +1h")
    h.ok(p.location?.contains("東京都中央区晴海1-8-10") ?? false, "location has address")
    h.ok(p.location?.contains("トリトンスクエア") ?? false, "location has venue")
    h.ok(p.location?.contains("7階") ?? false, "location has floor")
    h.eq(p.title, "トリトンスクエア", "title falls back to venue name")
}
do {
    let p = parse("明天下午3点 和张总在星巴克见面")
    h.eq(p.kind, .event, "见面 keyword -> event")
    h.ok(p.hasTime, "hasTime")
    h.eq(p.title, "和张总在星巴克见面", "title kept")
}
do {
    // Connected CJK "go to the meeting room" — classify as event but keep phrase as title.
    let p = parse("明天3点 去三楼会议室开会")
    h.eq(p.kind, .event, "meeting room + 开会 -> event")
    h.ok(p.location == nil, "no separate location extracted")
    h.eq(p.title, "去三楼会议室开会", "phrase kept as title")
}
do {
    let p = parse("英语会议室 Floor 12 tomorrow 2pm")
    h.eq(p.kind, .event, "Floor/Room cue -> event")
    h.ok(p.location?.lowercased().contains("floor 12") ?? false, "english location")
}
do {
    // Regression: a plain dated to-do is still a reminder.
    let p = parse("买牛奶 明天")
    h.eq(p.kind, .reminder, "no time, no place -> reminder")
    h.ok(p.location == nil, "no location")
}

h.group("Japanese")
do {
    let p = parse("月曜 歯医者")
    h.eq(p.startDate, ymd(2026, 6, 8, 0, 0), "月曜 -> next Monday")
    h.eq(p.title, "歯医者", "title")
}
do {
    let p = parse("午後3時 会議 30分")
    h.eq(p.kind, .event, "午後 + 会議 + 30分 -> event")
    h.eq(p.startDate, ymd(2026, 6, 5, 15, 0), "午後3時 = 15:00")
    h.eq(p.endDate, ymd(2026, 6, 5, 15, 30), "30分 duration")
    h.eq(p.title, "会議", "title")
}
h.eq(parse("明後日 レポート提出").startDate, ymd(2026, 6, 7, 0, 0), "明後日 -> +2 days")
h.eq(parse("来週 出張").startDate, ymd(2026, 6, 15, 0, 0), "来週 -> next Monday")
do {
    let p = parse("毎週月曜 午前10時 定例")
    h.eq(p.recurrence?.frequency, .weekly, "毎週 weekly")
    h.eq(p.recurrence?.weekdays ?? [], [2], "on Monday")
    h.eq(p.startDate.map { cal.dateComponents([.hour, .minute], from: $0) }, DateComponents(hour: 10, minute: 0), "午前10時")
    h.eq(p.title, "定例", "title")
}
do {
    let p = parse("毎日 水を飲む")
    h.eq(p.recurrence?.frequency, .daily, "毎日 daily")
    h.eq(p.title, "水を飲む", "title")
}
do {
    let p = parse("明日 9時 作業 1時間半")
    h.eq(p.kind, .event, "1時間半 -> event")
    h.eq(p.startDate, ymd(2026, 6, 6, 9, 0), "明日 9時")
    h.eq(p.endDate, ymd(2026, 6, 6, 10, 30), "+90 min")
}
h.eq(parse("夜8時 ジョギング").startDate, ymd(2026, 6, 5, 20, 0), "夜8時 = 20:00")

h.group("Lead-time alarms")
do {
    let p = parse("明天9点 开会 提前30分钟")
    h.eq(p.leadTimeSeconds, 1800, "提前30分钟 -> 1800s")
    h.eq(p.kind, .event, "still an event (开会)")
    h.eq(p.startDate, ymd(2026, 6, 6, 9, 0), "start unaffected by lead time")
    h.eq(p.title, "开会", "lead phrase stripped from title")
}
h.eq(parse("买牛奶 明天 提前1天").leadTimeSeconds, 86400, "提前1天 -> 1 day")
h.eq(parse("歯医者 明日 1日前").leadTimeSeconds, 86400, "1日前 -> 1 day (JA)")
do {
    let p = parse("review tomorrow 3pm remind 15 min before")
    h.eq(p.leadTimeSeconds, 900, "remind 15 min before -> 900s")
    h.eq(p.startDate, ymd(2026, 6, 6, 15, 0), "start 3pm")
}
h.ok(parse("提前完成任务").leadTimeSeconds == nil, "提前完成 is not a lead time")
do {
    let p = parse("全天 明天 团建")
    h.ok(p.isAllDay, "全天 -> all day")
    h.ok(!p.hasTime, "no time of day")
    h.eq(p.startDate, ymd(2026, 6, 6, 0, 0), "tomorrow, start of day")
    h.eq(p.title, "团建", "title")
}
h.ok(parse("all day tomorrow project freeze").isAllDay, "all day (EN)")

h.group("Vague time defaults")
do {
    let p = parse("明天下午 开会")
    h.eq(p.kind, .event, "afternoon + 开会 -> event")
    h.eq(p.startDate, ymd(2026, 6, 6, 14, 0), "下午 -> 14:00")
    h.eq(p.title, "开会", "title")
}
do {
    let p = parse("今晚 看电影")
    h.eq(p.startDate, ymd(2026, 6, 5, 19, 0), "今晚 -> 19:00 today")
    h.eq(p.title, "看电影", "title")
}
h.eq(parse("明天早上 跑步").startDate, ymd(2026, 6, 6, 9, 0), "早上 -> 09:00")
h.eq(parse("下午 提交报告").startDate, ymd(2026, 6, 5, 14, 0), "下午 -> 14:00 today")
do {
    let p = parse("tonight call dad")
    h.eq(p.startDate, ymd(2026, 6, 5, 19, 0), "tonight -> 19:00")
    h.eq(p.title, "call dad", "title")
}
do {
    let p = parse("明日 午後 ミーティング")
    h.eq(p.kind, .event, "午後 + ミーティング -> event")
    h.eq(p.startDate, ymd(2026, 6, 6, 14, 0), "午後 -> 14:00")
}

h.group("Search query")
do {
    let q = SearchQueryParser.parse("团队 is:event due:week ~Work #urgent !!")
    h.eq(q.text, "团队", "free text")
    h.eq(q.kind, .event, "is:event")
    h.eq(q.due, .thisWeek, "due:week")
    h.eq(q.listName, "Work", "~Work")
    h.eq(q.tags, ["urgent"], "#urgent")
    h.eq(q.priority, .medium, "!! priority")
}
do {
    let q = SearchQueryParser.parse("buy milk is:done priority:high")
    h.eq(q.text, "buy milk", "free text words")
    h.eq(q.completion, .done, "is:done")
    h.eq(q.priority, .high, "priority:high")
}
do {
    let q = SearchQueryParser.parse("plain search")
    h.ok(q.kind == nil && q.due == nil, "no filters")
    h.ok(q.matchesText(title: "a Plain Search result", notes: nil), "case-insensitive match")
    h.ok(!q.matchesText(title: "unrelated", notes: nil), "no match")
}

h.group("Performance")
do {
    let samples = [
        "明天下午3点 开会 30min",
        "6/8 15:30 東京都中央区晴海1-8-10 トリトンスクエア オフィスタワーX棟 7階",
        "买菜 ~Groceries #home #errand !! 明天",
        "every monday 10am team standup review",
        "30分钟后 提醒喝水 // 多喝热水"
    ]
    let p = InputParser(now: now, calendar: cal)
    let iterations = 3000
    var sink = 0
    let t0 = Date()
    for _ in 0..<iterations {
        for s in samples { sink += p.parse(s).title.count }
    }
    let elapsed = Date().timeIntervalSince(t0)
    let total = Double(iterations * samples.count)
    let perSec = total / elapsed
    let usEach = elapsed / total * 1_000_000
    h.ok(sink > 0, String(format: "parsed %.0f lines in %.2fs", total, elapsed))
    print(String(format: "    throughput: %.0f parses/sec  (%.1f µs each)", perSec, usEach))
    // Regression guard — live preview runs this per keystroke. The pre-optimization
    // baseline (recompiling regexes each parse) was ~2000/s; 4000 catches that regression
    // while leaving headroom for slower / debug CI machines.
    h.ok(perSec > 4000, String(format: "throughput healthy (got %.0f/s)", perSec))
}

exit(Int32(h.summarize()))
