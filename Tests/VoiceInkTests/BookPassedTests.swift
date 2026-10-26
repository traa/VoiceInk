import AppKit
import Foundation
import Testing
@testable import VoiceInk

/// "Passed" books: the user has dictated at least as many words as the book contains.
@MainActor
struct BookPassedTests {
    private func book(
        wordCount: Int,
        source: DashboardBook.WordCountSource = .estimatedFromPages(pages: 100, provider: .openLibrary),
        estimate: Int? = nil
    ) -> DashboardBook {
        DashboardBook(
            id: "custom.passed-test",
            kind: .custom,
            title: "Passed Test",
            author: nil,
            wordCount: wordCount,
            wordCountSource: source,
            estimatedWordCount: estimate ?? wordCount,
            pageCount: 100,
            openLibraryWorkKey: nil,
            coverID: nil,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - isPassed

    @Test func equalCountsArePassed() {
        #expect(DashboardProgressBenchmark.isPassed(book: book(wordCount: 21_180), totalWords: 21_180))
    }

    @Test func oneWordShortIsNotPassed() {
        #expect(!DashboardProgressBenchmark.isPassed(book: book(wordCount: 21_180), totalWords: 21_179))
    }

    @Test func moreWordsThanTheBookIsPassed() {
        #expect(DashboardProgressBenchmark.isPassed(book: book(wordCount: 21_180), totalWords: 5_000_000))
    }

    @Test func zeroWordsPassesNothing() {
        for builtIn in DashboardProgressBenchmark.builtInBooks {
            #expect(!DashboardProgressBenchmark.isPassed(book: builtIn, totalWords: 0))
        }
        #expect(!DashboardProgressBenchmark.isPassed(book: book(wordCount: 1), totalWords: 0))
    }

    @Test func degenerateZeroWordBookIsNeverPassed() {
        #expect(!DashboardProgressBenchmark.isPassed(book: book(wordCount: 0), totalWords: 0))
        #expect(!DashboardProgressBenchmark.isPassed(book: book(wordCount: 0), totalWords: 10))
    }

    @Test func overrideDecidesNotTheEstimate() {
        // Estimate said 90 000, the user typed the exact 8 000: 10 000 dictated words pass it.
        let overridden = book(wordCount: 8_000, source: .userOverride, estimate: 90_000)
        #expect(DashboardProgressBenchmark.isPassed(book: overridden, totalWords: 10_000))

        // Estimate said 8 000, the user typed the exact 90 000: 10 000 dictated words do not.
        let raised = book(wordCount: 90_000, source: .userOverride, estimate: 8_000)
        #expect(!DashboardProgressBenchmark.isPassed(book: raised, totalWords: 10_000))
    }

    @Test func estimateIsUsedWhileNothingIsOverridden() {
        let estimated = book(wordCount: 24_750)
        #expect(DashboardProgressBenchmark.isPassed(book: estimated, totalWords: 24_750))
        #expect(!DashboardProgressBenchmark.isPassed(book: estimated, totalWords: 24_749))
    }

    @Test func realisticTotalsPassOnlyTheSmallerBuiltIns() {
        let passed = DashboardProgressBenchmark.builtInBooks
            .filter { DashboardProgressBenchmark.isPassed(book: $0, totalWords: 47_094) }
            .map(\.id)
        #expect(passed == ["builtin.metamorphosis", "builtin.animal-farm", "builtin.great-gatsby"])
    }

    // MARK: - Menu thumbnail

    private func pixel(_ image: NSImage, x: Int, y: Int) throws -> NSColor {
        let scale = 4
        let rep = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width) * scale,
                pixelsHigh: Int(image.size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.colorAt(x: x, y: y)).usingColorSpace(.deviceRGB)!
    }

    @Test func thumbnailStaysSmallAndNonTemplateWithAndWithoutBadge() {
        let tint = RGB(red: 0.5, green: 0.2, blue: 0.2)
        for passed in [false, true] {
            let image = BookMenuThumbnail.make(from: nil, tint: tint, isPassed: passed)
            #expect(image.size == NSSize(width: 16, height: 22))
            #expect(!image.isTemplate)
        }
    }

    @Test func passedThumbnailDrawsAGreenBadgeInTheBottomRightCorner() throws {
        let tint = RGB(red: 0.5, green: 0.2, blue: 0.2)
        let plain = BookMenuThumbnail.make(from: nil, tint: tint, isPassed: false)
        let badged = BookMenuThumbnail.make(from: nil, tint: tint, isPassed: true)

        // Bottom-right area of the 16x22 image, in the 4x raster (origin bottom-left in the bitmap rep API
        // is top-left for colorAt, so "bottom" is a large y).
        let badgePixel = try pixel(badged, x: 16 * 4 - 14, y: 22 * 4 - 14)
        let plainPixel = try pixel(plain, x: 16 * 4 - 14, y: 22 * 4 - 14)
        #expect(badgePixel.greenComponent > badgePixel.redComponent + 0.2)
        #expect(badgePixel.greenComponent > badgePixel.blueComponent + 0.2)
        // The cover itself (top-left) is untouched by the badge.
        let coverPlain = try pixel(plain, x: 8, y: 8)
        let coverBadged = try pixel(badged, x: 8, y: 8)
        #expect(abs(coverPlain.redComponent - coverBadged.redComponent) < 0.02)
        #expect(plainPixel.greenComponent < plainPixel.redComponent)
    }
}
