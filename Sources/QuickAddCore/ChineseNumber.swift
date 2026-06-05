import Foundation

/// Parses Chinese numerals (0–99) such as 三, 十, 十五, 二十三, 两.
/// Used for clock times ("下午三点"), durations ("两小时"), and ordinals.
enum ChineseNumber {
    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]

    /// All characters that can appear in a Chinese numeral (for regex building).
    static let numeralCharacterClass = "零〇一二两三四五六七八九十"

    /// Parse a pure Chinese-numeral string into an integer (0–99). Returns nil if unrecognized.
    static func parse(_ raw: some StringProtocol) -> Int? {
        let s = String(raw)
        if s.isEmpty { return nil }

        // Pure ASCII digits passed through here too.
        if let n = Int(s) { return n }

        if let tenIndex = s.firstIndex(of: "十") {
            let before = s[s.startIndex..<tenIndex]
            let after = s[s.index(after: tenIndex)...]
            let tens: Int
            if before.isEmpty {
                tens = 1 // 十 == 10
            } else if let d = digits[before.first!], before.count == 1 {
                tens = d
            } else {
                return nil
            }
            let ones: Int
            if after.isEmpty {
                ones = 0
            } else if let d = digits[after.first!], after.count == 1 {
                ones = d
            } else {
                return nil
            }
            return tens * 10 + ones
        }

        // No 十: treat as a run of single digits, but only a single digit is meaningful
        // for our use (hours/minutes/intervals). Take the first if it's a known digit.
        if s.count == 1, let d = digits[s.first!] {
            return d
        }
        return nil
    }
}
