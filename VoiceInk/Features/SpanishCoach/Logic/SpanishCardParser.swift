import Foundation

struct SpanishCard: Equatable, Sendable {
    struct Chunk: Equatable, Sendable {
        let source: String
        let spanish: String
        let gloss: String
    }

    /// Exact sentence from the dictation, in its original language.
    let sentence: String
    /// 1...maxChunks, in sentence order, non-overlapping.
    let chunks: [Chunk]
}

enum SpanishCardParser {
    private struct Response: Decodable {
        struct RawChunk: Decodable {
            let source: String?
            let spanish: String?
            let gloss: String?
        }

        let sentence: String?
        let chunks: [RawChunk]?
    }

    private static let maxSpanishWords = 5

    /// Returns nil when nothing valid remains.
    static func parse(_ modelResponse: String, dictation: String, maxChunks: Int) -> SpanishCard? {
        guard maxChunks > 0 else { return nil }
        let payload = AutoLearnAIReviewer.jsonPayload(fromModelResponse: modelResponse)
        guard let data = payload.data(using: .utf8),
            let response = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }

        let sentence = collapseWhitespace(response.sentence ?? "")
        guard !sentence.isEmpty,
            collapseWhitespace(dictation).range(of: sentence, options: .caseInsensitive) != nil
        else { return nil }

        var kept: [(range: Range<String.Index>, chunk: SpanishCard.Chunk)] = []
        for raw in response.chunks ?? [] {
            let source = collapseWhitespace(raw.source ?? "")
            let spanish = collapseWhitespace(raw.spanish ?? "")
            let gloss = collapseWhitespace(raw.gloss ?? "")
            guard !source.isEmpty, !spanish.isEmpty, !gloss.isEmpty,
                spanish.split(separator: " ").count <= maxSpanishWords,
                let range = sentence.range(of: source, options: .caseInsensitive),
                !kept.contains(where: { $0.range.overlaps(range) })
            else { continue }
            kept.append((range, .init(source: source, spanish: spanish, gloss: gloss)))
        }

        let chunks = kept
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
            .prefix(maxChunks)
            .map(\.chunk)
        guard !chunks.isEmpty else { return nil }
        return SpanishCard(sentence: sentence, chunks: Array(chunks))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
