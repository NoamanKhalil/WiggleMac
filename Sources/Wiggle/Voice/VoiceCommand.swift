import Foundation

/// Spoken commands. Saying "screenshot" (or "take a screenshot and …") captures the screen,
/// and whatever else was said becomes the question.
enum VoiceCommand {
    struct Parsed: Equatable {
        let wantsScreenshot: Bool
        let question: String
    }

    // "take a screenshot", "screen shot", "capture my screen", "grab the screen", plus a trailing "and"/punctuation.
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(?:please\s+)?(?:(?:take|grab)\s+(?:a\s+)?)?(?:screen\s?shot|(?:capture|grab)\s+(?:my|the)\s+screen)\b[\s,.:;!?-]*(?:and\s+(?:then\s+)?)?"#,
        options: [.caseInsensitive]
    )

    static func parse(_ utterance: String) -> Parsed {
        let range = NSRange(utterance.startIndex..., in: utterance)
        guard let match = pattern.firstMatch(in: utterance, range: range),
              let matched = Range(match.range, in: utterance)
        else {
            return Parsed(wantsScreenshot: false, question: utterance.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var rest = utterance
        rest.removeSubrange(matched)
        let question = rest.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return Parsed(wantsScreenshot: true, question: question.isEmpty ? "" : capitalizedFirst(question) + terminalPunctuation(of: rest))
    }

    private static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Keeps a trailing "?" that trimming removed.
    private static func terminalPunctuation(of text: String) -> String {
        text.trimmingCharacters(in: .whitespaces).hasSuffix("?") ? "?" : ""
    }
}
