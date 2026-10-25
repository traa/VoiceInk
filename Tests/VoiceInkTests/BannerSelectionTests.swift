import AppKit
import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct BannerSelectionTests {
    private func book(
        id: String = "custom.banner-test",
        wordCount: Int = 90_200,
        coverID: Int? = 42,
        coverTint: RGB? = nil,
        customBannerFile: String? = nil
    ) -> DashboardBook {
        DashboardBook(
            id: id,
            kind: .custom,
            title: "Banner Test",
            author: nil,
            wordCount: wordCount,
            wordCountSource: .estimatedFromPages(pages: 328, provider: .openLibrary),
            estimatedWordCount: wordCount,
            pageCount: 328,
            openLibraryWorkKey: nil,
            coverID: coverID,
            coverTint: coverTint,
            customBannerFile: customBannerFile,
            addedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func jpegData() throws -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .jpeg, properties: [:]))
    }

    // MARK: - Source precedence

    @Test func customBannerBeatsCover() {
        let source = BookArtSource.resolve(
            book: book(customBannerFile: "custom.banner-test.jpg"),
            customBannerExists: true,
            coverCached: true
        )
        #expect(source.kind == .customBanner)
    }

    @Test func missingBannerFileFallsBackToCover() {
        let source = BookArtSource.resolve(
            book: book(customBannerFile: "custom.banner-test.jpg"),
            customBannerExists: false,
            coverCached: true
        )
        #expect(source.kind == .cover)
    }

    @Test func noCoverNoBannerUsesDefaultBanner() {
        #expect(BookArtSource.resolve(book: book(coverID: nil), customBannerExists: false, coverCached: false).kind == .defaultBanner)
        #expect(BookArtSource.resolve(book: book(), customBannerExists: false, coverCached: false).kind == .defaultBanner)
    }

    @Test func noBookUsesDefaultBanner() {
        #expect(BookArtSource.resolve(book: nil, customBannerExists: false, coverCached: false).kind == .defaultBanner)
    }

    @Test func everyBuiltInWithoutArtUsesDefaultBanner() {
        for builtIn in DashboardProgressBenchmark.builtInBooks {
            #expect(BookArtSource.resolve(book: builtIn, customBannerExists: false, coverCached: false).kind == .defaultBanner)
        }
    }

    @Test func builtInWithCustomBannerUsesIt() {
        var builtIn = DashboardProgressBenchmark.builtInBooks[0]
        builtIn.customBannerFile = "\(builtIn.id).jpg"
        #expect(BookArtSource.resolve(book: builtIn, customBannerExists: true, coverCached: false).kind == .customBanner)
    }

    @Test func coverIDWithoutCachedCoverUsesDefaultBanner() {
        #expect(BookArtSource.resolve(book: book(coverID: 42), customBannerExists: false, coverCached: false).kind == .defaultBanner)
    }

    @Test func removingBannerFallsBackToCover() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BannerSelectionTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DashboardBookStore(
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true)
        )
        store.add(book())
        try store.setBanner(try jpegData(), forBookID: "custom.banner-test")

        let withBanner = try #require(store.customBooks.first)
        #expect(
            BookArtSource.resolve(
                book: withBanner,
                customBannerExists: store.bannerImage(for: withBanner) != nil,
                coverCached: true
            ).kind == .customBanner
        )

        store.removeBanner(forBookID: "custom.banner-test")
        let removed = try #require(store.customBooks.first)
        #expect(
            BookArtSource.resolve(
                book: removed,
                customBannerExists: store.bannerImage(for: removed) != nil,
                coverCached: true
            ).kind == .cover
        )
        store.waitForPendingWrites()
    }

    // MARK: - Blur treatment

    @Test func coverAlwaysBlurred() {
        #expect(BannerTreatment.coverBlurRadius >= 8 && BannerTreatment.coverBlurRadius <= 12)
        for pixelWidth in [180, 500, 1600, 4000] {
            #expect(
                BannerTreatment.blurRadius(
                    isCustomBanner: false,
                    imagePixelWidth: pixelWidth,
                    artWidth: 400,
                    backingScale: 2
                ) == BannerTreatment.coverBlurRadius
            )
        }
    }

    @Test func highResCustomBannerIsSharp() {
        #expect(
            BannerTreatment.blurRadius(isCustomBanner: true, imagePixelWidth: 1600, artWidth: 400, backingScale: 2) == 0
        )
        #expect(
            BannerTreatment.blurRadius(isCustomBanner: true, imagePixelWidth: 1200, artWidth: 400, backingScale: 2) == 0
        )
    }

    @Test func lowResCustomBannerGetsLightBlur() {
        #expect(BannerTreatment.lowResCustomBlurRadius >= 3 && BannerTreatment.lowResCustomBlurRadius <= 5)
        #expect(
            BannerTreatment.blurRadius(isCustomBanner: true, imagePixelWidth: 500, artWidth: 400, backingScale: 2)
                == BannerTreatment.lowResCustomBlurRadius
        )
        #expect(
            BannerTreatment.blurRadius(isCustomBanner: true, imagePixelWidth: 1199, artWidth: 400, backingScale: 2)
                == BannerTreatment.lowResCustomBlurRadius
        )
    }

    @Test func layoutConstantsMatchSpec() {
        #expect(BannerTreatment.artWidthFraction == 0.55)
        #expect(BannerTreatment.minimumCardWidth == 620)
    }

    // MARK: - Art plan (locked state, spec §8.6 item 5)

    @Test func unlockedWideTierDrawsArtAndBookWithoutWash() {
        let plan = BannerTreatment.artPlan(isLocked: false, hasBook: true, hasArtImage: true, tierShowsBook: true)
        #expect(plan == .init(drawsArt: true, drawsBook: true, artIsLocked: false, washOpacity: 0))
    }

    @Test func lockedKeepsArtButHidesBook() {
        let plan = BannerTreatment.artPlan(isLocked: true, hasBook: true, hasArtImage: true, tierShowsBook: true)
        #expect(plan.drawsArt)
        #expect(!plan.drawsBook)
        #expect(plan.artIsLocked)
        #expect(plan.washOpacity == BannerTreatment.overlapWashOpacity)
    }

    @Test func lockedWithoutArtDrawsNothing() {
        let plan = BannerTreatment.artPlan(isLocked: true, hasBook: true, hasArtImage: false, tierShowsBook: true)
        #expect(!plan.drawsArt && !plan.drawsBook)
    }

    @Test func narrowTierKeepsArtDropsBook() {
        let plan = BannerTreatment.artPlan(isLocked: false, hasBook: true, hasArtImage: true, tierShowsBook: false)
        #expect(plan.drawsArt && !plan.drawsBook && !plan.artIsLocked)
        #expect(plan.washOpacity == BannerTreatment.overlapWashOpacity)
    }

    @Test func noBookNeverDrawsBook() {
        let plan = BannerTreatment.artPlan(isLocked: false, hasBook: false, hasArtImage: false, tierShowsBook: true)
        #expect(!plan.drawsBook && !plan.drawsArt)
    }

    @Test func lockedTreatmentConstantsMatchSpec() {
        #expect(BannerTreatment.lockedExtraBlurRadius == 2.5)
        #expect(BannerTreatment.lockedSaturation == 0.78)
        #expect(BannerTreatment.lockedWhiteOverlayOpacity == 0.32)
    }

    // MARK: - Boards tint

    @Test func boardsTintFollowsActiveSource() {
        let tint = RGB(red: 0.5, green: 0.25, blue: 1.0)
        #expect(BannerTreatment.boardsTint(for: book(coverTint: tint)) == ImageTint.boardsTint(from: tint))
        #expect(
            BannerTreatment.boardsTint(for: book(id: "custom.no-tint", coverTint: nil))
                == ImageTint.paletteTint(forBookID: "custom.no-tint")
        )
    }

    // MARK: - Open book ratio vs. subtitle wording

    @Test func openBookRatioClampsWhenRepeatsNotAllowed() {
        let b = book(wordCount: 50_000)
        #expect(DashboardProgressBenchmark.openBookRatio(words: 150_000, book: b, allowsRepeats: false) == 1)
        #expect(DashboardProgressBenchmark.openBookRatio(words: 150_000, book: b, allowsRepeats: true) == 3)
        #expect(DashboardProgressBenchmark.openBookRatio(words: 25_000, book: b, allowsRepeats: false) == 0.5)
        #expect(DashboardProgressBenchmark.openBookRatio(words: 25_000, book: b, allowsRepeats: true) == 0.5)
        #expect(DashboardProgressBenchmark.openBookRatio(words: 10, book: book(wordCount: 0), allowsRepeats: true) == 0)
    }

    /// The caption shows "N×" exactly when the subtitle reports a repeat, with the same N.
    @Test func captionMultipleMatchesSubtitleWording() {
        let b = book(wordCount: 47_094)
        for words in [0, 20_000, 47_094, 94_187, 94_188, 100_000, 200_000, 1_000_000] {
            for allowsRepeats in [false, true] {
                let ratio = DashboardProgressBenchmark.openBookRatio(words: words, book: b, allowsRepeats: allowsRepeats)
                let equivalence = DashboardProgressBenchmark.equivalence(for: words, book: b, allowsRepeats: allowsRepeats)
                let captionMultiple = ratio >= 2 ? Int(ratio.rounded(.down)) : nil
                if case .repeated(_, let count) = equivalence {
                    #expect(captionMultiple == count)
                } else {
                    #expect(captionMultiple == nil)
                }
            }
        }
    }

    @Test func multipleWordingSaysTwiceThenTimes() {
        #expect(DashboardProgressBenchmark.multipleText(2) == String(localized: "twice"))
        #expect(
            DashboardProgressBenchmark.multipleText(3)
                == String(localized: "\(Formatters.formattedNumber(3)) times")
        )
    }
}
