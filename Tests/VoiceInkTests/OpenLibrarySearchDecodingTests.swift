import Foundation
import Testing
@testable import VoiceInk

struct OpenLibrarySearchDecodingTests {
    private static let fixture = """
    {
      "numFound": 3,
      "start": 0,
      "docs": [
        { "key": "/works/OL1W", "title": "Bare Book", "edition_count": 1 },
        { "key": "/works/OL2W", "title": "Dune", "author_name": ["Frank Herbert"],
          "first_publish_year": 1965, "cover_i": 12345, "number_of_pages_median": 412, "edition_count": 90 },
        { "key": "/works/OL3W", "title": "Dune Messiah", "author_name": ["Frank Herbert"], "cover_i": 777 }
      ]
    }
    """

    private func search(
        _ title: String = "dune",
        handler: @escaping StubURLProtocol.Handler
    ) async throws -> [BookSearchResult] {
        let service = OpenLibraryBookSearchService(session: StubURLProtocol.makeSession(handler: handler))
        return try await service.search(title: title)
    }

    @Test func makeURLEscapesAndPinsFields() throws {
        let url = try #require(OpenLibraryBookSearchService.makeURL(title: "Dune & Messiah #1"))
        let string = url.absoluteString
        #expect(string.hasPrefix("https://openlibrary.org/search.json?"))
        #expect(string.contains("title=Dune%20%26%20Messiah%20%231"))
        #expect(string.contains("fields=key,title,author_name,first_publish_year,cover_i,number_of_pages_median,edition_count"))
        #expect(string.contains("limit=15"))
    }

    @Test func makeURLEncodesPlusAndUnicode() throws {
        let plus = try #require(OpenLibraryBookSearchService.makeURL(title: "C++ Primer"))
        #expect(plus.absoluteString.contains("title=C%2B%2B%20Primer"))
        let unicode = try #require(OpenLibraryBookSearchService.makeURL(title: "Les Misérables"))
        #expect(unicode.absoluteString.contains("title=Les%20Mis%C3%A9rables"))
    }

    @Test func makeURLTrimsAndRejectsEmpty() throws {
        #expect(OpenLibraryBookSearchService.makeURL(title: "  ") == nil)
        #expect(OpenLibraryBookSearchService.makeURL(title: "") == nil)
        let url = try #require(OpenLibraryBookSearchService.makeURL(title: "  Dune  "))
        #expect(url.absoluteString.contains("title=Dune&"))
    }

    @Test func decodesFixtureWithMissingOptionalFields() throws {
        let results = try OpenLibraryBookSearchService.decode(Data(Self.fixture.utf8))
        #expect(results.count == 3)
        let dune = try #require(results.first { $0.workKey == "/works/OL2W" })
        #expect(dune.title == "Dune")
        #expect(dune.authors == ["Frank Herbert"])
        #expect(dune.firstPublishYear == 1965)
        #expect(dune.coverID == 12345)
        #expect(dune.pagesMedian == 412)
        #expect(dune.id == "/works/OL2W")
        let bare = try #require(results.first { $0.workKey == "/works/OL1W" })
        #expect(bare.coverID == nil)
        #expect(bare.pagesMedian == nil)
        #expect(bare.authors.isEmpty)
        #expect(bare.firstPublishYear == nil)
    }

    @Test func resultsWithNeitherCoverNorPagesSortLast() throws {
        let results = try OpenLibraryBookSearchService.decode(Data(Self.fixture.utf8))
        #expect(results.map(\.workKey) == ["/works/OL2W", "/works/OL3W", "/works/OL1W"])
    }

    @Test func sendsUserAgentHeader() async throws {
        let captured = StubLockedBox<URLRequest?>(nil)
        _ = try await search { request in
            captured.value = request
            return (StubURLProtocol.response(for: request, status: 200), Data(Self.fixture.utf8))
        }
        let request = try #require(captured.value)
        let agent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("VoiceInk/"))
        #expect(agent.contains("tryvoiceink.com"))
        #expect(request.url?.host == "openlibrary.org")
    }

    @Test func returnsDecodedResultsOnSuccess() async throws {
        let results = try await search { request in
            (StubURLProtocol.response(for: request, status: 200), Data(Self.fixture.utf8))
        }
        #expect(results.count == 3)
    }

    @Test func mapsOfflineAndTimeout() async {
        await #expect(throws: BookSearchError.offline) {
            try await search { _ in throw URLError(.notConnectedToInternet) }
        }
        await #expect(throws: BookSearchError.timedOut) {
            try await search { _ in throw URLError(.timedOut) }
        }
    }

    @Test func mapsHTTPAndDecodingErrors() async {
        await #expect(throws: BookSearchError.http(503)) {
            try await search { request in (StubURLProtocol.response(for: request, status: 503), Data()) }
        }
        await #expect(throws: BookSearchError.decoding) {
            try await search { request in (StubURLProtocol.response(for: request, status: 200), Data("{}".utf8)) }
        }
    }
}

struct StubURLProtocolTests {
    @Test func followsRedirectsAndKeepsHandlerPerSession() async throws {
        let session = StubURLProtocol.makeSession { request in
            if request.url?.path == "/start" {
                return (
                    StubURLProtocol.response(for: request, status: 302, headers: ["Location": "https://stub.invalid/final"]),
                    Data()
                )
            }
            return (StubURLProtocol.response(for: request, status: 200), Data("done".utf8))
        }
        let (data, response) = try await session.data(from: URL(string: "https://stub.invalid/start")!)
        #expect(String(decoding: data, as: UTF8.self) == "done")
        #expect(response.url?.path == "/final")
    }

    @Test func doesNotInjectContentLength() async throws {
        let session = StubURLProtocol.makeSession { request in
            (StubURLProtocol.response(for: request, status: 200), Data(repeating: 1, count: 10))
        }
        let (_, response) = try await session.data(from: URL(string: "https://stub.invalid/x")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.value(forHTTPHeaderField: "Content-Length") == nil)
    }
}
