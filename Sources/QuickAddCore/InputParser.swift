import Foundation

/// Turns a single quick-add line into a structured `ParsedItem`.
///
/// Pipeline (each stage masks the span it claims so later stages and the title
/// don't see it): normalize → notes → priority → list → tags → recurrence →
/// date/time/duration/range → leftover text becomes the title.
public struct InputParser {
    public let now: Date
    public let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        var cal = calendar
        if cal.locale == nil { cal.locale = Locale(identifier: "en_US_POSIX") }
        self.calendar = cal
    }

    public func parse(_ rawInput: String) -> ParsedItem {
        let normalized = Self.normalize(rawInput)
        let masked = NSMutableString(string: normalized)
        var item = ParsedItem()
        var highlights: [Highlight] = []

        // Mask a claimed span with equal-length spaces so offsets stay aligned.
        func mask(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        func addHighlight(_ range: NSRange, _ kind: Highlight.Kind) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            highlights.append(Highlight(location: range.location, length: range.length, kind: kind))
        }

        // 1) URL — extracted first so a URL's "//" can't be mistaken for the notes marker.
        //    Skip the (relatively expensive) data detector unless the text could hold a URL.
        if (normalized.contains(".") || normalized.contains("//")), let detector = Self.urlDetector {
            for m in detector.matches(in: masked.copyString, options: [], range: masked.fullRange) {
                if let url = m.url {
                    item.url = url
                    addHighlight(m.range, .url)
                    mask(m.range)
                    break
                }
            }
        }

        // 2) Notes: text after a " // " separator or a newline.
        if let notesRange = Self.notesSeparator.firstMatch(in: masked.copyString, options: [], range: masked.fullRange) {
            let notesStart = notesRange.range.location
            let after = NSRange(location: notesRange.range.location + notesRange.range.length,
                                length: masked.length - (notesRange.range.location + notesRange.range.length))
            let notesText = masked.substring(with: after).trimmingCharacters(in: .whitespacesAndNewlines)
            if !notesText.isEmpty { item.notes = notesText }
            mask(NSRange(location: notesStart, length: masked.length - notesStart))
        }

        // 3) Priority: !, !!, !!! or p1/p2/p3 as a standalone token.
        if let (range, priority) = Self.matchPriority(masked) {
            item.priority = priority
            addHighlight(range, .priority)
            mask(range)
        }

        // 3a) Priority keywords ("urgent" / 紧急 / 重要 / 至急). Set priority but keep the
        //     word in the title (it's descriptive) — just tint it.
        if item.priority == .none, let kw = Self.matchPriorityKeyword(masked) {
            item.priority = kw.priority
            addHighlight(kw.range, .priority)
        }

        // 4) List: ~Name
        if let m = Self.listPattern.firstMatch(in: masked.copyString, options: [], range: masked.fullRange) {
            let nameRange = m.range(at: 1)
            if nameRange.location != NSNotFound {
                item.listName = masked.substring(with: nameRange)
                addHighlight(m.range, .list)
                mask(m.range)
            }
        }

        // 5) Tags: #tag (collect all). Capture, then mask in a second pass so the
        //    matches computed on the pre-mask snapshot stay valid.
        let tagMatches = Self.tagPattern.matches(in: masked.copyString, options: [], range: masked.fullRange)
        for m in tagMatches {
            let nameRange = m.range(at: 1)
            guard nameRange.location != NSNotFound else { continue }
            item.tags.append(masked.substring(with: nameRange))
            addHighlight(m.range, .tag)
        }
        for m in tagMatches { mask(m.range) }

        // 6) Recurrence
        if let rec = matchRecurrence(masked) {
            item.recurrence = rec.rule
            addHighlight(rec.range, .recurrence)
            mask(rec.range)
        }
        // 6a) Occurrence count ("共7次" / "5回" / "10 times") — only meaningful with a recurrence.
        if item.recurrence != nil, let cnt = Self.matchOccurrenceCount(masked) {
            item.recurrence?.occurrenceCount = cnt.count
            addHighlight(cnt.range, .recurrence)
            mask(cnt.range)
        }
        // 6a2) Recurrence end after a duration ("for 2 weeks" / "持续两周" / "2週間").
        var recurrenceEndSpec: (component: Calendar.Component, value: Int)?
        if item.recurrence != nil, let forSpec = Self.matchRecurrenceFor(masked) {
            recurrenceEndSpec = (forSpec.component, forSpec.value)
            addHighlight(forSpec.range, .recurrence)
            mask(forSpec.range)
        }
        // 6a3) Recurrence end at a weekday ("until Friday" / "到周五" / "金曜まで").
        if item.recurrence != nil, recurrenceEndSpec == nil, let until = matchUntilWeekday(masked) {
            item.recurrence?.endDate = until.date
            addHighlight(until.range, .recurrence)
            mask(until.range)
        }

        // 6b) Lead-time alarm ("提前30分钟" / "30分前" / "1 day before"). Extracted before
        //     the date stage so its number isn't mistaken for an event duration.
        if let lead = Self.matchLeadTime(masked) {
            item.leadTimeSeconds = lead.seconds
            addHighlight(lead.range, .time)
            mask(lead.range)
        }

        // 6c) Explicit all-day ("全天" / "all day" / "終日").
        var forceAllDay = false
        if let m = Self.allDayPattern.firstMatch(in: masked.copyString, options: [], range: masked.fullRange) {
            forceAllDay = true
            addHighlight(m.range, .date)
            mask(m.range)
        }

        // 7) Date / time / duration / range
        let dt = DateTimeParser.parse(masked.copyString, now: now, calendar: calendar)
        item.startDate = dt.startDate
        item.endDate = dt.endDate
        item.hasTime = dt.hasTime
        item.isAllDay = dt.isAllDay
        for c in dt.consumed {
            addHighlight(c.range, c.kind)
            mask(c.range)
        }
        let explicitEvent = dt.isEvent

        // 7b) Location & meeting detection (rule-based NLP) on the remaining text.
        let cueDetection = LocationDetector.detect(in: masked.copyString)
        let meetingKeyword = LocationDetector.containsMeetingKeyword(masked.copyString)
        if let det = cueDetection {
            // Keep the phrase as the title (don't pull out a location) only for a
            // single connected token that is really an action, e.g. "去三楼会议室开会":
            // it would empty the title, contains a meeting keyword, and has no spaces to
            // separate a venue from a subject. Space-separated venues are still extracted.
            let leftover = Self.maskedCopy(masked, removing: det.range)
            let titleWouldBeEmpty = Self.cleanTitle(leftover).isEmpty
            let singleConnectedToken = !det.text.contains(" ")
            let keepAsTitle = titleWouldBeEmpty && det.overlapsMeetingKeyword && singleConnectedToken
            if !keepAsTitle {
                item.location = det.text
                addHighlight(det.range, .location)
                mask(det.range)
            }
        }

        // 7c) Reminder vs. event. A timed item that is a meeting or has a place is an event.
        let hasLocationSignal = (item.location != nil) || (cueDetection != nil)
        let isEvent = explicitEvent || (item.hasTime && (hasLocationSignal || meetingKeyword))
        item.kind = isEvent ? .event : .reminder
        if isEvent, item.endDate == nil, item.hasTime, let start = item.startDate {
            item.endDate = start.addingTimeInterval(Self.defaultEventDuration)
        }

        // Explicit all-day overrides any time-of-day.
        if forceAllDay {
            item.isAllDay = true
            item.hasTime = false
            if let s = item.startDate { item.startDate = calendar.startOfDay(for: s) }
        }

        // A recurring item with no explicit date needs an anchor date to recur from.
        if item.recurrence != nil, item.startDate == nil {
            if let rec = item.recurrence, rec.frequency == .weekly, let wd = rec.weekdays.first {
                item.startDate = nextWeekday(wd)
            } else {
                item.startDate = calendar.startOfDay(for: now)
            }
            item.isAllDay = !item.hasTime
        }

        // Resolve a duration-based recurrence end now that the start is known.
        if let spec = recurrenceEndSpec, item.recurrence != nil {
            let base = item.startDate ?? calendar.startOfDay(for: now)
            item.recurrence?.endDate = calendar.date(byAdding: spec.component, value: spec.value, to: base)
        }

        // 8) Title = whatever is left. If empty but we found a place, name it after
        //    the most name-like part of the location.
        item.title = Self.cleanTitle(masked.copyString)
        if item.title.isEmpty, let loc = item.location {
            item.title = LocationDetector.nameLikeTitle(from: loc)
        }
        item.highlights = highlights.sorted { $0.location < $1.location }
        return item
    }

    // MARK: - Normalization

    /// Map the full-width characters a CJK keyboard produces to their ASCII forms,
    /// one-to-one so UTF-16 offsets (and therefore highlight ranges) are preserved.
    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19: // ０-９
                out.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF01: out.append("!")   // ！
            case 0xFF1A: out.append(":")   // ：
            case 0xFF5E, 0x301C: out.append("~") // ～ 〜
            case 0xFF03: out.append("#")   // ＃
            case 0xFF0D: out.append("-")   // －
            case 0xFF0E: out.append(".")   // ．
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// A copy of `s` with `range` blanked to spaces (used to preview the leftover title).
    static func maskedCopy(_ s: NSMutableString, removing range: NSRange) -> String {
        let copy = NSMutableString(string: s as String)
        if range.location != NSNotFound, range.length > 0 {
            copy.replaceCharacters(in: range, with: String(repeating: " ", count: range.length))
        }
        return copy as String
    }

    static func cleanTitle(_ s: String) -> String {
        let collapsed = s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimSet = CharacterSet(charactersIn: " ,，、:：;；-–—~～·")
        return collapsed.trimmingCharacters(in: trimSet)
    }

    // MARK: - Priority

    private static func matchPriority(_ s: NSMutableString) -> (NSRange, Priority)? {
        let str = s.copyString
        if let m = bangPattern.firstMatch(in: str, options: [], range: s.fullRange) {
            let g = m.range(at: 1)
            let bangs = s.substring(with: g)
            let p: Priority = bangs.count >= 3 ? .high : (bangs.count == 2 ? .medium : .low)
            return (g, p)
        }
        if let m = pLevelPattern.firstMatch(in: str, options: [], range: s.fullRange) {
            let g = m.range(at: 1)
            let token = s.substring(with: g).lowercased()
            let p: Priority = token.hasSuffix("1") ? .high : (token.hasSuffix("2") ? .medium : .low)
            return (g, p)
        }
        return nil
    }

    // MARK: - Priority keywords

    private static let highPriorityKeyword = r("(紧急|緊急|重要|急ぎ|至急|大事|要紧|urgent|asap|important|critical)")
    private static let lowPriorityKeyword = r("(不急|低优先级|低優先|low\\s*priority|whenever|someday)")

    private static func matchPriorityKeyword(_ s: NSMutableString) -> (range: NSRange, priority: Priority)? {
        let str = s.copyString
        let full = s.fullRange
        if let m = highPriorityKeyword.firstMatch(in: str, options: [], range: full) { return (m.range, .high) }
        if let m = lowPriorityKeyword.firstMatch(in: str, options: [], range: full) { return (m.range, .low) }
        return nil
    }

    // MARK: - Recurrence

    private struct RecurrenceMatch { var rule: RecurrenceRule; var range: NSRange }

    private static let recWeekdayMap: [String: Int] = [
        "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3, "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6, "saturday": 7, "sat": 7,
        "sunday": 1, "sun": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1
    ]

    private func matchRecurrence(_ s: NSMutableString) -> RecurrenceMatch? {
        let str = s.copyString
        let full = s.fullRange

        // Weekly on a specific weekday: 每周一 / 每星期二 / every monday
        if let m = Self.recWeeklyDayCN.firstMatch(in: str, options: [], range: full),
           let wd = (m.range(at: 1).location != NSNotFound ? Self.recWeekdayMap[s.substring(with: m.range(at: 1))] : nil) {
            return RecurrenceMatch(rule: RecurrenceRule(frequency: .weekly, interval: 1, weekdays: [wd]), range: m.range)
        }
        if let m = Self.recWeeklyDayEN.firstMatch(in: str, options: [], range: full),
           m.range(at: 1).location != NSNotFound,
           let wd = Self.recWeekdayMap[s.substring(with: m.range(at: 1)).lowercased()] {
            return RecurrenceMatch(rule: RecurrenceRule(frequency: .weekly, interval: 1, weekdays: [wd]), range: m.range)
        }
        // Weekly on a specific weekday, Japanese: 毎週月曜 / 毎週金曜日
        if let m = Self.recWeeklyDayJA.firstMatch(in: str, options: [], range: full),
           m.range(at: 1).location != NSNotFound,
           let wd = ["月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7, "日": 1][s.substring(with: m.range(at: 1))] {
            return RecurrenceMatch(rule: RecurrenceRule(frequency: .weekly, interval: 1, weekdays: [wd]), range: m.range)
        }

        // every N <unit> / 每N<unit>
        for (pattern, freq) in Self.recIntervalPatterns {
            if let m = pattern.firstMatch(in: str, options: [], range: full) {
                let n = m.range(at: 1).location != NSNotFound ? (Int(s.substring(with: m.range(at: 1))) ?? ChineseNumber.parse(s.substring(with: m.range(at: 1))) ?? 1) : 1
                return RecurrenceMatch(rule: RecurrenceRule(frequency: freq, interval: n), range: m.range)
            }
        }

        // Plain daily / weekly / monthly / yearly
        for (pattern, freq) in Self.recSimplePatterns {
            if let m = pattern.firstMatch(in: str, options: [], range: full) {
                return RecurrenceMatch(rule: RecurrenceRule(frequency: freq), range: m.range)
            }
        }
        return nil
    }

    // MARK: - Occurrence count

    private static let occurrenceCountPatterns = [
        r("(?:共|计|x|×)?\\s*([0-9零〇一二两三四五六七八九十]+)\\s*(?:次|回)"),
        r("\\b([0-9]+)\\s*times\\b")
    ]

    private static func matchOccurrenceCount(_ s: NSMutableString) -> (range: NSRange, count: Int)? {
        let str = s.copyString
        let full = s.fullRange
        for regex in occurrenceCountPatterns {
            guard let m = regex.firstMatch(in: str, options: [], range: full) else { continue }
            let g = m.range(at: 1)
            guard g.location != NSNotFound else { continue }
            let numStr = s.substring(with: g)
            if let n = Int(numStr) ?? ChineseNumber.parse(numStr), n > 0 {
                return (m.range, n)
            }
        }
        return nil
    }

    // MARK: - Recurrence end ("for N weeks")

    private static let recForEN = r("\\bfor\\s+(\\d+)\\s+(day|week|month)s?\\b")
    private static let recForZH = r("持续\\s*([0-9零〇一二两三四五六七八九十]+)\\s*(天|周|星期|个月|月)")
    private static let recForJA = r("([0-9一二三四五六七八九十]+)\\s*(日間|週間|ヶ月間|か月間)")

    private static func matchRecurrenceFor(_ s: NSMutableString) -> (range: NSRange, component: Calendar.Component, value: Int)? {
        let str = s.copyString
        let full = s.fullRange
        func parse(_ regex: NSRegularExpression) -> (NSRange, String, Int)? {
            guard let m = regex.firstMatch(in: str, options: [], range: full) else { return nil }
            let numStr = s.substring(with: m.range(at: 1))
            guard let n = Int(numStr) ?? ChineseNumber.parse(numStr), n > 0 else { return nil }
            return (m.range, s.substring(with: m.range(at: 2)), n)
        }
        let hit = parse(recForEN) ?? parse(recForZH) ?? parse(recForJA)
        guard let (range, unit, n) = hit else { return nil }
        if unit.contains("week") || unit.contains("周") || unit.contains("星期") || unit.contains("週") {
            return (range, .day, n * 7)
        }
        if unit.contains("month") || unit.contains("月") {
            return (range, .month, n)
        }
        return (range, .day, n) // day / 天 / 日間
    }

    // MARK: - Lead-time alarm

    private static let leadTimePatterns: [(NSRegularExpression, Int, Int)] = [
        (r("提前\\s*([0-9零〇一二两三四五六七八九十]+)?\\s*(分钟|分|小时|个小时|小時|钟头|天|周|星期)"), 1, 2),
        (r("([0-9一二三四五六七八九十]+)\\s*(分|時間|日|週間)\\s*前"), 1, 2),
        (r("(?:remind(?:\\s+me)?\\s+|alert\\s+)?([0-9]+)\\s*(minutes?|mins?|min|hours?|hrs?|hr|days?|weeks?)\\s+(?:before|ahead|prior|early|in advance)"), 1, 2)
    ]

    private static func matchLeadTime(_ s: NSMutableString) -> (range: NSRange, seconds: TimeInterval)? {
        let str = s.copyString
        let full = s.fullRange
        for (regex, numIdx, unitIdx) in leadTimePatterns {
            guard let m = regex.firstMatch(in: str, options: [], range: full) else { continue }
            let numRange = m.range(at: numIdx)
            let numStr = numRange.location != NSNotFound ? s.substring(with: numRange) : "1"
            let n = Int(numStr) ?? ChineseNumber.parse(numStr) ?? 1
            let unit = s.substring(with: m.range(at: unitIdx)).lowercased()
            let per: TimeInterval
            if unit.contains("分") || unit.contains("min") { per = 60 }
            else if unit.contains("小时") || unit.contains("小時") || unit.contains("時間") || unit.contains("钟头") || unit.contains("hour") || unit.contains("hr") { per = 3600 }
            else if unit.contains("天") || unit.contains("日") || unit.contains("day") { per = 86400 }
            else if unit.contains("周") || unit.contains("星期") || unit.contains("週") || unit.contains("week") { per = 604800 }
            else { per = 0 }
            guard per > 0 else { continue }
            return (m.range, per * Double(n))
        }
        return nil
    }

    // MARK: - Recurrence end at a weekday ("until Friday")

    private static let untilEN = r("\\buntil\\s+(next\\s+)?(monday|mon|tuesday|tues|tue|wednesday|weds|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun)\\b")
    private static let untilZH = r("到\\s*(下周|下星期)?\\s*(?:周|星期|礼拜)\\s*([一二三四五六日天])")
    private static let untilJA = r("([月火水木金土日])曜日?\\s*まで")

    private func matchUntilWeekday(_ s: NSMutableString) -> (range: NSRange, date: Date)? {
        let str = s.copyString
        let full = s.fullRange
        if let m = Self.untilEN.firstMatch(in: str, options: [], range: full),
           m.range(at: 2).location != NSNotFound,
           let wd = Self.recWeekdayMap[s.substring(with: m.range(at: 2)).lowercased()] {
            var d = nextWeekday(wd)
            if m.range(at: 1).location != NSNotFound { d = calendar.date(byAdding: .day, value: 7, to: d) ?? d }
            return (m.range, d)
        }
        if let m = Self.untilZH.firstMatch(in: str, options: [], range: full),
           m.range(at: 2).location != NSNotFound,
           let wd = Self.recWeekdayMap[s.substring(with: m.range(at: 2))] {
            var d = nextWeekday(wd)
            if m.range(at: 1).location != NSNotFound { d = calendar.date(byAdding: .day, value: 7, to: d) ?? d }
            return (m.range, d)
        }
        if let m = Self.untilJA.firstMatch(in: str, options: [], range: full),
           let wd = ["月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7, "日": 1][s.substring(with: m.range(at: 1))] {
            return (m.range, nextWeekday(wd))
        }
        return nil
    }

    private func nextWeekday(_ target: Int) -> Date {
        let cur = calendar.component(.weekday, from: now)
        let delta = (target - cur + 7) % 7
        return calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now)) ?? now
    }

    // MARK: - Compiled patterns

    private static func r(_ p: String, _ o: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: o)
    }

    // Notes start at an explicit " // " marker. (A bare newline is NOT a separator —
    // multi-line input is often a continued address/venue, handled by the location pass.)
    static let notesSeparator = r("(?:^|\\s)//\\s*")
    static let defaultEventDuration: TimeInterval = 3600
    private static let bangPattern = r("(?:^|\\s)(!{1,3})(?=\\s|$)")
    private static let pLevelPattern = r("(?:^|\\s)(p[1-3])(?=\\s|$)")
    private static let listPattern = r("(?:^|\\s)~([\\p{L}\\p{N}_\\-/]+)")
    private static let tagPattern = r("(?:^|\\s)#([\\p{L}\\p{N}_\\-/]+)")
    private static let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static let allDayPattern = r("(全天|整天|all[\\s-]?day|終日|终日)")
    private static let recWeeklyDayCN = r("(?:每|每个)\\s*(?:周|星期|礼拜)\\s*([一二三四五六日天])")
    private static let recWeeklyDayEN = r("every\\s+(monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thu|friday|fri|saturday|sat|sunday|sun)\\b")

    private static let recIntervalPatterns: [(NSRegularExpression, RecurrenceFrequency)] = [
        (r("(?:每|每隔)\\s*([0-9零〇一二两三四五六七八九十]+)\\s*天"), .daily),
        (r("(?:每|每隔)\\s*([0-9零〇一二两三四五六七八九十]+)\\s*(?:周|星期)"), .weekly),
        (r("(?:每|每隔)\\s*([0-9零〇一二两三四五六七八九十]+)\\s*(?:个月|月)"), .monthly),
        (r("(?:每|每隔)\\s*([0-9零〇一二两三四五六七八九十]+)\\s*年"), .yearly),
        (r("every\\s+(\\d+)\\s+days?"), .daily),
        (r("every\\s+(\\d+)\\s+weeks?"), .weekly),
        (r("every\\s+(\\d+)\\s+months?"), .monthly),
        (r("every\\s+(\\d+)\\s+years?"), .yearly)
    ]

    private static let recWeeklyDayJA = r("毎週\\s*([月火水木金土日])曜日?")

    private static let recSimplePatterns: [(NSRegularExpression, RecurrenceFrequency)] = [
        (r("(每天|每日|天天|每一天|毎日|daily|every\\s*day|everyday)"), .daily),
        (r("(每周|每星期|每个星期|每个周|毎週|weekly|every\\s*week)"), .weekly),
        (r("(每月|每个月|每月份|毎月|monthly|every\\s*month)"), .monthly),
        (r("(每年|每一年|毎年|yearly|annually|every\\s*year)"), .yearly)
    ]
}

private extension NSMutableString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }
    /// A stable immutable snapshot for regex matching (NSRegularExpression wants a String).
    var copyString: String { self as String }
}
