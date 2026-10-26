import AppKit
import Foundation
import Testing
@testable import VoiceInk

// MARK: - Stubs

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [String] = []
    private var pageCountCalls: [(title: String, author: String?)] = []

    func recordSearch(_ title: String) { lock.withLock { titles.append(title) } }
    func recordPageCount(title: String, author: String?) { lock.withLock { pageCountCalls.append((title, author)) } }
    var searches: [String] { lock.withLock { titles } }
    var pageCounts: [(title: String, author: String?)] { lock.withLock { pageCountCalls } }
}

private struct StubSearch: BookSearching {
    let log: CallLog
    var handler: @Sendable (String) async throws -> [BookSearchResult]

    func search(title: String) async throws -> [BookSearchResult] {
        log.recordSearch(title)
        return try await handler(title)
    }
}

private struct StubPageCounts: PageCountProviding {
    let log: CallLog
    var result: Int?
    var gate: Gate?

    func pageCount(title: String, author: String?) async -> Int? {
        log.recordPageCount(title: title, author: author)
        await gate?.wait()
        return result
    }
}

private struct StubImporter: BannerImporting {
    func importImage(from url: URL) async throws -> Data { Data([1]) }
    func importImage(fromFile url: URL) throws -> Data { Data([1]) }
}

/// A suspension point the test opens by hand; ignores task cancellation like a slow server would.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Fixtures

@MainActor
private struct Env {
    let root: URL
    let store: DashboardBookStore
    let covers: BookCoverCache
    let log = CallLog()
    let bannerEditor = BookBannerEditorModel(importer: StubImporter())

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AddBookViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = DashboardBookStore(
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true)
        )
        // Covers never hit the network: every request is a 404.
        covers = BookCoverCache(
            directory: root.appendingPathComponent("Covers", isDirectory: true),
            session: StubURLProtocol.makeSession { request in
                (StubURLProtocol.response(for: request, status: 404), Data())
            }
        )
    }

    func cleanUp() {
        store.waitForPendingWrites()
        try? FileManager.default.removeItem(at: root)
    }

    func makeViewModel(
        pageCount: Int? = nil,
        pageCountGate: Gate? = nil,
        debounce: Duration = .milliseconds(1),
        search: @escaping @Sendable (String) async throws -> [BookSearchResult] = { _ in [] }
    ) -> AddBookViewModel {
        AddBookViewModel(
            store: store,
            search: StubSearch(log: log, handler: search),
            pageCounts: StubPageCounts(log: log, result: pageCount, gate: pageCountGate),
            covers: covers,
            bannerEditor: bannerEditor,
            debounce: debounce
        )
    }
}

private func result(
    _ title: String = "Dune",
    key: String = "/works/OL1W",
    authors: [String] = ["Frank Herbert"],
    pages: Int? = 328,
    coverID: Int? = 99
) -> BookSearchResult {
    BookSearchResult(
        workKey: key,
        title: title,
        authors: authors,
        firstPublishYear: 1965,
        coverID: coverID,
        pagesMedian: pages
    )
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

private func customBook(workKey: String?) -> DashboardBook {
    DashboardBook(
        id: "custom.\(UUID().uuidString)",
        kind: .custom,
        title: "Existing",
        author: nil,
        wordCount: 1_000,
        wordCountSource: .userOverride,
        estimatedWordCount: nil,
        pageCount: nil,
        openLibraryWorkKey: workKey,
        coverID: nil,
        coverTint: nil,
        customBannerFile: nil,
        addedAt: Date(timeIntervalSince1970: 1)
    )
}

// MARK: - Tests

@MainActor
struct AddBookViewModelTests {
    // Search

    @Test func belowThreeCharactersNeverSearches() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()

        viewModel.query = "du"
        viewModel.queryChanged()
        await viewModel.settle()
        #expect(viewModel.state == .idle)

        viewModel.query = "   "
        viewModel.queryChanged()
        await viewModel.settle()
        #expect(viewModel.state == .idle)

        viewModel.query = "  ab  "
        viewModel.queryChanged()
        await viewModel.settle()
        #expect(viewModel.state == .idle)
        #expect(env.log.searches.isEmpty)
    }

    @Test func searchTrimsAndFiresAfterDebounce() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let expected = [result()]
        let viewModel = env.makeViewModel(debounce: .milliseconds(50)) { _ in expected }

        viewModel.query = "  dune  "
        viewModel.queryChanged()
        #expect(env.log.searches.isEmpty)  // nothing fires before the debounce elapses
        await viewModel.settle()

        #expect(env.log.searches == ["dune"])
        #expect(viewModel.state == .loaded(expected))
    }

    @Test func rapidTypingSearchesOnlyTheLastQuery() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel(debounce: .milliseconds(50)) { _ in [result()] }

        for text in ["dun", "dune", "dune m"] {
            viewModel.query = text
            viewModel.queryChanged()
        }
        await viewModel.settle()

        #expect(env.log.searches == ["dune m"])
    }

    @Test func laterQueryWinsOverSlowerEarlierResponse() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let gate = Gate()
        let slow = [result("Dune", key: "/works/OLDUNE")]
        let fast = [result("Dune Messiah", key: "/works/OLMESSIAH")]
        let viewModel = env.makeViewModel { title in
            if title == "dune" {
                await gate.wait()
                return slow
            }
            return fast
        }

        viewModel.query = "dune"
        viewModel.queryChanged()
        // Wait until the first search is actually suspended in the stub.
        while env.log.searches.isEmpty { try await Task.sleep(for: .milliseconds(1)) }

        viewModel.query = "dune messiah"
        viewModel.queryChanged()
        await viewModel.settle()
        #expect(viewModel.state == .loaded(fast))

        await gate.open()
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.state == .loaded(fast))
    }

    @Test func clearingQueryAfterResultsReturnsToIdleAndDropsLateResponse() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let gate = Gate()
        let viewModel = env.makeViewModel { _ in
            await gate.wait()
            return [result()]
        }

        viewModel.query = "dune"
        viewModel.queryChanged()
        while env.log.searches.isEmpty { try await Task.sleep(for: .milliseconds(1)) }

        viewModel.query = "du"
        viewModel.queryChanged()
        #expect(viewModel.state == .idle)

        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        #expect(viewModel.state == .idle)
    }

    @Test func emptyResultsGiveEmptyState() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel { _ in [] }

        viewModel.query = "zzzzzz"
        viewModel.queryChanged()
        await viewModel.settle()

        #expect(viewModel.state == .empty)
    }

    @Test func offlineMapsToFailedOffline() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel { _ in throw BookSearchError.offline }

        viewModel.query = "dune"
        viewModel.queryChanged()
        await viewModel.settle()

        #expect(viewModel.state == .failed(.offline))
    }

    @Test func retryRunsTheSearchAgain() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let attempts = CallLog()
        let viewModel = env.makeViewModel { _ in
            attempts.recordSearch("attempt")
            if attempts.searches.count == 1 { throw BookSearchError.timedOut }
            return [result()]
        }

        viewModel.query = "dune"
        viewModel.queryChanged()
        await viewModel.settle()
        #expect(viewModel.state == .failed(.timedOut))

        viewModel.retry()
        await viewModel.settle()
        #expect(viewModel.state == .loaded([result()]))
    }

    // Duplicates

    @Test func alreadyAddedWhenWorkKeyMatchesCustomBook() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        env.store.add(customBook(workKey: "/works/OL1W"))
        let viewModel = env.makeViewModel()
        let duplicate = result(key: "/works/OL1W")

        #expect(viewModel.isAlreadyAdded(duplicate))
        #expect(!viewModel.isAlreadyAdded(result(key: "/works/OL2W")))

        viewModel.selected = duplicate
        let added = await viewModel.add()

        #expect(added == nil)
        #expect(env.store.customBooks.count == 1)
    }

    @Test func manualBooksNeverMatchDuplicates() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        env.store.add(customBook(workKey: nil))
        let viewModel = env.makeViewModel()

        #expect(!viewModel.isAlreadyAdded(result(key: "/works/OL1W")))
        #expect(!viewModel.isAlreadyAdded(result(key: "")))
    }

    // Add via pick

    @Test func addWithPagesCreatesEstimatedBook() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()
        viewModel.selected = result(pages: 328)

        let book = try #require(await viewModel.add())

        #expect(book.id.hasPrefix("custom."))
        #expect(UUID(uuidString: String(book.id.dropFirst("custom.".count))) != nil)
        #expect(book.kind == .custom)
        #expect(book.title == "Dune")
        #expect(book.author == "Frank Herbert")
        #expect(book.wordCount == 90_200)
        #expect(book.wordCountSource == .estimatedFromPages(pages: 328, provider: .openLibrary))
        #expect(book.estimatedWordCount == 90_200)
        #expect(book.pageCount == 328)
        #expect(book.openLibraryWorkKey == "/works/OL1W")
        #expect(book.coverID == 99)
        #expect(env.store.customBooks == [book])
        #expect(env.log.pageCounts.isEmpty)
    }

    @Test func addWithoutPagesUsesGoogleFallback() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel(pageCount: 400)
        viewModel.selected = result("Dune", authors: ["Frank Herbert", "Someone Else"], pages: nil)

        let book = try #require(await viewModel.add())

        #expect(book.wordCountSource == .estimatedFromPages(pages: 400, provider: .googleBooks))
        #expect(book.wordCount == 110_000)
        #expect(book.pageCount == 400)
        #expect(env.log.pageCounts.count == 1)
        #expect(env.log.pageCounts.first?.title == "Dune")
        #expect(env.log.pageCounts.first?.author == "Frank Herbert")
    }

    @Test func addWithoutPagesAndNoFallbackNeedsWordCount() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel(pageCount: nil)
        let picked = result(pages: nil)
        viewModel.selected = picked

        let book = await viewModel.add()

        #expect(book == nil)
        #expect(viewModel.state == .needsWordCount(picked))
        #expect(env.store.customBooks.isEmpty)
    }

    // Manual word count after a pick

    @Test func manualWordCountValidation() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel(pageCount: nil)
        let picked = result(pages: nil, coverID: 77)
        viewModel.selected = picked
        _ = await viewModel.add()
        #expect(viewModel.state == .needsWordCount(picked))

        for text in ["0", "-5", "12.5", "abc", "", "  ", "+5", "1,000", "99999999999999999999999"] {
            let book = await viewModel.submitManualWordCount(text)
            #expect(book == nil, "\(text) must be rejected")
        }
        #expect(env.store.customBooks.isEmpty)

        let book = try #require(await viewModel.submitManualWordCount(" 82500 "))
        #expect(book.wordCountSource == .userOverride)
        #expect(book.wordCount == 82_500)
        #expect(book.estimatedWordCount == nil)
        #expect(book.title == "Dune")
        // Ruling: the picked result's identity survives the manual-count path.
        #expect(book.openLibraryWorkKey == "/works/OL1W")
        #expect(book.coverID == 77)
        #expect(env.store.customBooks == [book])
        #expect(viewModel.isAlreadyAdded(picked))
    }

    @Test func manualWordCountWithoutPendingResultAddsNothing() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()

        let book = await viewModel.submitManualWordCount("1000")

        #expect(book == nil)
        #expect(env.store.customBooks.isEmpty)
    }

    // Add manually

    @Test func addManuallyRequiresTitleAndCount() throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()

        #expect(viewModel.addManually(title: "   ", wordCountText: "1000") == nil)
        #expect(viewModel.addManually(title: "Notes", wordCountText: "1,000") == nil)
        #expect(viewModel.addManually(title: "Notes", wordCountText: "0") == nil)
        #expect(viewModel.addManually(title: "Notes", wordCountText: "") == nil)
        #expect(env.store.customBooks.isEmpty)

        let book = try #require(viewModel.addManually(title: "  Notes ", wordCountText: "1000"))
        #expect(book.title == "Notes")
        #expect(book.wordCount == 1_000)
        #expect(book.wordCountSource == .userOverride)
        #expect(book.coverID == nil)
        #expect(book.openLibraryWorkKey == nil)
        #expect(book.author == nil)
        #expect(env.store.customBooks == [book])
    }

    // Banner

    @Test func preparedBannerIsAppliedOnAdd() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()
        viewModel.selected = result()
        viewModel.preparedBannerData = try jpegData()

        let book = try #require(await viewModel.add())

        let stored = try #require(env.store.customBooks.first { $0.id == book.id })
        #expect(stored.customBannerFile != nil)
        #expect(env.store.bannerImage(for: stored) != nil)
    }

    @Test func preparedBannerIsAppliedToManualBook() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel()
        viewModel.preparedBannerData = try jpegData()

        let book = try #require(viewModel.addManually(title: "Notes", wordCountText: "1000"))

        let stored = try #require(env.store.customBooks.first { $0.id == book.id })
        #expect(env.store.bannerImage(for: stored) != nil)
    }

    @Test func cancelledSheetWritesNothing() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let viewModel = env.makeViewModel { _ in [result()] }

        viewModel.query = "dune"
        viewModel.queryChanged()
        await viewModel.settle()
        viewModel.selected = result()
        viewModel.preparedBannerData = try jpegData()

        viewModel.cancel()
        env.store.waitForPendingWrites()

        #expect(viewModel.preparedBannerData == nil)
        #expect(env.store.customBooks.isEmpty)
        let banners = env.root.appendingPathComponent("BookBanners")
        #expect(!FileManager.default.fileExists(atPath: banners.path))
        #expect(!FileManager.default.fileExists(atPath: env.root.appendingPathComponent("dashboard-books.json").path))
    }

    @Test func cancelDuringGoogleFallbackWritesNothing() async throws {
        let env = try Env()
        defer { env.cleanUp() }
        let gate = Gate()
        let viewModel = env.makeViewModel(pageCount: 400, pageCountGate: gate)
        viewModel.selected = result(pages: nil)
        viewModel.preparedBannerData = try jpegData()

        var onAddedCalls = 0
        let addTask = Task { @MainActor in
            let book = await viewModel.add()
            if book != nil { onAddedCalls += 1 }
            return book
        }

        // Bounded wait for add() to reach the suspended Google lookup.
        let deadline = ContinuousClock.now + .seconds(5)
        while env.log.pageCounts.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(env.log.pageCounts.count == 1)

        viewModel.cancel()
        await gate.open()
        let book = await addTask.value
        env.store.waitForPendingWrites()

        #expect(book == nil)
        #expect(onAddedCalls == 0)
        #expect(env.store.customBooks.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: env.root.appendingPathComponent("BookBanners").path))
        #expect(!viewModel.isAdding)
    }
}
