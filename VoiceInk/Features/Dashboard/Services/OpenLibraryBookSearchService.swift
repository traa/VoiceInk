import Foundation

struct BookSearchResult: Identifiable, Hashable, Sendable {
    let workKey: String
    let title: String
    let authors: [String]
    let firstPublishYear: Int?
    let coverID: Int?
    let pagesMedian: Int?

    var id: String { workKey }
}

enum BookSearchError: Error, Equatable {
    case offline
    case timedOut
    case http(Int)
    case decoding
}

protocol BookSearching: Sendable {
    func search(title: String) async throws -> [BookSearchResult]
}

/// Shared helpers for the dashboard book web services (query encoding, identification).
enum BookServiceHTTP {
    static let requestTimeout: TimeInterval = 10

    /// `VoiceInk/<CFBundleShortVersionString> (https://tryvoiceink.com)`; Open Library asks clients to identify themselves.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "VoiceInk/\(version) (https://tryvoiceink.com)"
    }

    static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Percent-encodes a query value so that everything except RFC 3986 unreserved characters
    /// is escaped. `URLComponents` leaves `+` untouched, which servers read as a space ("C++").
    static func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Builds `base?name=value&...` from already-encoded query text.
    static func url(base: String, percentEncodedQuery: String) -> URL? {
        var components = URLComponents(string: base)
        components?.percentEncodedQuery = percentEncodedQuery
        return components?.url
    }

    static func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

struct OpenLibraryBookSearchService: BookSearching {
    static let fields = "key,title,author_name,first_publish_year,cover_i,number_of_pages_median,edition_count"
    static let limit = 15

    private let session: URLSession

    init(session: URLSession = BookServiceHTTP.makeEphemeralSession()) {
        self.session = session
    }

    static func makeURL(title: String) -> URL? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let query = "title=\(BookServiceHTTP.encodeQueryValue(trimmed))&fields=\(fields)&limit=\(limit)"
        return BookServiceHTTP.url(base: "https://openlibrary.org/search.json", percentEncodedQuery: query)
    }

    func search(title: String) async throws -> [BookSearchResult] {
        guard let url = Self.makeURL(title: title) else { return [] }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: BookServiceHTTP.makeRequest(url: url))
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw BookSearchError.timedOut
            default: throw BookSearchError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else { throw BookSearchError.decoding }
        guard (200..<300).contains(http.statusCode) else { throw BookSearchError.http(http.statusCode) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [BookSearchResult] {
        struct Envelope: Decodable {
            let docs: [Doc]
        }
        struct Doc: Decodable {
            let key: String?
            let title: String?
            let authorName: [String]?
            let firstPublishYear: Int?
            let coverI: Int?
            let numberOfPagesMedian: Int?

            enum CodingKeys: String, CodingKey {
                case key, title
                case authorName = "author_name"
                case firstPublishYear = "first_publish_year"
                case coverI = "cover_i"
                case numberOfPagesMedian = "number_of_pages_median"
            }
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw BookSearchError.decoding
        }

        let results: [BookSearchResult] = envelope.docs.compactMap { doc in
            guard let key = doc.key, !key.isEmpty, let title = doc.title, !title.isEmpty else { return nil }
            return BookSearchResult(
                workKey: key,
                title: title,
                authors: doc.authorName ?? [],
                firstPublishYear: doc.firstPublishYear,
                coverID: doc.coverI,
                pagesMedian: doc.numberOfPagesMedian
            )
        }

        // Keep Open Library's ranking, but push results with neither cover nor pages to the end.
        let informative = results.filter { $0.coverID != nil || $0.pagesMedian != nil }
        let bare = results.filter { $0.coverID == nil && $0.pagesMedian == nil }
        return informative + bare
    }
}
