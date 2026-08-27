import Foundation

public struct AppSearchDocument: Hashable, Sendable {
    public let id: String
    public let primaryText: String
    public let secondaryTexts: [String]
    public let isRunning: Bool
    public let isBackgroundOnly: Bool
    public let recencyRank: Int?
    public let sourceOrder: Int

    public init(
        id: String,
        primaryText: String,
        secondaryTexts: [String] = [],
        isRunning: Bool = false,
        isBackgroundOnly: Bool = false,
        recencyRank: Int? = nil,
        sourceOrder: Int = 0
    ) {
        self.id = id
        self.primaryText = primaryText
        self.secondaryTexts = secondaryTexts
        self.isRunning = isRunning
        self.isBackgroundOnly = isBackgroundOnly
        self.recencyRank = recencyRank
        self.sourceOrder = sourceOrder
    }
}

public struct AppSearchMatch: Equatable, Sendable {
    public let id: String
    public let score: Int

    public init(id: String, score: Int) {
        self.id = id
        self.score = score
    }
}

/// Deterministic, side-effect-free search ranking shared by the app and tests.
/// Exact and prefix matches dominate; fuzzy subsequence matching is deliberately
/// limited to 3+ characters to avoid noisy one-letter results.
public enum AppSearchScorer {
    public static func rankedMatches(
        query: String,
        documents: [AppSearchDocument]
    ) -> [AppSearchMatch] {
        let normalizedQuery = normalize(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return [] }

        return documents.compactMap { document -> (match: AppSearchMatch, order: Int)? in
            let primary = SearchField(document.primaryText, isPrimary: true)
            let secondary = document.secondaryTexts.map { SearchField($0, isPrimary: false) }
            let fields = [primary] + secondary

            var total = 0
            for term in terms {
                guard let best = fields.compactMap({ score(term: term, field: $0) }).max() else {
                    return nil
                }
                total += best
            }

            if primary.normalized == normalizedQuery { total += 500 }
            if document.isRunning { total += 80 }
            if let rank = document.recencyRank { total += max(0, 60 - min(rank, 60)) }
            if document.isBackgroundOnly { total -= 120 }

            return (AppSearchMatch(id: document.id, score: total), document.sourceOrder)
        }
        .sorted {
            if $0.match.score != $1.match.score { return $0.match.score > $1.match.score }
            return $0.order < $1.order
        }
        .map(\.match)
    }

    public static func normalizedSearchTerms(for value: String) -> [String] {
        let field = SearchField(value, isPrimary: true)
        var seen = Set<String>()
        return [
            field.normalized,
            field.transliterated,
            field.compactTransliteration,
            field.initials
        ].filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private struct SearchField {
        let normalized: String
        let transliterated: String
        let compactTransliteration: String
        let initials: String
        let isPrimary: Bool

        init(_ value: String, isPrimary: Bool) {
            self.normalized = normalize(value)
            self.transliterated = transliterate(value)
            self.compactTransliteration = self.transliterated.filter { !$0.isWhitespace }
            self.initials = acronym(from: transliterate(value))
            self.isPrimary = isPrimary
        }
    }

    private static func score(term: String, field: SearchField) -> Int? {
        let values: [(text: String, transliterated: Bool)] = [
            (field.normalized, false),
            (field.transliterated, true),
            (field.compactTransliteration, true),
            (field.initials, true)
        ]

        var best: Int?
        for value in values where !value.text.isEmpty {
            let base: Int
            if value.text == term {
                base = 1_000
            } else if value.text.hasPrefix(term) {
                base = 850
            } else if tokenHasPrefix(value.text, term: term) {
                base = 760
            } else if let range = value.text.range(of: term) {
                let distance = value.text.distance(from: value.text.startIndex, to: range.lowerBound)
                base = 660 - min(distance, 120)
            } else if term.count >= 3, let gapPenalty = subsequenceGapPenalty(term, in: value.text) {
                base = 430 - min(gapPenalty, 180)
            } else {
                continue
            }

            var candidate = base
            if field.isPrimary { candidate += 90 }
            if value.transliterated { candidate -= 35 }
            best = max(best ?? .min, candidate)
        }
        return best
    }

    private static func tokenHasPrefix(_ value: String, term: String) -> Bool {
        value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains {
            $0.hasPrefix(term)
        }
    }

    private static func subsequenceGapPenalty(_ needle: String, in haystack: String) -> Int? {
        let needleChars = Array(needle)
        let haystackChars = Array(haystack)
        var needleIndex = 0
        var firstMatch: Int?
        var lastMatch: Int?

        for (index, character) in haystackChars.enumerated() where needleIndex < needleChars.count {
            if character == needleChars[needleIndex] {
                firstMatch = firstMatch ?? index
                lastMatch = index
                needleIndex += 1
            }
        }
        guard needleIndex == needleChars.count, let firstMatch, let lastMatch else { return nil }
        return (lastMatch - firstMatch + 1) - needleChars.count + firstMatch
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        ).lowercased()
    }

    private static func transliterate(_ value: String) -> String {
        let latin = value.applyingTransform(.toLatin, reverse: false) ?? value
        return normalize(latin)
    }

    private static func acronym(from value: String) -> String {
        value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}
