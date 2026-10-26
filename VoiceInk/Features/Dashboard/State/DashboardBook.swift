import Foundation

struct RGB: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

enum DashboardBookEstimation {
    static let wordsPerPage = 275

    static func words(forPages pages: Int) -> Int {
        pages * wordsPerPage
    }
}

struct DashboardBook: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case builtIn
        case custom
    }

    enum WordCountSource: Codable, Hashable, Sendable {
        case curated
        case estimatedFromPages(pages: Int, provider: PageCountProvider)
        case userOverride
    }

    enum PageCountProvider: String, Codable, Sendable {
        case openLibrary
        case googleBooks
    }

    let id: String
    let kind: Kind
    var title: String
    var author: String?
    var wordCount: Int
    var wordCountSource: WordCountSource
    var estimatedWordCount: Int?
    var pageCount: Int?
    var openLibraryWorkKey: String?
    var coverID: Int?
    var coverTint: RGB?
    var customBannerFile: String?
    var addedAt: Date

    var isEstimate: Bool {
        if case .estimatedFromPages = wordCountSource { true } else { false }
    }

    var pagesEquivalent: Int {
        let derivedFromWords = Int((Double(wordCount) / Double(DashboardBookEstimation.wordsPerPage)).rounded())
        if wordCountSource == .userOverride {
            return max(2, derivedFromWords)
        }
        return max(2, pageCount ?? derivedFromWords)
    }

    var displayTitle: String {
        guard kind == .builtIn, let resource = Self.builtInTitles[id] else {
            return title
        }
        return String(localized: resource)
    }

    private static let builtInTitles: [String: LocalizedStringResource] = [
        "builtin.metamorphosis": "The Metamorphosis",
        "builtin.animal-farm": "Animal Farm",
        "builtin.great-gatsby": "The Great Gatsby",
        "builtin.iliad": "Homer's Iliad",
        "builtin.odyssey": "Homer's Odyssey",
        "builtin.iliad-odyssey": "Homer's Iliad and Odyssey",
        "builtin.war-and-peace": "Tolstoy's War and Peace",
    ]
}
