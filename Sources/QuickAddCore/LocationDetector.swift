import Foundation

/// Rule-based location & meeting detection (Japanese / Chinese / English).
///
/// This is the deterministic NLP layer that decides "is this a meeting at a place?"
/// without needing an LLM. It looks for address/venue cues (丁目, 階, タワー, Floor,
/// Room, 〒, `1-8-10`, …) and, separately, meeting keywords (会議, 开会, meeting, …).
enum LocationDetector {

    struct Detection {
        /// Span of the recognized location in the (masked) input.
        var range: NSRange
        /// Cleaned location text (internal whitespace/newlines collapsed).
        var text: String
        /// True when the span also contains a meeting keyword (verb+place phrase),
        /// in which case the caller may keep it as the title instead of extracting.
        var overlapsMeetingKeyword: Bool
    }

    // MARK: Cues

    // Address / venue indicators. Multi-character & patterned cues are favored over
    // ambiguous single characters (号/室/区) to avoid false positives.
    private static let cuePattern = "(?i)" + [
        "丁目", "番地", "番[0-9０-９]", "会議室", "会议室", "オフィス",
        "ビル", "ビルディング", "タワー", "マンション", "アパート", "ホール",
        "プラザ", "センター", "スクエア", "ルーム",
        "大厦", "大廈", "大楼", "大樓", "写字楼", "广场", "廣場", "酒店", "饭店", "宾馆",
        "[0-9０-９]+\\s*階", "[0-9０-９]+\\s*[FfＦ]\\b", "[0-9０-９]+\\s*楼", "[0-9０-９]+\\s*层",
        "[0-9０-９]+\\s*号室", "[0-9０-９]+\\s*号馆", "棟",
        "[0-9]+-[0-9]+-[0-9]+",                         // 1-8-10 chome-banchi
        "〒\\s*[0-9]{3}-?[0-9]{4}",                      // postal
        "東京都", "京都府", "大阪府", "北海道", "[\\x{4e00}-\\x{9fff}]{1,3}県",
        "\\b(?:street|st|avenue|ave|road|rd|blvd|boulevard|lane|floor|fl|room|rm|suite|ste|building|bldg|hall|plaza|tower|center|centre|campus)\\b"
    ].joined(separator: "|")

    private static let cueRegex = try! NSRegularExpression(pattern: cuePattern)

    // Meeting / appointment keywords.
    private static let meetingPattern = "(?i)" + [
        "开会", "會議", "会议", "例会", "周会", "週会", "月会", "见面", "見面", "会面",
        "面试", "面試", "面谈", "面談", "面接", "拜访", "訪問", "商谈", "商談", "约见",
        "碰头", "评审", "答辩", "路演", "宣讲", "面签", "约饭", "聚餐", "会食",
        "会議", "打ち合わせ", "打合せ", "打合わせ", "ミーティング", "アポ", "商談",
        "\\b(?:meeting|meet|mtg|standup|stand-up|sync|1:1|interview|appointment|appt|conference|demo|presentation|review|catch[ -]?up|coffee chat)\\b"
    ].joined(separator: "|")

    private static let meetingRegex = try! NSRegularExpression(pattern: meetingPattern)

    // MARK: API

    static func containsMeetingKeyword(_ text: String) -> Bool {
        let ns = text as NSString
        return meetingRegex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil
    }

    // A "block" is a maximal run of tokens separated by *single* whitespace; runs of
    // 2+ whitespace (e.g. where a date/time was masked out) separate blocks.
    private static let blockRegex = try! NSRegularExpression(pattern: "\\S+(?:\\s\\S+)*")

    /// Find a location span in `masked` (a string where already-consumed tokens are
    /// spaces). Returns the whole block(s) containing address/venue cues, so trailing
    /// pieces like "Floor 12" or "オフィスタワーX棟 7階" are captured. Nil when no cue.
    static func detect(in masked: String) -> Detection? {
        let ns = masked as NSString
        let full = NSRange(location: 0, length: ns.length)
        let cues = cueRegex.matches(in: masked, range: full)
        guard !cues.isEmpty else { return nil }

        let blocks = blockRegex.matches(in: masked, range: full).map { $0.range }
        let cueBlocks = blocks.filter { block in
            cues.contains { NSLocationInRange($0.range.location, block) }
        }
        guard let first = cueBlocks.first, let last = cueBlocks.last else { return nil }

        let span = NSRange(location: first.location,
                           length: (last.location + last.length) - first.location)
        let raw = ns.substring(with: span)
        let text = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return Detection(range: span, text: text, overlapsMeetingKeyword: containsMeetingKeyword(raw))
    }

    /// Pick a human-friendly title from location text when nothing else remains:
    /// the first "name-like" token (letters/kana, no digits) — usually the venue name —
    /// else the whole text.
    static func nameLikeTitle(from location: String) -> String {
        let tokens = location.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let candidate = tokens.first { tok in
            tok.count >= 2 &&
            !tok.contains(where: { $0.isNumber }) &&
            tok.contains(where: { $0.isLetter })
        }
        return candidate ?? location
    }
}
