import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@MainActor
struct SpanishPhraseStoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: SpanishPhrase.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func card(_ spanish: String) -> SpanishCard {
        SpanishCard(sentence: "s", chunks: [.init(source: "src", spanish: spanish, gloss: "g")])
    }

    @Test func upsertDedupesOnNormalizedSpanish() throws {
        let context = try makeContext()
        let store = SpanishPhraseStore(context: context)
        try store.upsert(card("Podría ayudarme"), now: Date())
        try store.upsert(card("podria ayudarme."), now: Date())
        let rows = try context.fetch(FetchDescriptor<SpanishPhrase>())
        #expect(rows.count == 1)
        #expect(rows.first?.timesSeen == 2)
    }

    @Test func duePhrasesOrdering() throws {
        let context = try makeContext()
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
}
