import Foundation
import Testing
@testable import VoiceInk

struct DashboardBookResolutionTests {
    private typealias Benchmark = DashboardProgressBenchmark

    private var builtIns: [DashboardBook] { Benchmark.builtInBooks }

    private func book(_ id: String) -> DashboardBook {
        builtIns.first { $0.id == id }!
    }

    private func customBook(id: String = "custom.test", wordCount: Int) -> DashboardBook {
        DashboardBook(
            id: id,
            kind: .custom,
            title: "Custom Epic",
            author: nil,
            wordCount: wordCount,
            wordCountSource: .estimatedFromPages(pages: 100, provider: .openLibrary),
            estimatedWordCount: wordCount,
            pageCount: 100,
            openLibraryWorkKey: nil,
            coverID: nil,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func resolveAndEquivalence(
        words: Int,
        visible: [DashboardBook]? = nil,
        selectedID: String? = nil
    ) -> (ResolvedBook?, Benchmark.Equivalence) {
        let resolved = Benchmark.resolveBook(words: words, visible: visible ?? builtIns, selectedID: selectedID)
        let equivalence = Benchmark.equivalence(
            for: words,
            book: resolved?.book,
            allowsRepeats: resolved?.allowsRepeats ?? false
        )
        return (resolved, equivalence)
    }

    @Test func builtInIDsAreUniqueAndStable() {
        let ids = builtIns.map(\.id)
        #expect(ids == [
            "builtin.metamorphosis",
            "builtin.animal-farm",
            "builtin.great-gatsby",
            "builtin.iliad",
            "builtin.odyssey",
            "builtin.iliad-odyssey",
            "builtin.war-and-peace",
        ])
        #expect(Set(ids).count == ids.count)
        #expect(builtIns.map(\.wordCount) == [21_180, 29_966, 47_094, 114_715, 121_365, 236_080, 700_000])
        #expect(builtIns.allSatisfy { $0.kind == .builtIn && $0.wordCountSource == .curated && $0.pageCount == nil })
        #expect(builtIns.map(\.author) == ["Kafka", "Orwell", "Fitzgerald", "Homer", "Homer", "Homer", "Tolstoy"])
    }

    @Test func zeroWordsResolvesFirstBookWithoutRepeats() {
        let (resolved, equivalence) = resolveAndEquivalence(words: 0)
        #expect(resolved?.book.id == "builtin.metamorphosis")
        #expect(resolved?.allowsRepeats == false)
        #expect(equivalence == .remaining(
            words: 21_180,
            title: book("builtin.metamorphosis").displayTitle,
            isEstimate: false
        ))
    }

    @Test func betweenMilestonesResolvesLargestPassed() {
        let (low, _) = resolveAndEquivalence(words: 25_000)
        #expect(low?.book.id == "builtin.metamorphosis")

        let (resolved, equivalence) = resolveAndEquivalence(words: 100_000)
        #expect(resolved?.book.id == "builtin.great-gatsby")
        #expect(resolved?.allowsRepeats == false)
        #expect(equivalence == .matched(title: book("builtin.great-gatsby").displayTitle))
    }

    @Test func atLargestResolvesLargestWithRepeats() {
        let title = book("builtin.war-and-peace").displayTitle

        let (resolved, equivalence) = resolveAndEquivalence(words: 700_000)
        #expect(resolved?.book.id == "builtin.war-and-peace")
        #expect(resolved?.allowsRepeats == true)
        #expect(equivalence == .matched(title: title))

        let (_, doubled) = resolveAndEquivalence(words: 1_400_000)
        #expect(doubled == .repeated(title: title, count: 2))
    }

    @Test func automaticGeneralisesOverVisibleSet() {
        let custom = customBook(wordCount: 900_000)
        let visible = builtIns.filter { $0.id != "builtin.war-and-peace" } + [custom]

        let (below, belowEquivalence) = resolveAndEquivalence(words: 800_000, visible: visible)
        #expect(below?.book.id == "builtin.iliad-odyssey")
        #expect(below?.allowsRepeats == false)
        #expect(belowEquivalence == .matched(title: book("builtin.iliad-odyssey").displayTitle))

        let (at, _) = resolveAndEquivalence(words: 900_000, visible: visible)
        #expect(at?.book.id == custom.id)
        #expect(at?.allowsRepeats == true)
    }

    @Test func tiesBreakByID() {
        let b = customBook(id: "custom.b", wordCount: 50_000)
        let a = customBook(id: "custom.a", wordCount: 50_000)

        let belowTie = Benchmark.resolveBook(words: 10, visible: [b, a], selectedID: nil)
        #expect(belowTie?.book.id == "custom.a")
        #expect(belowTie?.allowsRepeats == false)

        let atTie = Benchmark.resolveBook(words: 50_000, visible: [b, a], selectedID: nil)
        #expect(atTie?.book.id == "custom.b")
        #expect(atTie?.allowsRepeats == true)
    }

    @Test func explicitSelectionWinsAndAllowsRepeats() {
        let (resolved, equivalence) = resolveAndEquivalence(words: 100_000, selectedID: "builtin.metamorphosis")
        #expect(resolved?.book.id == "builtin.metamorphosis")
        #expect(resolved?.allowsRepeats == true)
        #expect(equivalence == .repeated(title: book("builtin.metamorphosis").displayTitle, count: 4))
        #expect(!Benchmark.isSelectionStale(selectedID: "builtin.metamorphosis", visible: builtIns))
    }

    @Test func staleSelectionIsDetected() {
        let visible = builtIns.filter { $0.id != "builtin.animal-farm" }
        #expect(Benchmark.isSelectionStale(selectedID: "builtin.animal-farm", visible: visible))

        let fallback = Benchmark.resolveBook(words: 35_000, visible: visible, selectedID: "builtin.animal-farm")
        let automatic = Benchmark.resolveBook(words: 35_000, visible: visible, selectedID: nil)
        #expect(fallback == automatic)
        #expect(fallback?.book.id == "builtin.metamorphosis")
    }

    @Test func emptySelectionIsAutomaticAndNeverStale() {
        #expect(!Benchmark.isSelectionStale(selectedID: nil, visible: builtIns))
        #expect(!Benchmark.isSelectionStale(selectedID: "", visible: builtIns))
        #expect(!Benchmark.isSelectionStale(selectedID: "", visible: []))

        let empty = Benchmark.resolveBook(words: 100_000, visible: builtIns, selectedID: "")
        let automatic = Benchmark.resolveBook(words: 100_000, visible: builtIns, selectedID: nil)
        #expect(empty == automatic)
        #expect(empty?.allowsRepeats == false)
    }

    @Test func emptyVisibleResolvesNil() {
        #expect(Benchmark.resolveBook(words: 5, visible: [], selectedID: nil) == nil)
        #expect(Benchmark.resolveBook(words: 5, visible: [], selectedID: "builtin.iliad") == nil)
        #expect(Benchmark.equivalence(for: 5, book: nil, allowsRepeats: false) == .none)
    }

    @Test func progressIsClamped() {
        let small = customBook(wordCount: 600)
        #expect(Benchmark.progress(words: 0, book: small) == 0)
        #expect(Benchmark.progress(words: 100, book: small) == 1.0 / 6.0)
        #expect(Benchmark.progress(words: 1_200, book: small) == 1.0)
    }
}
