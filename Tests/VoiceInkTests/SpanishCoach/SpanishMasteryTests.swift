import Foundation
import Testing
@testable import VoiceInk

struct SpanishMasteryTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func phrase(mastery: Int) -> SpanishPhrase {
        let phrase = SpanishPhrase(spanish: "x", source: "y", gloss: "g", exampleSentence: "e", now: now)
        phrase.mastery = mastery
        return phrase
    }

    @Test func correctRaisesAndCaps() {
        let p = phrase(mastery: 4)
        SpanishMastery.apply(.correct, to: p, now: now)
        #expect(p.mastery == 5)
        #expect(p.practiceCorrect == 1)
        SpanishMastery.apply(.correct, to: p, now: now)
        #expect(p.mastery == 5)
    }

    @Test func wrongFloorsAtZero() {
        let p = phrase(mastery: 0)
        SpanishMastery.apply(.wrong, to: p, now: now)
        #expect(p.mastery == 0)
        #expect(p.practiceAttempts == 1)
    }

    @Test func closeKeepsMastery() {
        let p = phrase(mastery: 2)
        SpanishMastery.apply(.close, to: p, now: now)
        #expect(p.mastery == 2)
        #expect(p.practiceCorrect == 0)
    }

    @Test func schedulesNextReviewByNewMastery() {
        let p = phrase(mastery: 2)
        SpanishMastery.apply(.correct, to: p, now: now)
        #expect(p.mastery == 3)
        #expect(p.nextReviewAt == now.addingTimeInterval(4 * 86_400))
    }

    @Test func chunkCountThresholds() {
        #expect(SpanishMastery.chunkCount(masteredCount: 0) == 2)
        #expect(SpanishMastery.chunkCount(masteredCount: 9) == 2)
        #expect(SpanishMastery.chunkCount(masteredCount: 10) == 3)
        #expect(SpanishMastery.chunkCount(masteredCount: 59) == 4)
        #expect(SpanishMastery.chunkCount(masteredCount: 60) == 5)
    }
}
