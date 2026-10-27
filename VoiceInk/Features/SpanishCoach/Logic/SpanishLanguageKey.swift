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
}
