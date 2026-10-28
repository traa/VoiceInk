import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@MainActor
struct SpanishPhraseStoreTests {
    /// The container must outlive the context, so tests hold both.
    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try ModelContainer(
            for: SpanishPhrase.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, ModelContext(container))
    }

    private func card(_ spanish: String) -> SpanishCard {
        SpanishCard(sentence: "s", chunks: [.init(source: "src", spanish: spanish, gloss: "g")])
    }

    @Test func upsertDedupesOnNormalizedSpanish() throws {
        let (container, context) = try makeContext()
        withExtendedLifetime(container) {}
        let store = SpanishPhraseStore(context: context)
        try store.upsert(card("Podría ayudarme"), now: Date())
        try store.upsert(card("podria ayudarme."), now: Date())
        let rows = try context.fetch(FetchDescriptor<SpanishPhrase>())
        #expect(rows.count == 1)
        #expect(rows.first?.timesSeen == 2)
    }

    @Test func duePhrasesOrdering() throws {
        let (container, context) = try makeContext()
        withExtendedLifetime(container) {}
        let now = Date()
        let day: TimeInterval = 86_400
        for (name, offset) in [("a", -day), ("b", -7 * day), ("c", day)] {
            let phrase = SpanishPhrase(spanish: name, source: "s", gloss: "g", exampleSentence: "e", now: now)
            phrase.nextReviewAt = now.addingTimeInterval(offset)
            context.insert(phrase)
        }
        try context.save()
        let due = try SpanishPhraseStore(context: context).duePhrases(now: now, limit: 10)
        #expect(due.map(\.spanish) == ["b", "a"])
    }

    @Test func duplicateChunksInOneCardCountOnce() throws {
        let (container, context) = try makeContext()
        withExtendedLifetime(container) {}
        let card = SpanishCard(sentence: "s", chunks: [
            .init(source: "help me", spanish: "ayúdame", gloss: "g"),
            .init(source: "Help me!", spanish: "ayudame", gloss: "g"),
        ])
        try SpanishPhraseStore(context: context).upsert(card, now: Date())
        let rows = try context.fetch(FetchDescriptor<SpanishPhrase>())
        #expect(rows.count == 1)
        #expect(rows.first?.timesSeen == 1)
    }

    @Test func upsertKeepsOriginalFieldsOnMatch() throws {
        let (container, context) = try makeContext()
        withExtendedLifetime(container) {}
        let store = SpanishPhraseStore(context: context)
        try store.upsert(SpanishCard(sentence: "first", chunks: [.init(source: "a", spanish: "hola", gloss: "g1")]), now: Date())
        try store.upsert(SpanishCard(sentence: "second", chunks: [.init(source: "b", spanish: "Hola", gloss: "g2")]), now: Date())
        let row = try #require(try context.fetch(FetchDescriptor<SpanishPhrase>()).first)
        #expect(row.source == "a")
        #expect(row.gloss == "g1")
        #expect(row.exampleSentence == "first")
    }
}
