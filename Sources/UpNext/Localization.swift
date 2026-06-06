import Foundation

/// Lightweight localization: UI chrome follows the system language (en / 中文 / 日本語),
/// to match the multilingual parser. Strings are inlined at call sites via `L(...)` for
/// readability — there are few enough that a full .strings table isn't worth it.
enum AppLang { case en, zh, ja }

enum L10n {
    /// Forced language (used by the screenshot renderer); nil = detect from the system.
    static var override: AppLang?

    static var lang: AppLang {
        if let override { return override }
        let pref = (Locale.preferredLanguages.first ?? "en").lowercased()
        if pref.hasPrefix("zh") { return .zh }
        if pref.hasPrefix("ja") { return .ja }
        return .en
    }

    /// Locale for date/number formatting in the current UI language.
    static var locale: Locale {
        switch lang {
        case .en: return Locale(identifier: "en_US")
        case .zh: return Locale(identifier: "zh_CN")
        case .ja: return Locale(identifier: "ja_JP")
        }
    }

    /// CJK locales read clock times more naturally in 24-hour form.
    static var uses24Hour: Bool { lang != .en }
}

/// Pick the string for the current UI language.
func L(_ en: String, _ zh: String, _ ja: String) -> String {
    switch L10n.lang {
    case .en: return en
    case .zh: return zh
    case .ja: return ja
    }
}
