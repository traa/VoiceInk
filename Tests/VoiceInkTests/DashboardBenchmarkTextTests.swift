import Foundation
import Testing
@testable import VoiceInk

struct DashboardBenchmarkTextTests {
    private func estimatedBook() -> DashboardBook {
        DashboardBook(
            id: "custom.estimated",
            kind: .custom,
            title: "My Raw Title",
            author: nil,
            wordCount: 90_200,
            wordCountSource: .estimatedFromPages(pages: 328, provider: .openLibrary),
            estimatedWordCount: 90_200,
            pageCount: 328,
            openLibraryWorkKey: nil,
            coverID: nil,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func estimatedCustomBookReportsRemainingAsEstimate() {
        let equivalence = DashboardProgressBenchmark.equivalence(
            for: 10_000,
            book: estimatedBook(),
            allowsRepeats: true
        )
        #expect(equivalence == .remaining(words: 80_200, title: "My Raw Title", isEstimate: true))
    }

    @Test func customBookUsesRawTitleWhenMatched() {
        let book = estimatedBook()
        #expect(book.displayTitle == "My Raw Title")
        #expect(
            DashboardProgressBenchmark.equivalence(for: 90_200, book: book, allowsRepeats: false)
                == .matched(title: "My Raw Title")
        )
        #expect(
            DashboardProgressBenchmark.equivalence(for: 270_600, book: book, allowsRepeats: false)
                == .matched(title: "My Raw Title")
        )
        #expect(
            DashboardProgressBenchmark.equivalence(for: 270_600, book: book, allowsRepeats: true)
                == .repeated(title: "My Raw Title", count: 3)
        )
    }
}
