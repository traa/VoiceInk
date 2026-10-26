import AppKit
import SwiftUI
import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct ManageBooksViewModelTests {
    private final class Box {
        var hidden = HiddenBookIDs()
        var selectedID = ""
    }

    private struct Env {
        let root: URL
        let store: DashboardBookStore
        let covers: BookCoverCache
        let box: Box
        let viewModel: ManageBooksViewModel
    }

    private func makeEnv(selectedID: String = "") throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManageBooksViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = DashboardBookStore(
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true)
        )
        let covers = BookCoverCache(
            directory: root.appendingPathComponent("BookCovers", isDirectory: true),
            session: StubURLProtocol.makeSession { _ in throw URLError(.notConnectedToInternet) }
        )
        let box = Box()
        box.selectedID = selectedID
        let viewModel = ManageBooksViewModel(
            store: store,
            hidden: Binding(get: { box.hidden }, set: { box.hidden = $0 }),
            selectedID: Binding(get: { box.selectedID }, set: { box.selectedID = $0 }),
            covers: covers
        )
        return Env(root: root, store: store, covers: covers, box: box, viewModel: viewModel)
    }

    private func cleanup(_ env: Env) {
        env.store.waitForPendingWrites()
        try? FileManager.default.removeItem(at: env.root)
    }

    private func customBook(
        source: DashboardBook.WordCountSource = .estimatedFromPages(pages: 328, provider: .openLibrary),
        estimated: Int? = 90_200,
        wordCount: Int = 90_200
    ) -> DashboardBook {
        DashboardBook(
            id: "custom.\(UUID().uuidString)",
            kind: .custom,
            title: "Test Book",
            author: "Author",
            wordCount: wordCount,
            wordCountSource: source,
            estimatedWordCount: estimated,
            pageCount: 328,
            openLibraryWorkKey: "/works/OL1W",
            coverID: 42,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func builtIn(_ id: String = "builtin.iliad") throws -> DashboardBook {
        try #require(DashboardProgressBenchmark.builtInBooks.first { $0.id == id })
    }

    private func jpegData() throws -> Data {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .jpeg, properties: [:]))
    }

    private func current(_ env: Env, _ book: DashboardBook) throws -> DashboardBook {
        try #require(env.store.customBooks.first { $0.id == book.id })
    }

    @Test func hidingSelectedBuiltInClearsSelection() throws {
        let env = try makeEnv(selectedID: "builtin.iliad")
        defer { cleanup(env) }
        env.viewModel.toggleHidden(try builtIn("builtin.iliad"))
        #expect(env.box.hidden.ids.contains("builtin.iliad"))
        #expect(env.box.selectedID == "")
    }

    @Test func hidingUnselectedBuiltInKeepsSelection() throws {
        let env = try makeEnv(selectedID: "builtin.odyssey")
        defer { cleanup(env) }
        env.viewModel.toggleHidden(try builtIn("builtin.iliad"))
        #expect(env.box.hidden.ids == ["builtin.iliad"])
        #expect(env.box.selectedID == "builtin.odyssey")
    }

    @Test func showingRemovesFromHidden() throws {
        let env = try makeEnv()
        defer { cleanup(env) }
        env.box.hidden = HiddenBookIDs(ids: ["builtin.iliad", "builtin.odyssey"])
        env.viewModel.toggleHidden(try builtIn("builtin.iliad"))
        #expect(env.box.hidden.ids == ["builtin.odyssey"])
    }

    @Test func toggleHiddenIgnoresCustomBooks() throws {
        let env = try makeEnv()
        defer { cleanup(env) }
        let book = customBook()
        env.store.add(book)
        env.viewModel.toggleHidden(book)
        #expect(env.box.hidden.ids.isEmpty)
    }

    @Test func deletingSelectedCustomBookClearsSelectionAndRemovesBanner() throws {
        let book = customBook()
        let env = try makeEnv(selectedID: book.id)
        defer { cleanup(env) }
        env.store.add(book)
        try env.viewModel.applyBanner(try jpegData(), to: book)
        let bannerFile = try #require(try current(env, book).customBannerFile)
        let bannerURL = env.root.appendingPathComponent("BookBanners").appendingPathComponent(bannerFile)
        #expect(FileManager.default.fileExists(atPath: bannerURL.path))

        env.viewModel.delete(book)

        #expect(env.store.customBooks.isEmpty)
        #expect(env.box.selectedID == "")
        #expect(!FileManager.default.fileExists(atPath: bannerURL.path))
    }

    @Test func deletingUnselectedCustomBookKeepsSelection() throws {
        let book = customBook()
        let env = try makeEnv(selectedID: "builtin.iliad")
        defer { cleanup(env) }
        env.store.add(book)
        env.viewModel.delete(book)
        #expect(env.store.customBooks.isEmpty)
        #expect(env.box.selectedID == "builtin.iliad")
    }

    @Test func deleteRemovesCoverFileAndMemoryEntry() throws {
        let book = customBook()
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)
        let coverID = try #require(book.coverID)
        let coverURL = env.covers.fileURL(for: coverID)
        try FileManager.default.createDirectory(
            at: coverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpegData().write(to: coverURL)
        #expect(env.covers.cachedImage(for: coverID) != nil)

        env.viewModel.delete(book)

        #expect(!FileManager.default.fileExists(atPath: coverURL.path))
        #expect(env.covers.cachedImage(for: coverID) == nil)
    }

    @Test func deleteOnlyAppliesToCustomBooks() throws {
        let env = try makeEnv(selectedID: "builtin.iliad")
        defer { cleanup(env) }
        env.viewModel.delete(try builtIn("builtin.iliad"))
        #expect(env.box.selectedID == "builtin.iliad")
        #expect(env.store.allBooks(hiddenBuiltIns: []).contains { $0.id == "builtin.iliad" })
    }

    @Test func saveWordCountSetsUserOverrideAndKeepsEstimate() throws {
        let book = customBook()
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)

        #expect(env.viewModel.saveWordCount("82500", for: book))

        let saved = try current(env, book)
        #expect(saved.wordCount == 82_500)
        #expect(saved.wordCountSource == .userOverride)
        #expect(saved.estimatedWordCount == 90_200)
        #expect(saved.pageCount == 328)
    }

    @Test func saveWordCountRejectsGarbage() throws {
        let book = customBook()
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)

        for text in ["", "0", "-1", "1.5", "abc"] {
            #expect(!env.viewModel.saveWordCount(text, for: book), "\(text)")
        }
        #expect(try current(env, book) == book)
    }

    @Test func saveWordCountNotAllowedForBuiltIns() throws {
        let env = try makeEnv()
        defer { cleanup(env) }
        #expect(!env.viewModel.saveWordCount("1000", for: try builtIn()))
        #expect(env.store.customBooks.isEmpty)
    }

    @Test func resetToEstimateRestoresWordCountAndSource() throws {
        let book = customBook()
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)
        #expect(env.viewModel.saveWordCount("82500", for: book))

        let overridden = try current(env, book)
        #expect(env.viewModel.canResetToEstimate(overridden))
        env.viewModel.resetToEstimate(overridden)

        let reset = try current(env, book)
        #expect(reset.wordCount == 90_200)
        #expect(reset.wordCountSource == .estimatedFromPages(pages: 328, provider: .openLibrary))
        #expect(reset.estimatedWordCount == 90_200)
        #expect(!env.viewModel.canResetToEstimate(reset))
    }

    @Test func resetToEstimateUnavailableWithoutEstimate() throws {
        let book = customBook(source: .userOverride, estimated: nil, wordCount: 50_000)
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)

        #expect(!env.viewModel.canResetToEstimate(book))
        env.viewModel.resetToEstimate(book)
        #expect(try current(env, book) == book)
    }

    @Test func builtInBannerCanBeSetAndRemoved() throws {
        let iliad = try builtIn()
        let env = try makeEnv()
        defer { cleanup(env) }

        try env.viewModel.applyBanner(try jpegData(), to: iliad)
        #expect(env.store.builtInArt[iliad.id]?.customBannerFile != nil)
        let merged = try #require(env.store.allBooks(hiddenBuiltIns: []).first { $0.id == iliad.id })
        #expect(merged.customBannerFile != nil)

        env.viewModel.removeBanner(from: merged)
        #expect(env.store.builtInArt[iliad.id]?.customBannerFile == nil)
        let cleared = try #require(env.store.allBooks(hiddenBuiltIns: []).first { $0.id == iliad.id })
        #expect(cleared.customBannerFile == nil)
    }

    @Test func customBannerCanBeSetAndRemoved() throws {
        let book = customBook()
        let env = try makeEnv()
        defer { cleanup(env) }
        env.store.add(book)

        try env.viewModel.applyBanner(try jpegData(), to: book)
        #expect(try current(env, book).customBannerFile != nil)
        env.viewModel.removeBanner(from: book)
        #expect(try current(env, book).customBannerFile == nil)
    }

    @Test func sourceLabels() throws {
        let env = try makeEnv()
        defer { cleanup(env) }
        let estimated = customBook()
        let override = customBook(source: .userOverride)

        #expect(env.viewModel.sourceLabel(for: estimated) == String(localized: "estimated from \(328) pages"))
        #expect(env.viewModel.sourceLabel(for: override) == String(localized: "exact (you entered)"))
        #expect(env.viewModel.sourceLabel(for: try builtIn()) == String(localized: "curated"))
    }
}
