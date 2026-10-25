import Foundation
import Testing
@testable import VoiceInk

struct BookEstimationTests {
    private func customBook(
        wordCount: Int,
        source: DashboardBook.WordCountSource,
        pageCount: Int?
    ) -> DashboardBook {
        DashboardBook(
            id: "custom.test",
            kind: .custom,
            title: "Test Book",
            author: "Author",
            wordCount: wordCount,
            wordCountSource: source,
            estimatedWordCount: nil,
            pageCount: pageCount,
            openLibraryWorkKey: nil,
            coverID: nil,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func wordsPerPageIs275() {
        #expect(DashboardBookEstimation.wordsPerPage == 275)
        #expect(DashboardBookEstimation.words(forPages: 328) == 90_200)
    }

    @Test func estimatedPagesUsePageCount() {
        let book = customBook(
            wordCount: 90_200,
            source: .estimatedFromPages(pages: 328, provider: .openLibrary),
            pageCount: 328
        )
        #expect(book.pagesEquivalent == 328)
    }

    @Test func overrideDerivesPagesFromWords() {
        let book = customBook(wordCount: 82_500, source: .userOverride, pageCount: 328)
        #expect(book.pagesEquivalent == 300)
    }

    @Test func builtInPagesAreWordsOver275() throws {
        let metamorphosis = try #require(
            DashboardProgressBenchmark.builtInBooks.first { $0.id == "builtin.metamorphosis" }
        )
        #expect(metamorphosis.wordCount == 21_180)
        #expect(metamorphosis.pagesEquivalent == 77)
    }

    @Test func pagesEquivalentHasFloorOfTwo() {
        let book = customBook(wordCount: 100, source: .userOverride, pageCount: nil)
        #expect(book.pagesEquivalent == 2)
    }

    @Test func isEstimateOnlyForEstimatedSource() {
        let estimated = customBook(
            wordCount: 90_200,
            source: .estimatedFromPages(pages: 328, provider: .googleBooks),
            pageCount: 328
        )
        let overridden = customBook(wordCount: 82_500, source: .userOverride, pageCount: 328)
        #expect(estimated.isEstimate)
        #expect(!overridden.isEstimate)
        #expect(DashboardProgressBenchmark.builtInBooks.allSatisfy { !$0.isEstimate })
    }
}
