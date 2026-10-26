import Foundation
import Testing
@testable import VoiceInk

struct GoogleBooksPageCountTests {
    private static let fixture = """
    { "items": [
      { "volumeInfo": { "title": "Dune", "pageCount": 12 } },
      { "volumeInfo": { "title": "DUNE", "pageCount": 310 } },
      { "volumeInfo": { "title": "Dune!", "pageCount": 320 } },
      { "volumeInfo": { "title": "Dune", "pageCount": 330 } },
      { "volumeInfo": { "title": "Dune Messiah", "pageCount": 900 } },
      { "volumeInfo": { "title": "Dune" } }
    ] }
    """

    private func service(
        handler: @escaping StubURLProtocol.Handler
    ) -> GoogleBooksPageCountService {
        GoogleBooksPageCountService(session: StubURLProtocol.makeSession(handler: handler))
    }

    @Test func googleMedianFiltersByTitleAndMinimumPages() {
        let median = GoogleBooksPageCountService.medianPageCount(from: Data(Self.fixture.utf8), matchingTitle: "Dune")
        #expect(median == 320)
    }

    @Test func titleNormalisationFoldsCaseDiacriticsAndPunctuation() {
        let json = #"{"items":[{"volumeInfo":{"title":"Les Misérables:","pageCount":1200}}]}"#
        #expect(GoogleBooksPageCountService.medianPageCount(from: Data(json.utf8), matchingTitle: "les miserables") == 1200)
    }

    @Test func evenCountAveragesMiddleValues() {
        let json = #"{"items":[{"volumeInfo":{"title":"A","pageCount":100}},{"volumeInfo":{"title":"A","pageCount":201}}]}"#
        #expect(GoogleBooksPageCountService.medianPageCount(from: Data(json.utf8), matchingTitle: "A") == 150)
    }

    @Test func noMatchesOrGarbageYieldsNil() {
        #expect(GoogleBooksPageCountService.medianPageCount(from: Data(Self.fixture.utf8), matchingTitle: "Emma") == nil)
        #expect(GoogleBooksPageCountService.medianPageCount(from: Data("{}".utf8), matchingTitle: "Dune") == nil)
        #expect(GoogleBooksPageCountService.medianPageCount(from: Data("nope".utf8), matchingTitle: "Dune") == nil)
    }

    @Test func makeURLUsesIntitleInauthorAndEncodesPlus() throws {
        let url = try #require(GoogleBooksPageCountService.makeURL(title: "C++ Primer", author: "Stanley B. Lippman"))
        let string = url.absoluteString
        #expect(string.hasPrefix("https://www.googleapis.com/books/v1/volumes?q="))
        #expect(string.contains("q=intitle:C%2B%2B%20Primer+inauthor:Stanley%20B.%20Lippman"))
        #expect(string.hasSuffix("&maxResults=5"))
        let noAuthor = try #require(GoogleBooksPageCountService.makeURL(title: "Dune", author: nil))
        #expect(!noAuthor.absoluteString.contains("inauthor"))
        #expect(GoogleBooksPageCountService.makeURL(title: "  ", author: "x") == nil)
    }

    @Test func googleReturnsMedianOverStubbedSession() async {
        let count = await service { request in
            (StubURLProtocol.response(for: request, status: 200), Data(Self.fixture.utf8))
        }.pageCount(title: "Dune", author: "Frank Herbert")
        #expect(count == 320)
    }

    @Test func googleReturnsNilOnFailureOr429() async {
        let rateLimited = await service { request in
            (StubURLProtocol.response(for: request, status: 429), Data(Self.fixture.utf8))
        }.pageCount(title: "Dune", author: nil)
        #expect(rateLimited == nil)

        let offline = await service { _ in throw URLError(.notConnectedToInternet) }
            .pageCount(title: "Dune", author: nil)
        #expect(offline == nil)

        let garbage = await service { request in
            (StubURLProtocol.response(for: request, status: 200), Data("<html>".utf8))
        }.pageCount(title: "Dune", author: nil)
        #expect(garbage == nil)
    }

    @Test func googleFallbackHonoursOverallDeadline() async {
        let slow = GoogleBooksPageCountService(
            session: StubURLProtocol.makeSession { request in
                Thread.sleep(forTimeInterval: 2)
                return (StubURLProtocol.response(for: request, status: 200), Data(Self.fixture.utf8))
            },
            overallTimeout: 0.2
        )
        let start = Date()
        let count = await slow.pageCount(title: "Dune", author: nil)
        #expect(count == nil)
        #expect(Date().timeIntervalSince(start) < 1.5)
    }

    @Test func defaultDeadlineIsTenSeconds() {
        #expect(BookServiceHTTP.requestTimeout == 10)
    }

    @Test func googleFallbackConstantIsTrue() {
        #expect(GoogleBooksPageCountService.isGoogleBooksFallbackEnabled)
    }
}
