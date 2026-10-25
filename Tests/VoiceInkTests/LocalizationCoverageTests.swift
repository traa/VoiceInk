import Foundation
import Testing

/// Every user-facing string added for custom books must ship with German, French and
/// Simplified Chinese translations (spec §5.8: no `new`-state entries left behind).
struct LocalizationCoverageTests {
    private static let translatedLanguages = ["de", "fr", "zh-Hans"]

    /// The exact catalog keys emitted by the custom-books code (Tasks 5-9), including
    /// the six §8.3 banner import error messages.
    private static let bookKeys = [
        // Banner import errors (BannerImageImporter, spec §8.3)
        "Enter a web address starting with http:// or https://.",
        "Couldn't download that image. Check the address and your connection.",
        "The server took too long to respond.",
        "That doesn't look like an image (PNG, JPEG or HEIC).",
        "That image is too large (over 10 MB or 50 megapixels).",
        "That image is too small to use as a banner (at least 300 px wide).",
        // Grid reveal caption (ProgressCaption, DashboardBookBannerArt)
        "~%@ of %@ pages dictated",
        "All %@ pages dictated",
        "All %@ pages · %@×",
        // Hero subtitle estimate variant (DashboardContent)
        "Dictated %@, ~%@ words from %@.",
        // Hero book chip and menu (DashboardHeroCard)
        "Choose a book",
        "Choose the book your progress is compared to",
        "Book for progress comparison",
        "%@ — %@ words",
        "%@ — ~%@ words",
        "Add Book…",
        "Manage Books…",
        // Add Book sheet (AddBookSheet)
        "Add Book",
        "Book title",
        "Searches Open Library over the internet. Only the title you type is sent.",
        "Searches Open Library over the internet. Only the title you type is sent; page counts may come from Google Books.",
        "Type at least 3 letters of a book title to search.",
        "No books found. Try a shorter title.",
        "Can't reach Open Library. Check your connection, or add the book manually.",
        "Search failed.",
        "Add manually…",
        "Already added",
        "No page count",
        "~%@ words",
        "We couldn't find a page count. Enter the word count:",
        "Word count",
        "Banner image (optional)",
        "Add a book manually",
        // Banner editor (BookBannerEditor)
        "Image URL",
        "Use URL",
        "Downloads the image from the address you enter.",
        "Upload…",
        "Remove custom banner",
        "Choose Banner Image",
        "Couldn't save that image.",
        // Manage Books panel (ManageBooksPanel)
        "Manage Books",
        "Your books",
        "Built-in books",
        "No custom books yet.",
        "curated",
        "estimated from %lld pages",
        "exact (you entered)",
        "%@ · %@",
        "Delete this book?",
        "Completed",
        "“%@” and its custom banner will be removed.",
        "Edit word count…",
        "Exact word count",
        "Reset to estimate",
        "Show",
        "Hide",
        "Banner…",
    ]

    @Test func catalogHasNoNewStateEntriesForBookKeys() throws {
        let strings = try Self.loadCatalogStrings()

        for key in Self.bookKeys {
            guard let entry = strings[key] as? [String: Any] else {
                Issue.record("Missing catalog key: \(key)")
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.translatedLanguages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                let state = unit?["state"] as? String
                #expect(!value.isEmpty, "Missing \(language) translation for key: \(key)")
                #expect(state != nil && state != "new", "\(language) translation for key \(key) is in state \(state ?? "nil")")
            }
        }
    }

    @Test func translationsKeepTheKeysFormatSpecifiers() throws {
        let strings = try Self.loadCatalogStrings()

        for key in Self.bookKeys {
            guard let entry = strings[key] as? [String: Any] else { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let expected = Self.specifiers(in: key)
            for language in Self.translatedLanguages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String else { continue }
                #expect(Self.specifiers(in: value) == expected, "\(language) translation of \(key) changes its format specifiers: \(value)")
                #expect(key.contains("~") == value.contains("~"), "\(language) translation of \(key) must keep the \"~\" estimate marker exactly: \(value)")
                #expect(key.contains("×") == value.contains("×"), "\(language) translation of \(key) must keep \"×\": \(value)")
            }
        }
    }

    /// Format specifiers in argument order, with positional forms (`%2$@`) normalised.
    private static func specifiers(in format: String) -> [String] {
        let regex = /%(?:(\d+)\$)?(@|lld|d)/
        let matches = format.matches(of: regex)
        let positional = matches.allSatisfy { $0.output.1 != nil }
        let tokens = matches.enumerated().map { index, match in
            (position: match.output.1.flatMap { Int($0) } ?? index + 1, type: String(match.output.2))
        }
        let ordered = positional ? tokens.sorted { $0.position < $1.position } : tokens
        return ordered.map(\.type)
    }

    private static func loadCatalogStrings() throws -> [String: Any] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VoiceInkTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("VoiceInk/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(catalog["strings"] as? [String: Any])
    }
}
