import AppKit
import Foundation
import Testing
@testable import VoiceInk

@MainActor
struct DashboardBookStoreTests {
    private struct Env {
        let root: URL
        let fileURL: URL
        let bannersDirectory: URL
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardBookStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Env(
            root: root,
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true)
        )
    }

    private func makeStore(_ env: Env) -> DashboardBookStore {
        DashboardBookStore(fileURL: env.fileURL, bannersDirectory: env.bannersDirectory)
    }

    private func customBook(id: String = "custom.\(UUID().uuidString)", workKey: String? = nil) -> DashboardBook {
        DashboardBook(
            id: id,
            kind: .custom,
            title: "Test Book",
            author: "Author",
            wordCount: 90_200,
            wordCountSource: .estimatedFromPages(pages: 328, provider: .openLibrary),
            estimatedWordCount: 90_200,
            pageCount: 328,
            openLibraryWorkKey: workKey,
            coverID: 42,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private func jpegData(color: NSColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)) throws -> Data {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .jpeg, properties: [:]))
    }

    /// Drains the store's serial write queue.
    private func flush(_ store: DashboardBookStore) {
        store.waitForPendingWrites()
    }

    @Test func roundTripsCustomBooks() throws {
        let env = try makeEnv()
        let book = customBook()
        let store = makeStore(env)
        store.add(book)
        flush(store)

        let reloaded = makeStore(env)
        #expect(reloaded.customBooks == [book])
    }

    @Test func decodesOlderFileWithoutOptionalFields() throws {
        let env = try makeEnv()
        let json = """
        {"version":1,"books":[{"id":"custom.old","kind":"custom","title":"Old","wordCount":50000,
        "wordCountSource":{"userOverride":{}},"addedAt":0}]}
        """
        try json.write(to: env.fileURL, atomically: true, encoding: .utf8)
        let store = makeStore(env)
        #expect(store.customBooks.count == 1)
        #expect(store.customBooks[0].id == "custom.old")
        #expect(store.customBooks[0].coverTint == nil)
        #expect(store.customBooks[0].customBannerFile == nil)
        #expect(store.builtInArt.isEmpty)
    }

    @Test func corruptFileIsRenamedAndStoreStartsEmpty() throws {
        let env = try makeEnv()
        try "{not json".write(to: env.fileURL, atomically: true, encoding: .utf8)
        let store = makeStore(env)
        #expect(store.customBooks.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.fileURL.path))
        let siblings = try FileManager.default.contentsOfDirectory(atPath: env.root.path)
        let corrupt = siblings.filter { $0.hasPrefix("dashboard-books.corrupt-") && $0.hasSuffix(".json") }
        #expect(corrupt.count == 1)

        store.add(customBook())
        flush(store)
        #expect(FileManager.default.fileExists(atPath: env.fileURL.path))
    }

    @Test func deleteRemovesBannerFile() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook()
        store.add(book)
        try store.setBanner(try jpegData(), forBookID: book.id)
        let file = env.bannersDirectory.appendingPathComponent("\(book.id).jpg")
        #expect(FileManager.default.fileExists(atPath: file.path))
        store.delete(id: book.id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.customBooks.isEmpty)
    }

    @Test func setBannerWritesFileAndSetsFileName() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook()
        store.add(book)
        try store.setBanner(try jpegData(), forBookID: book.id)
        let updated = try #require(store.customBooks.first)
        #expect(updated.customBannerFile == "\(book.id).jpg")
        #expect(store.bannerImage(for: updated) != nil)
        let tint = try #require(updated.coverTint)
        // Banner is solid blue; boards tint is darkened by 20 %.
        #expect(tint.blue > tint.red)
        #expect(tint.blue <= 0.85)
    }

    @Test func missingBannerFileYieldsNilImage() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook()
        store.add(book)
        try store.setBanner(try jpegData(), forBookID: book.id)
        try FileManager.default.removeItem(at: env.bannersDirectory.appendingPathComponent("\(book.id).jpg"))
        let updated = try #require(store.customBooks.first)
        #expect(store.bannerImage(for: updated) == nil)
    }

    @Test func removeBannerClearsFieldAndFile() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook()
        store.add(book)
        try store.setBanner(try jpegData(), forBookID: book.id)
        store.removeBanner(forBookID: book.id)
        let updated = try #require(store.customBooks.first)
        #expect(updated.customBannerFile == nil)
        #expect(updated.coverTint == nil)
        #expect(!FileManager.default.fileExists(atPath: env.bannersDirectory.appendingPathComponent("\(book.id).jpg").path))
    }

    @Test func builtInBannerLivesInBuiltInArt() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        try store.setBanner(try jpegData(), forBookID: "builtin.iliad")
        let art = try #require(store.builtInArt["builtin.iliad"])
        #expect(art.customBannerFile == "builtin.iliad.jpg")
        #expect(art.coverTint != nil)
        #expect(store.customBooks.isEmpty)

        let merged = try #require(store.allBooks(hiddenBuiltIns: []).first { $0.id == "builtin.iliad" })
        #expect(merged.customBannerFile == "builtin.iliad.jpg")
        #expect(merged.coverTint == art.coverTint)
        #expect(store.bannerImage(for: merged) != nil)

        // Persists across reload.
        flush(store)
        #expect(makeStore(env).builtInArt["builtin.iliad"] == art)

        // setCoverTint routes to builtInArt.
        let tint = RGB(red: 0.1, green: 0.2, blue: 0.3)
        store.setCoverTint(tint, forBookID: "builtin.iliad")
        #expect(store.builtInArt["builtin.iliad"]?.coverTint == tint)
        #expect(store.builtInArt["builtin.iliad"]?.customBannerFile == "builtin.iliad.jpg")
        store.setCoverTint(nil, forBookID: "builtin.iliad")
        #expect(store.builtInArt["builtin.iliad"]?.coverTint == nil)

        // removeBanner routes to builtInArt and removes the file and the empty entry.
        store.removeBanner(forBookID: "builtin.iliad")
        #expect(store.builtInArt["builtin.iliad"] == nil)
        #expect(!FileManager.default.fileExists(atPath: env.bannersDirectory.appendingPathComponent("builtin.iliad.jpg").path))
        let after = try #require(store.allBooks(hiddenBuiltIns: []).first { $0.id == "builtin.iliad" })
        #expect(after.customBannerFile == nil)
        #expect(after.coverTint == nil)
    }

    @Test func setCoverTintOnCustomBookUpdatesBook() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook()
        store.add(book)
        let tint = RGB(red: 0.4, green: 0.3, blue: 0.2)
        store.setCoverTint(tint, forBookID: book.id)
        #expect(store.customBooks.first?.coverTint == tint)
    }

    @Test func allBooksHidesHiddenBuiltInsButNeverCustom() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        let book = customBook(id: "builtin.iliad-lookalike")
        store.add(book)
        let all = store.allBooks(hiddenBuiltIns: ["builtin.iliad", book.id])
        #expect(!all.contains { $0.id == "builtin.iliad" })
        #expect(all.contains { $0.id == "builtin.odyssey" })
        #expect(all.last?.id == book.id)
        #expect(all.count == DashboardProgressBenchmark.builtInBooks.count - 1 + 1)
    }

    @Test func containsWorkKeyMatchesOnlyCustomBooksWithThatKey() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        store.add(customBook(workKey: "/works/OL1W"))
        #expect(store.contains(workKey: "/works/OL1W"))
        #expect(!store.contains(workKey: "/works/OL2W"))
    }

    @Test func updateReplacesBookByID() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        var book = customBook()
        store.add(book)
        book.title = "Renamed"
        store.update(book)
        #expect(store.customBooks.map(\.title) == ["Renamed"])
    }

    @Test func envelopeVersionStaysOne() throws {
        let env = try makeEnv()
        let store = makeStore(env)
        store.add(customBook())
        flush(store)
        let data = try Data(contentsOf: env.fileURL)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["books"] is [Any])
    }
}
