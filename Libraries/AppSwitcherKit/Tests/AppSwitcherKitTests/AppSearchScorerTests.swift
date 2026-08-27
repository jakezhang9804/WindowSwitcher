import Testing
@testable import AppSwitcherKit

@Suite("Application search scoring")
struct AppSearchScorerTests {
    @Test("Exact app names outrank weak running-window matches")
    func exactBeatsWeakRunningMatch() {
        let documents = [
            AppSearchDocument(id: "window", primaryText: "Notes about Slack", isRunning: true, recencyRank: 0),
            AppSearchDocument(id: "app", primaryText: "Slack", secondaryTexts: ["com.tinyspeck.slackmacgap"])
        ]

        let matches = AppSearchScorer.rankedMatches(query: "Slack", documents: documents)
        #expect(matches.map(\.id) == ["app", "window"])
    }

    @Test("Bundle IDs and multiple AND terms are searchable")
    func bundleIDAndMultipleTerms() {
        let documents = [
            AppSearchDocument(
                id: "cursor",
                primaryText: "Cursor",
                secondaryTexts: ["com.todesktop.230313mzl4w4u92", "Project Alpha"]
            ),
            AppSearchDocument(id: "other", primaryText: "Alpha")
        ]

        #expect(AppSearchScorer.rankedMatches(query: "todesktop", documents: documents).map(\.id) == ["cursor"])
        #expect(AppSearchScorer.rankedMatches(query: "cursor alpha", documents: documents).map(\.id) == ["cursor"])
    }

    @Test("Fuzzy subsequences, Pinyin, and Pinyin initials match")
    func fuzzyAndPinyin() {
        let documents = [
            AppSearchDocument(id: "slack", primaryText: "Slack"),
            AppSearchDocument(id: "wechat", primaryText: "微信")
        ]

        #expect(AppSearchScorer.rankedMatches(query: "slak", documents: documents).first?.id == "slack")
        #expect(AppSearchScorer.rankedMatches(query: "wei xin", documents: documents).first?.id == "wechat")
        #expect(AppSearchScorer.rankedMatches(query: "weixin", documents: documents).first?.id == "wechat")
        #expect(AppSearchScorer.rankedMatches(query: "wx", documents: documents).first?.id == "wechat")
    }

    @Test("Background utilities rank below equally matching normal apps")
    func backgroundPenalty() {
        let documents = [
            AppSearchDocument(id: "agent", primaryText: "Helper", isBackgroundOnly: true, sourceOrder: 0),
            AppSearchDocument(id: "normal", primaryText: "Helper", isBackgroundOnly: false, sourceOrder: 1)
        ]

        #expect(AppSearchScorer.rankedMatches(query: "Helper", documents: documents).map(\.id) == ["normal", "agent"])
    }

    @Test("Queries shorter than three characters do not use noisy fuzzy matching")
    func shortQueriesDoNotFuzzyMatch() {
        let documents = [AppSearchDocument(id: "calendar", primaryText: "Calendar")]
        #expect(AppSearchScorer.rankedMatches(query: "cl", documents: documents).isEmpty)
    }
}
