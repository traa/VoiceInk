import Foundation
import SwiftData

struct SpanishPhraseStore {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Insert a phrase per chunk, or bump `timesSeen`/`lastSeenAt` on an existing normalized match.
    func upsert(_ card: SpanishCard, now: Date) throws {
        for chunk in card.chunks {
            let key = SpanishLanguageKey.normalize(chunk.spanish)
            guard !key.isEmpty else { continue }
            var descriptor = FetchDescriptor<SpanishPhrase>(predicate: #Predicate { $0.normalizedSpanish == key })
            descriptor.fetchLimit = 1
            if let existing = try context.fetch(descriptor).first {
                existing.lastSeenAt = now
                existing.timesSeen += 1
            } else {
                context.insert(
                    SpanishPhrase(
                        spanish: chunk.spanish, source: chunk.source, gloss: chunk.gloss,
                        exampleSentence: card.sentence, now: now))
            }
        }
        try context.save()
    }

    /// mastery < 3, most recently seen first.
    func reinforcementCandidates(limit: Int) throws -> [SpanishPhrase] {
        var descriptor = FetchDescriptor<SpanishPhrase>(
            predicate: #Predicate { $0.mastery < 3 },
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// mastery == 5.
    func masteredPhrases(limit: Int) throws -> [SpanishPhrase] {
        var descriptor = FetchDescriptor<SpanishPhrase>(
            predicate: #Predicate { $0.mastery >= 5 },
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// mastery >= 3.
    func masteredCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<SpanishPhrase>(predicate: #Predicate { $0.mastery >= 3 }))
    }

    /// `nextReviewAt <= now`, by nextReviewAt ascending then mastery ascending.
    func duePhrases(now: Date, limit: Int) throws -> [SpanishPhrase] {
        var descriptor = FetchDescriptor<SpanishPhrase>(
            predicate: #Predicate { $0.nextReviewAt <= now },
            sortBy: [SortDescriptor(\.nextReviewAt), SortDescriptor(\.mastery)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// mastery ascending, most recently seen first.
    func weakestPhrases(limit: Int) throws -> [SpanishPhrase] {
        var descriptor = FetchDescriptor<SpanishPhrase>(
            sortBy: [SortDescriptor(\.mastery), SortDescriptor(\.lastSeenAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}
