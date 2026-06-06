import Foundation
import UpNextCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional on-device LLM refinement (Apple's Foundation Models, macOS 26+).
///
/// The rule-based parser in UpNextCore is always the baseline. When Apple
/// Intelligence is enabled *and* the user opts in, this nudges the result for fuzzy
/// cases the rules miss (e.g. "明天3点 麦当劳" → event at McDonald's). It never
/// blocks the UI: the live preview shows the heuristic result immediately and this
/// updates it a moment later if it has something better.
@MainActor
final class LLMRefiner {
    enum Availability: Equatable {
        case available
        case appleIntelligenceOff
        case modelNotReady
        case deviceNotEligible
        case unsupportedOS
        case unknown(String)

        var userText: String {
            switch self {
            case .available: return "Available"
            case .appleIntelligenceOff: return "Turn on Apple Intelligence in System Settings"
            case .modelNotReady: return "Model downloading…"
            case .deviceNotEligible: return "Not supported on this Mac"
            case .unsupportedOS: return "Requires macOS 26+"
            case .unknown(let s): return s
            }
        }
    }

    static let shared = LLMRefiner()

    var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .appleIntelligenceOff
                case .modelNotReady: return .modelNotReady
                case .deviceNotEligible: return .deviceNotEligible
                @unknown default: return .unknown("Unavailable")
                }
            @unknown default:
                return .unknown("Unavailable")
            }
        }
        #endif
        return .unsupportedOS
    }

    var isAvailable: Bool { availability == .available }

    /// Return a possibly-refined item. Falls back to `base` on any error/timeout.
    func refine(input: String, base: ParsedItem) async -> ParsedItem {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isAvailable {
            let instructions = """
            You refine parsing of one quick-add line (Japanese / Chinese / English) for a \
            reminders + calendar app. Reply with ONLY compact JSON, no prose:
            {"isEvent": bool, "location": string, "title": string}
            - isEvent = true when it is a meeting/appointment (a specific time plus a place, \
            a named venue, or a meeting verb); false for a plain to-do.
            - location = the physical place or address, else "".
            - title = the concise subject, without the date, time, or location.
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: input)
                return Self.merge(base: base, json: response.content)
            } catch {
                return base
            }
        }
        #endif
        return base
    }

    /// Conservative merge: the LLM may *upgrade* a timed reminder to an event and add a
    /// location/title, but explicit ranges/durations from the rules are never overridden.
    static func merge(base: ParsedItem, json raw: String) -> ParsedItem {
        guard let jsonString = extractJSON(raw),
              let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return base }

        var item = base
        if let isEvent = obj["isEvent"] as? Bool, isEvent, item.kind == .reminder, item.hasTime {
            item.kind = .event
            if item.endDate == nil, let start = item.startDate {
                item.endDate = start.addingTimeInterval(3600)
            }
        }
        if let location = obj["location"] as? String {
            let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, item.location == nil { item.location = trimmed }
        }
        if let title = obj["title"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, item.title.isEmpty { item.title = trimmed }
        }
        return item
    }

    private static func extractJSON(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else { return nil }
        return String(s[start...end])
    }
}
