import Foundation

/// Matches the last spoken words against a small forward window in the script.
struct ScriptFollower {
    private(set) var words: [String] = []
    private(set) var position = 0

    mutating func load(_ text: String) {
        words = Self.words(in: text)
        position = 0
    }

    mutating func seek(to word: Int) {
        position = min(max(0, word), words.count)
    }

    mutating func follow(_ transcript: String) -> Int {
        let spoken = Self.words(in: transcript)
        guard !spoken.isEmpty, position < words.count else { return position }
        let lower = max(0, position - 5)
        let upper = min(words.count, position + 45)
        var bestPosition = position
        var bestScore = 0

        for end in (lower + 1)...upper {
            for length in 1...min(5, spoken.count, end - lower) {
                var matches = true
                for offset in 0..<length where words[end - length + offset] != spoken[spoken.count - length + offset] {
                    matches = false
                    break
                }
                guard matches else { continue }
                let score = length * 10 - abs(end - position) / 3
                if score > bestScore && end > position {
                    bestScore = score
                    bestPosition = end
                }
            }
        }
        // A single common word is too weak to move the prompt far ahead.
        if bestPosition - position > 8 && bestScore < 20 { return position }
        position = bestPosition
        return position
    }

    static func words(in text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func displayWords(in text: String) -> [String] {
        let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+[\\p{P}]*")
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }
}
