import Foundation
import SwiftData

@Model
final class SpanishPhrase {
    var id: UUID = UUID()
    var spanish: String = ""
    var normalizedSpanish: String = ""
    var source: String = ""
    var gloss: String = ""
    var exampleSentence: String = ""
    var createdAt: Date = Date()
    var lastSeenAt: Date = Date()
    var timesSeen: Int = 1
    var mastery: Int = 0
    var practiceAttempts: Int = 0
    var practiceCorrect: Int = 0
    var nextReviewAt: Date = Date()

    init(spanish: String, source: String, gloss: String, exampleSentence: String, now: Date = Date()) {
        self.spanish = spanish
        self.normalizedSpanish = SpanishLanguageKey.normalize(spanish)
        self.source = source
        self.gloss = gloss
        self.exampleSentence = exampleSentence
        self.createdAt = now
        self.lastSeenAt = now
        self.nextReviewAt = now
    }
}
