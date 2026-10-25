import Foundation

protocol PageCountProviding: Sendable {
    func pageCount(title: String, author: String?) async -> Int?
}

/// Single-shot page-count fallback, used only after the user picks an Open Library result without
/// `number_of_pages_median`. Never called during type-ahead. All failures yield nil.
struct GoogleBooksPageCountService: PageCountProviding {
    static let isGoogleBooksFallbackEnabled = true
    static let minimumPageCount = 40

    private let session: URLSession

    init(session: URLSession = BookServiceHTTP.makeEphemeralSession()) {
        self.session = session
    }

    static func makeURL(title: String, author: String?) -> URL? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        var q = "intitle:\(BookServiceHTTP.encodeQueryValue(trimmedTitle))"
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            // The literal "+" is the term separator Google expects; "+" inside values is %2B.
            q += "+inauthor:\(BookServiceHTTP.encodeQueryValue(author))"
        }
        return BookServiceHTTP.url(
            base: "https://www.googleapis.com/books/v1/volumes",
            percentEncodedQuery: "q=\(q)&maxResults=5"
        )
    }

    func pageCount(title: String, author: String?) async -> Int? {
        guard Self.isGoogleBooksFallbackEnabled,
              let url = Self.makeURL(title: title, author: author) else { return nil }
        do {
            let (data, response) = try await session.data(for: BookServiceHTTP.makeRequest(url: url))
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return Self.medianPageCount(from: data, matchingTitle: title)
        } catch {
            return nil
        }
    }

    /// Median `pageCount` of volumes whose normalised title equals `title` and that have at least
    /// `minimumPageCount` pages. An even count averages the two middle values (rounded down).
    static func medianPageCount(from data: Data, matchingTitle title: String) -> Int? {
        struct Envelope: Decodable {
            let items: [Item]?
        }
        struct Item: Decodable {
            let volumeInfo: VolumeInfo?
        }
        struct VolumeInfo: Decodable {
            let title: String?
            let pageCount: Int?
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        let wanted = normalizedTitle(title)
        guard !wanted.isEmpty else { return nil }

        let counts = (envelope.items ?? [])
            .compactMap(\.volumeInfo)
            .filter { info in
                guard let infoTitle = info.title, let pages = info.pageCount else { return false }
                return pages >= minimumPageCount && normalizedTitle(infoTitle) == wanted
            }
            .compactMap(\.pageCount)
            .sorted()
        guard !counts.isEmpty else { return nil }

        let mid = counts.count / 2
        return counts.count % 2 == 1 ? counts[mid] : (counts[mid - 1] + counts[mid]) / 2
    }

    /// Case-, diacritic- and punctuation-folded title with collapsed whitespace.
    static func normalizedTitle(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
