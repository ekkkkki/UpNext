import Foundation

/// Resolved date/time information extracted from a quick-add line.
struct DateTimeInterpretation: Equatable {
    var startDate: Date?
    var endDate: Date?
    var hasTime: Bool = false
    var isAllDay: Bool = false
    var isEvent: Bool = false
    var consumed: [ConsumedRange] = []
}

struct ConsumedRange: Equatable {
    var range: NSRange
    var kind: Highlight.Kind
}

private struct Clock: Equatable {
    var hour: Int
    var minute: Int
}

/// Tracks which spans of the input have already been claimed by a sub-parser so later
/// passes don't double-consume (e.g. the day pass must not match inside a time span).
private final class Scanner {
    let text: String
    let ns: NSString
    private(set) var consumed: [NSRange] = []

    init(_ text: String) {
        self.text = text
        self.ns = text as NSString
    }

    var fullRange: NSRange { NSRange(location: 0, length: ns.length) }

    func isFree(_ r: NSRange) -> Bool {
        !consumed.contains { NSIntersectionRange($0, r).length > 0 }
    }

    func consume(_ r: NSRange) { if r.location != NSNotFound { consumed.append(r) } }

    /// First regex match that doesn't overlap an already-consumed span.
    func firstFree(_ re: NSRegularExpression) -> NSTextCheckingResult? {
        re.matches(in: text, range: fullRange).first { isFree($0.range) }
    }
}

enum DateTimeParser {

    // MARK: Public entry

    static func parse(_ input: String, now: Date, calendar: Calendar) -> DateTimeInterpretation {
        var cal = calendar
        cal.locale = calendar.locale ?? Locale(identifier: "en_US")
        let scanner = Scanner(input)
        var result = DateTimeInterpretation()

        // 1) Day context (also yields an evening hint for period-less times like "今晚8点").
        let day = findDay(scanner, now: now, cal: cal)

        // 2) Explicit time range -> calendar event.
        if let range = findTimeRange(scanner, eveningHint: day?.eveningHint ?? false) {
            let baseDay = day?.date ?? cal.startOfDay(for: now)
            var start = combine(day: baseDay, clock: range.start, cal: cal)
            var end = combine(day: baseDay, clock: range.end, cal: cal)
            if end <= start { end = cal.date(byAdding: .day, value: 1, to: end) ?? end } // overnight
            // If no explicit day and the whole event is already in the past, roll to tomorrow.
            if day == nil, end < now {
                start = cal.date(byAdding: .day, value: 1, to: start) ?? start
                end = cal.date(byAdding: .day, value: 1, to: end) ?? end
            }
            result.startDate = start
            result.endDate = end
            result.isEvent = true
            result.hasTime = true
            result.consumed.append(ConsumedRange(range: range.range, kind: .time))
            if let d = day { result.consumed.append(ConsumedRange(range: d.range, kind: .date)) }
            return result
        }

        // 3) Relative time ("in 30 min" / "30分钟后") -> a single absolute instant.
        if let rel = findRelativeTime(scanner, now: now) {
            result.startDate = rel.date
            result.hasTime = true
            result.consumed.append(ConsumedRange(range: rel.range, kind: .time))
            // A duration could still turn it into an event.
            if let dur = findDuration(scanner) {
                result.endDate = rel.date.addingTimeInterval(dur.seconds)
                result.isEvent = true
                result.consumed.append(ConsumedRange(range: dur.range, kind: .duration))
            }
            return result
        }

        // 4) Single time, optionally followed by a duration -> reminder or event.
        //    Fall back to a vague period word ("下午" / "tonight" / "朝") → a default clock.
        let time = findTime(scanner, eveningHint: day?.eveningHint ?? false)
            ?? findBareTimeWord(scanner, eveningHint: day?.eveningHint ?? false)
        if let time = time {
            let baseDay = day?.date ?? cal.startOfDay(for: now)
            var start = combine(day: baseDay, clock: time.clock, cal: cal)
            // Bare time with no day, already past today -> roll to tomorrow.
            if day == nil, start < now {
                start = cal.date(byAdding: .day, value: 1, to: start) ?? start
            }
            result.startDate = start
            result.hasTime = true
            result.consumed.append(ConsumedRange(range: time.range, kind: .time))

            if let dur = findDuration(scanner) {
                result.endDate = start.addingTimeInterval(dur.seconds)
                result.isEvent = true
                result.consumed.append(ConsumedRange(range: dur.range, kind: .duration))
            }
            if let d = day { result.consumed.append(ConsumedRange(range: d.range, kind: .date)) }
            return result
        }

        // 5) Day only -> all-day reminder.
        if let day = day {
            result.startDate = day.date
            result.isAllDay = true
            result.hasTime = false
            result.consumed.append(ConsumedRange(range: day.range, kind: .date))
            // A day range ("周一到周三") becomes an all-day event spanning the days.
            if let endDay = day.endDate {
                result.endDate = endDay
                result.isEvent = true
            }
            return result
        }

        return result
    }

    // MARK: Combine helpers

    private static func combine(day: Date, clock: Clock, cal: Calendar) -> Date {
        let start = cal.startOfDay(for: day)
        return cal.date(byAdding: DateComponents(hour: clock.hour, minute: clock.minute), to: start) ?? start
    }

    // MARK: Regex cache

    // Compiled-regex cache. The patterns here are constants, but they were previously
    // recompiled on every parse() (the hot path for live preview). Memoizing them, plus
    // skipping URL detection when impossible, takes throughput from ~2k to ~9k parses/sec.
    private static var regexCache: [String: NSRegularExpression] = [:]
    private static let regexCacheLock = NSLock()

    private static func re(_ pattern: String, _ opts: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        let key = "\(opts.rawValue)\u{1}\(pattern)"
        regexCacheLock.lock()
        defer { regexCacheLock.unlock() }
        if let cached = regexCache[key] { return cached }
        let regex = try! NSRegularExpression(pattern: pattern, options: opts)
        regexCache[key] = regex
        return regex
    }

    private static let cnNum = "[0-9零〇一二两三四五六七八九十]"

    private static func number(_ s: String?) -> Int? {
        guard let s = s, !s.isEmpty else { return nil }
        if let n = Int(s) { return n }
        return ChineseNumber.parse(s)
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, in ns: NSString) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        guard r.location != NSNotFound else { return nil }
        return ns.substring(with: r)
    }

    // MARK: Day parsing

    private struct DayMatch {
        var date: Date
        var endDate: Date?       // for day ranges
        var range: NSRange
        var eveningHint: Bool
    }

    private static let weekdayMap: [String: Int] = [
        // Calendar weekday numbers: Sun=1 ... Sat=7
        "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "weds": 4, "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6, "saturday": 7, "sat": 7, "sunday": 1, "sun": 1,
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1
    ]

    private static func nextWeekday(_ target: Int, from now: Date, cal: Calendar, includingToday: Bool) -> Date {
        let cur = cal.component(.weekday, from: now)
        var delta = (target - cur + 7) % 7
        if delta == 0 && !includingToday { delta = 7 }
        return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: now)) ?? now
    }

    private static func findDay(_ scanner: Scanner, now: Date, cal: Calendar) -> DayMatch? {
        let ns = scanner.ns
        let today = cal.startOfDay(for: now)

        // --- Day ranges first: "周一到周三", "Mon-Wed", "3月5日到3月7日" ---
        if let dr = findDayRange(scanner, now: now, cal: cal) { return dr }

        // --- Relative day words (longest / most specific first) ---
        let evening = re("(今晚|今天晚上|明晚|明天晚上|tonight|tomorrow night)")
        if let m = scanner.firstFree(evening) {
            let token = ns.substring(with: m.range).lowercased()
            let isTomorrow = token.contains("明") || token.contains("tomorrow")
            let date = cal.date(byAdding: .day, value: isTomorrow ? 1 : 0, to: today) ?? today
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: true)
        }

        // "the day after tomorrow" / 大后天 / 后天
        let plus = re("(大后天|the day after tomorrow)")
        if let m = scanner.firstFree(plus) {
            scanner.consume(m.range)
            return DayMatch(date: cal.date(byAdding: .day, value: 3, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
        }
        let dayAfter = re("(后天|明後日|あさって)")
        if let m = scanner.firstFree(dayAfter) {
            scanner.consume(m.range)
            return DayMatch(date: cal.date(byAdding: .day, value: 2, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
        }
        let tomorrow = re("(明天|明日|tomorrow|tmr|tmrw)")
        if let m = scanner.firstFree(tomorrow) {
            scanner.consume(m.range)
            return DayMatch(date: cal.date(byAdding: .day, value: 1, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
        }
        let todayWord = re("(今天|今日|today)")
        if let m = scanner.firstFree(todayWord) {
            scanner.consume(m.range)
            return DayMatch(date: today, endDate: nil, range: m.range, eveningHint: false)
        }

        // "in N days" / "N天后" / "N days later"
        let inDaysEN = re("\\bin\\s+(\\d+)\\s+days?\\b")
        if let m = scanner.firstFree(inDaysEN), let n = number(group(m, 1, in: ns)) {
            scanner.consume(m.range)
            return DayMatch(date: cal.date(byAdding: .day, value: n, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
        }
        let inDaysCN = re("(\(cnNum)+)\\s*天\\s*(后|之后)")
        if let m = scanner.firstFree(inDaysCN), let n = number(group(m, 1, in: ns)) {
            scanner.consume(m.range)
            return DayMatch(date: cal.date(byAdding: .day, value: n, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
        }

        // "in N weeks" / "N周后" / "N週間後"
        let inWeeks = re("\\bin\\s+(\\d+)\\s+weeks?\\b|(\(cnNum)+)\\s*(?:周|星期|週間|週)\\s*(?:后|之后|後)")
        if let m = scanner.firstFree(inWeeks) {
            let n = number(group(m, 1, in: ns)) ?? number(group(m, 2, in: ns))
            if let n = n {
                scanner.consume(m.range)
                return DayMatch(date: cal.date(byAdding: .day, value: n * 7, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
            }
        }

        // "in N months" / "N个月后" / "Nヶ月後"
        let inMonths = re("\\bin\\s+(\\d+)\\s+months?\\b|(\(cnNum)+)\\s*(?:个月|個月|ヶ月|か月|月)\\s*(?:后|之后|後)")
        if let m = scanner.firstFree(inMonths) {
            let n = number(group(m, 1, in: ns)) ?? number(group(m, 2, in: ns))
            if let n = n {
                scanner.consume(m.range)
                return DayMatch(date: cal.date(byAdding: .month, value: n, to: today) ?? today, endDate: nil, range: m.range, eveningHint: false)
            }
        }

        // Weekday with optional this/next prefix.
        let prefixedWeekday = re("(this|next|本|这|这个|下|下个)?\\s*(周|星期|礼拜)\\s*([一二三四五六日天])")
        if let m = scanner.firstFree(prefixedWeekday),
           let wd = group(m, 3, in: ns).flatMap({ weekdayMap[$0] }) {
            let prefix = group(m, 1, in: ns)?.lowercased() ?? ""
            let isNext = prefix.contains("next") || prefix.contains("下")
            var date = nextWeekday(wd, from: now, cal: cal, includingToday: true)
            if isNext { date = cal.date(byAdding: .day, value: 7, to: date) ?? date }
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }
        // English weekdays with optional this/next.
        let enWeekday = re("\\b(this|next)?\\s*(monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat|sunday|sun)\\b")
        if let m = scanner.firstFree(enWeekday),
           let name = group(m, 2, in: ns)?.lowercased(), let wd = weekdayMap[name] {
            let prefix = group(m, 1, in: ns)?.lowercased() ?? ""
            let isNext = prefix.contains("next")
            var date = nextWeekday(wd, from: now, cal: cal, includingToday: true)
            if isNext { date = cal.date(byAdding: .day, value: 7, to: date) ?? date }
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }

        // Japanese weekdays: 月曜(日)…日曜(日), with optional 今週 / 来週.
        let jaWeekday = re("(今週|来週|next|this)?\\s*([月火水木金土日])曜日?")
        if let m = scanner.firstFree(jaWeekday), let ch = group(m, 2, in: ns)?.first,
           let wd = ["月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7, "日": 1][ch] {
            let prefix = group(m, 1, in: ns)?.lowercased() ?? ""
            let isNext = prefix.contains("来") || prefix.contains("next")
            var date = nextWeekday(wd, from: now, cal: cal, includingToday: true)
            if isNext { date = cal.date(byAdding: .day, value: 7, to: date) ?? date }
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }

        // Weekend → the upcoming Saturday ("下周末"/"next weekend" → the one after).
        let weekend = re("(下个?|next)?\\s*(周末|週末|weekend)")
        if let m = scanner.firstFree(weekend) {
            let prefix = group(m, 1, in: ns)?.lowercased() ?? ""
            let isNext = prefix.contains("next") || prefix.contains("下")
            var date = nextWeekday(7, from: now, cal: cal, includingToday: true)
            if isNext { date = cal.date(byAdding: .day, value: 7, to: date) ?? date }
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }

        // End of month → last calendar day of the current month.
        let monthEnd = re("(月底|月末|end\\s+of\\s+(?:the\\s+)?month)")
        if let m = scanner.firstFree(monthEnd) {
            let comps = cal.dateComponents([.year, .month], from: now)
            if let startOfMonth = cal.date(from: comps),
               let nextMonth = cal.date(byAdding: .month, value: 1, to: startOfMonth),
               let lastDay = cal.date(byAdding: .day, value: -1, to: nextMonth) {
                scanner.consume(m.range)
                return DayMatch(date: lastDay, endDate: nil, range: m.range, eveningHint: false)
            }
        }

        // Absolute Chinese date: (YYYY年)?M月D日/号
        let cnDate = re("(?:(\\d{4})\\s*年)?\\s*(\(cnNum){1,2})\\s*月\\s*(\(cnNum){1,3})\\s*[日号]")
        if let m = scanner.firstFree(cnDate),
           let month = number(group(m, 2, in: ns)), let dayN = number(group(m, 3, in: ns)) {
            let year = number(group(m, 1, in: ns))
            if let date = makeDate(year: year, month: month, day: dayN, now: now, cal: cal) {
                scanner.consume(m.range)
                return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
            }
        }
        // "M月" alone -> not specific enough; skip.

        // Numeric ISO / slashed dates: YYYY-MM-DD, YYYY/MM/DD, M/D, M-D
        let iso = re("\\b(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})\\b")
        if let m = scanner.firstFree(iso),
           let y = number(group(m, 1, in: ns)), let mo = number(group(m, 2, in: ns)), let d = number(group(m, 3, in: ns)),
           let date = makeDate(year: y, month: mo, day: d, now: now, cal: cal) {
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }
        let mdSlash = re("\\b(\\d{1,2})/(\\d{1,2})\\b")
        if let m = scanner.firstFree(mdSlash),
           let mo = number(group(m, 1, in: ns)), let d = number(group(m, 2, in: ns)),
           (1...12).contains(mo), (1...31).contains(d),
           let date = makeDate(year: nil, month: mo, day: d, now: now, cal: cal) {
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }

        // English month-name dates: "Jan 5", "January 5th", "5 Jan", "March 5, 2026"
        if let m = findEnglishMonthDate(scanner, now: now, cal: cal) {
            return m
        }

        // "下周"/"下个月" without a weekday.
        let nextWeek = re("(下周|下星期|下个星期|next week|来週)")
        if let m = scanner.firstFree(nextWeek) {
            scanner.consume(m.range)
            // Next Monday.
            let base = nextWeekday(2, from: now, cal: cal, includingToday: true)
            let date = cal.date(byAdding: .day, value: 7, to: base) ?? base
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }
        let nextMonth = re("(下个月|下月|next month|来月)")
        if let m = scanner.firstFree(nextMonth) {
            scanner.consume(m.range)
            let date = cal.date(byAdding: .month, value: 1, to: today) ?? today
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }

        return nil
    }

    private static let monthNames: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12
    ]

    private static let monthAlt = monthNames.keys.sorted { $0.count > $1.count }.joined(separator: "|")

    private static func findEnglishMonthDate(_ scanner: Scanner, now: Date, cal: Calendar) -> DayMatch? {
        let ns = scanner.ns
        let monthAlt = Self.monthAlt
        // "Month D(st|nd|rd|th)?(, YYYY)?"
        let p1 = re("\\b(\(monthAlt))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?\\b")
        if let m = scanner.firstFree(p1),
           let mn = group(m, 1, in: ns)?.lowercased(), let mo = monthNames[mn],
           let d = number(group(m, 2, in: ns)) {
            let y = number(group(m, 3, in: ns))
            if let date = makeDate(year: y, month: mo, day: d, now: now, cal: cal) {
                scanner.consume(m.range)
                return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
            }
        }
        // "D(st|nd|rd|th)? Month"
        let p2 = re("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthAlt))\\b")
        if let m = scanner.firstFree(p2),
           let d = number(group(m, 1, in: ns)),
           let mn = group(m, 2, in: ns)?.lowercased(), let mo = monthNames[mn],
           let date = makeDate(year: nil, month: mo, day: d, now: now, cal: cal) {
            scanner.consume(m.range)
            return DayMatch(date: date, endDate: nil, range: m.range, eveningHint: false)
        }
        return nil
    }

    /// Build a date, rolling forward to next year when no year was given and the day already passed.
    private static func makeDate(year: Int?, month: Int, day: Int, now: Date, cal: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.year = year ?? cal.component(.year, from: now)
        comps.month = month
        comps.day = day
        guard let date = cal.date(from: comps) else { return nil }
        if year == nil, date < cal.startOfDay(for: now) {
            comps.year = (comps.year ?? 0) + 1
            return cal.date(from: comps)
        }
        return date
    }

    // MARK: Day range

    private static func findDayRange(_ scanner: Scanner, now: Date, cal: Calendar) -> DayMatch? {
        let ns = scanner.ns
        // Weekday to weekday: 周一到周三 / Mon-Wed
        let cnWdRange = re("(周|星期|礼拜)\\s*([一二三四五六日天])\\s*(?:到|至|-|~)\\s*(?:周|星期|礼拜)?\\s*([一二三四五六日天])")
        if let m = scanner.firstFree(cnWdRange),
           let w1 = group(m, 2, in: ns).flatMap({ weekdayMap[$0] }),
           let w2 = group(m, 3, in: ns).flatMap({ weekdayMap[$0] }) {
            let start = nextWeekday(w1, from: now, cal: cal, includingToday: true)
            var end = nextWeekday(w2, from: now, cal: cal, includingToday: true)
            if end < start { end = cal.date(byAdding: .day, value: 7, to: end) ?? end }
            scanner.consume(m.range)
            return DayMatch(date: start, endDate: cal.date(byAdding: .day, value: 1, to: end), range: m.range, eveningHint: false)
        }
        return nil
    }

    // MARK: Time parsing

    private struct TimeMatch { var clock: Clock; var range: NSRange }

    private static func adjust(hour: Int, period: String?, cal: Calendar) -> Int {
        guard let p = period?.lowercased(), !p.isEmpty else { return hour }
        if p.contains("下午") || p.contains("午後") || p.contains("夕方") || p == "pm" || p == "p.m." || p == "p" {
            return hour < 12 ? hour + 12 : hour
        }
        if p.contains("深夜") {                    // 深夜2時 == 02:00, 深夜12時 == 00:00
            return hour == 12 ? 0 : hour
        }
        if p.contains("晚") || p.contains("傍晚") || p.contains("夜") {
            if hour == 12 { return 0 }            // 晚上12点 / 夜12時 == midnight
            return hour < 12 ? hour + 12 : hour
        }
        if p.contains("中午") || p.contains("正午") || p.contains("昼") {
            return hour < 7 ? hour + 12 : hour     // 中午1点 == 13:00, 昼12時 == 12
        }
        if p.contains("凌晨") || p.contains("午前") || p.contains("朝") {
            return hour == 12 ? 0 : hour
        }
        if p.contains("上午") || p.contains("早") || p == "am" || p == "a.m." || p == "a" {
            return hour == 12 ? 0 : hour
        }
        return hour
    }

    private static func specialMinute(_ s: String?) -> Int? {
        guard let s = s else { return nil }
        if s.contains("半") { return 30 }
        if s.contains("一刻") { return 15 }
        if s.contains("三刻") { return 45 }
        return nil
    }

    /// Parse a single time; `eveningHint` shifts a period-less time into the evening.
    private static func findTime(_ scanner: Scanner, eveningHint: Bool) -> TimeMatch? {
        let ns = scanner.ns

        // noon / midnight / 正午 / 午夜
        let special = re("\\b(noon|midnight)\\b|(正午|午夜|中午)")
        if let m = scanner.firstFree(special) {
            let t = ns.substring(with: m.range).lowercased()
            let clock = (t.contains("midnight") || t.contains("午夜")) ? Clock(hour: 0, minute: 0) : Clock(hour: 12, minute: 0)
            scanner.consume(m.range)
            return TimeMatch(clock: clock, range: m.range)
        }

        // Chinese: (period)? H点 (M分 | 半/一刻/三刻)?
        let cn = re("(上午|早上|早晨|凌晨|中午|下午|晚上|傍晚|午前|午後|朝|夜|夕方|正午|昼|深夜)?\\s*(\(cnNum){1,3})\\s*[点點時时]\\s*(?:(\(cnNum){1,3})\\s*分?|(半|一刻|三刻))?")
        if let m = scanner.firstFree(cn), let h = number(group(m, 2, in: ns)) {
            let period = group(m, 1, in: ns)
            let minNum = number(group(m, 3, in: ns))
            let special = specialMinute(group(m, 4, in: ns))
            let minute = minNum ?? special ?? 0
            var hour = adjust(hour: h, period: period, cal: .current)
            if period == nil, eveningHint, hour < 12 { hour += 12 }
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour % 24, minute: minute), range: m.range)
        }

        // English with am/pm: 3pm, 3:30 pm, 3 p.m.
        let enAP = re("\\b(\\d{1,2})(?::(\\d{2}))?\\s*([ap])\\.?\\s?m\\.?\\b")
        if let m = scanner.firstFree(enAP), let h = number(group(m, 1, in: ns)) {
            let minute = number(group(m, 2, in: ns)) ?? 0
            let ap = group(m, 3, in: ns)?.lowercased()
            let hour = adjust(hour: h, period: ap, cal: .current)
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour % 24, minute: minute), range: m.range)
        }

        // 24h colon time: 15:00, 9:30
        let colon = re("\\b(\\d{1,2}):(\\d{2})\\b")
        if let m = scanner.firstFree(colon), let h = number(group(m, 1, in: ns)), let mn = number(group(m, 2, in: ns)),
           (0...23).contains(h), (0...59).contains(mn) {
            var hour = h
            if eveningHint, hour < 12 { hour += 12 }
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour, minute: mn), range: m.range)
        }

        // "at 3", "at 3:30", "3 o'clock"
        let atN = re("\\bat\\s+(\\d{1,2})(?::(\\d{2}))?\\b")
        if let m = scanner.firstFree(atN), let h = number(group(m, 1, in: ns)), (0...23).contains(h) {
            let minute = number(group(m, 2, in: ns)) ?? 0
            var hour = h
            if eveningHint, hour < 12 { hour += 12 }
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour, minute: minute), range: m.range)
        }
        let oclock = re("\\b(\\d{1,2})\\s*o'?clock\\b")
        if let m = scanner.firstFree(oclock), let h = number(group(m, 1, in: ns)), (0...23).contains(h) {
            var hour = h
            if eveningHint, hour < 12 { hour += 12 }
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour, minute: 0), range: m.range)
        }
        return nil
    }

    /// A standalone period word with no clock number → a sensible default time.
    /// Only consulted when no explicit time was found. The negative lookahead avoids
    /// matching when a number/点/時 follows (that case is handled by `findTime`).
    private static func findBareTimeWord(_ scanner: Scanner, eveningHint: Bool) -> TimeMatch? {
        let ns = scanner.ns
        let bare = re("(清晨|早上|早晨|上午|中午|正午|下午|傍晚|晚上|morning|noon|afternoon|evening|night|午前|午後|朝|夕方|夜|昼)(?![0-9０-９一二两三四五六七八九十点點時时:])")
        if let m = scanner.firstFree(bare) {
            let w = ns.substring(with: m.range).lowercased()
            let hour: Int
            if w.contains("清晨") || w.contains("早") || w == "morning" || w.contains("朝") {
                hour = 9
            } else if w.contains("上午") || w.contains("午前") {
                hour = 10
            } else if w.contains("中午") || w.contains("正午") || w == "noon" || w.contains("昼") {
                hour = 12
            } else if w.contains("下午") || w == "afternoon" || w.contains("午後") {
                hour = 14
            } else if w.contains("傍晚") || w.contains("夕方") {
                hour = 18
            } else {
                hour = 19 // 晚上 / evening / night / 夜
            }
            scanner.consume(m.range)
            return TimeMatch(clock: Clock(hour: hour, minute: 0), range: m.range)
        }
        // "今晚 / 明晚 / tonight" gave a day with an evening hint but no clock → default 19:00.
        if eveningHint {
            return TimeMatch(clock: Clock(hour: 19, minute: 0), range: NSRange(location: NSNotFound, length: 0))
        }
        return nil
    }

    // MARK: Time range

    private struct RangeMatch { var start: Clock; var end: Clock; var range: NSRange }

    private static func findTimeRange(_ scanner: Scanner, eveningHint: Bool) -> RangeMatch? {
        let ns = scanner.ns
        let sep = "(?:-|–|—|~|to|until|到|至)"

        // English: 3-4pm, 9am-10am, 9:30-11, from 2 to 4pm
        let en = re("\\b(?:from\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*([ap]\\.?m\\.?)?\\s*\(sep)\\s*(\\d{1,2})(?::(\\d{2}))?\\s*([ap]\\.?m\\.?)?\\b")
        if let m = scanner.firstFree(en),
           let h1 = number(group(m, 1, in: ns)), let h2 = number(group(m, 4, in: ns)) {
            let m1 = number(group(m, 2, in: ns)) ?? 0
            let m2 = number(group(m, 5, in: ns)) ?? 0
            var ap1 = group(m, 3, in: ns)?.lowercased()
            let ap2 = group(m, 6, in: ns)?.lowercased()
            // "3-4pm" -> first inherits the second's am/pm.
            if ap1 == nil, ap2 != nil { ap1 = ap2 }
            // Require this to actually be a *time* range (avoid matching "5-6 apples").
            let looksLikeTime = ap1 != nil || ap2 != nil || group(m, 2, in: ns) != nil || group(m, 5, in: ns) != nil || eveningHint
            guard looksLikeTime else { return nil }
            var hh1 = adjust(hour: h1, period: ap1, cal: .current)
            var hh2 = adjust(hour: h2, period: ap2 ?? ap1, cal: .current)
            if ap1 == nil, eveningHint, hh1 < 12 { hh1 += 12 }
            if ap2 == nil, ap1 == nil, eveningHint, hh2 < 12 { hh2 += 12 }
            scanner.consume(m.range)
            return RangeMatch(start: Clock(hour: hh1 % 24, minute: m1), end: Clock(hour: hh2 % 24, minute: m2), range: m.range)
        }

        // Chinese: 下午3点到4点半, 9点-10点, 下午3点到下午5点
        let cnTime = "(上午|早上|早晨|凌晨|中午|下午|晚上|傍晚|午前|午後|朝|夜|夕方|正午|昼|深夜)?\\s*(\(cnNum){1,3})\\s*[点點時时]\\s*(?:(\(cnNum){1,3})\\s*分?|(半|一刻|三刻))?"
        let cn = re("\(cnTime)\\s*(?:到|至|-|~)\\s*\(cnTime)")
        if let m = scanner.firstFree(cn),
           let h1 = number(group(m, 2, in: ns)), let h2 = number(group(m, 6, in: ns)) {
            let p1 = group(m, 1, in: ns)
            let min1 = number(group(m, 3, in: ns)) ?? specialMinute(group(m, 4, in: ns)) ?? 0
            let p2 = group(m, 5, in: ns) ?? p1
            let min2 = number(group(m, 7, in: ns)) ?? specialMinute(group(m, 8, in: ns)) ?? 0
            var hh1 = adjust(hour: h1, period: p1, cal: .current)
            var hh2 = adjust(hour: h2, period: p2, cal: .current)
            if p1 == nil, eveningHint, hh1 < 12 { hh1 += 12 }
            if p2 == nil, p1 == nil, eveningHint, hh2 < 12 { hh2 += 12 }
            scanner.consume(m.range)
            return RangeMatch(start: Clock(hour: hh1 % 24, minute: min1), end: Clock(hour: hh2 % 24, minute: min2), range: m.range)
        }
        return nil
    }

    // MARK: Duration

    private struct DurationMatch { var seconds: TimeInterval; var range: NSRange }

    private static func findDuration(_ scanner: Scanner) -> DurationMatch? {
        let ns = scanner.ns

        // "an hour and a half", "X个半小时", "一个半小时" -> X*60 + 30 minutes
        let andHalfCN = re("(\(cnNum)+)?\\s*个半\\s*(?:小时|小時|钟头)")
        if let m = scanner.firstFree(andHalfCN) {
            let n = number(group(m, 1, in: ns)) ?? 1
            scanner.consume(m.range)
            return DurationMatch(seconds: TimeInterval(n * 3600 + 1800), range: m.range)
        }

        // Japanese "X時間半" = X hours and a half.
        let andHalfJA = re("(\(cnNum)+)?\\s*時間半")
        if let m = scanner.firstFree(andHalfJA) {
            let n = number(group(m, 1, in: ns)) ?? 1
            scanner.consume(m.range)
            return DurationMatch(seconds: TimeInterval(n * 3600 + 1800), range: m.range)
        }

        // 一刻钟 = 15 min
        let quarterCN = re("(一刻钟|一刻鐘)")
        if let m = scanner.firstFree(quarterCN) {
            scanner.consume(m.range)
            return DurationMatch(seconds: 15 * 60, range: m.range)
        }

        // Chinese hours: 1小时, 1.5小时, 两个小时, 半小时, 半个钟头
        let cnHour = re("(\(cnNum)+(?:\\.\\d+)?|半)\\s*(?:个)?\\s*(?:小时|小時|钟头|鐘頭|時間)")
        if let m = scanner.firstFree(cnHour) {
            let token = group(m, 1, in: ns) ?? ""
            let hours = parseDecimal(token)
            if let hours = hours {
                scanner.consume(m.range)
                return DurationMatch(seconds: hours * 3600, range: m.range)
            }
        }
        // Chinese minutes: 30分钟, 45分, 三十分钟
        let cnMin = re("(\(cnNum)+)\\s*分钟?")
        if let m = scanner.firstFree(cnMin), let n = number(group(m, 1, in: ns)) {
            scanner.consume(m.range)
            return DurationMatch(seconds: TimeInterval(n * 60), range: m.range)
        }

        // English: "half an hour", "an hour", "1.5h", "30 min", "2 hours", "45m"
        let halfEN = re("\\b(?:half\\s+an?\\s+hour|an?\\s+half\\s+hour)\\b")
        if let m = scanner.firstFree(halfEN) {
            scanner.consume(m.range)
            return DurationMatch(seconds: 30 * 60, range: m.range)
        }
        let anHourEN = re("\\ban?\\s+hour\\b")
        if let m = scanner.firstFree(anHourEN) {
            scanner.consume(m.range)
            return DurationMatch(seconds: 3600, range: m.range)
        }
        let enHour = re("\\b(\\d+(?:\\.\\d+)?)\\s*(hours?|hrs?|h)\\b")
        if let m = scanner.firstFree(enHour), let hours = parseDecimal(group(m, 1, in: ns)) {
            scanner.consume(m.range)
            return DurationMatch(seconds: hours * 3600, range: m.range)
        }
        let enMin = re("\\b(\\d+(?:\\.\\d+)?)\\s*(minutes?|mins?|min|m)\\b")
        if let m = scanner.firstFree(enMin), let mins = parseDecimal(group(m, 1, in: ns)) {
            scanner.consume(m.range)
            return DurationMatch(seconds: mins * 60, range: m.range)
        }
        return nil
    }

    private static func parseDecimal(_ s: String?) -> Double? {
        guard let s = s else { return nil }
        if s == "半" { return 0.5 }
        if let d = Double(s) { return d }
        if let i = ChineseNumber.parse(s) { return Double(i) }
        return nil
    }

    // MARK: Relative time ("in 30 min" / "30分钟后")

    private struct RelTimeMatch { var date: Date; var range: NSRange }

    private static func findRelativeTime(_ scanner: Scanner, now: Date) -> RelTimeMatch? {
        let ns = scanner.ns

        // English: "in 30 minutes", "in 2 hours", "in 90 min"
        let en = re("\\bin\\s+(\\d+(?:\\.\\d+)?)\\s*(hours?|hrs?|h|minutes?|mins?|min|m)\\b")
        if let m = scanner.firstFree(en), let n = parseDecimal(group(m, 1, in: ns)), let unit = group(m, 2, in: ns)?.lowercased() {
            let secs = unit.hasPrefix("h") ? n * 3600 : n * 60
            scanner.consume(m.range)
            return RelTimeMatch(date: now.addingTimeInterval(secs), range: m.range)
        }

        // Chinese: "30分钟后", "2小时后", "半小时后"
        let cn = re("(\(cnNum)+(?:\\.\\d+)?|半)\\s*(?:个)?\\s*(小时|小時|钟头|分钟|分|時間)\\s*(后|之后|後)")
        if let m = scanner.firstFree(cn), let n = parseDecimal(group(m, 1, in: ns)), let unit = group(m, 2, in: ns) {
            let secs = (unit.contains("小时") || unit.contains("钟头") || unit.contains("小時") || unit.contains("時間")) ? n * 3600 : n * 60
            scanner.consume(m.range)
            return RelTimeMatch(date: now.addingTimeInterval(secs), range: m.range)
        }
        return nil
    }
}
