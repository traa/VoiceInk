import Foundation

enum SpanishLanguageKey {
    /// Lowercase, accent-insensitive, punctuation-free, single-spaced. Used as the dedupe key
    /// and for the local grading fallback.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es_ES"))
        let stripped = folded.unicodeScalars
            .map { CharacterSet.punctuationCharacters.union(.symbols).contains($0) ? " " : String($0) }
            .joined()
        return stripped
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// "es" if supported, else "es-ES", else the first key with prefix "es"; nil if none.
    static func key(in supportedLanguages: [String: String]) -> String? {
        if supportedLanguages["es"] != nil { return "es" }
        if supportedLanguages["es-ES"] != nil { return "es-ES" }
        return supportedLanguages.keys.filter { $0.hasPrefix("es") }.sorted().first
    }
}
