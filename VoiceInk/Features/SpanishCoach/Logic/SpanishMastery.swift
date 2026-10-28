import Foundation

enum SpanishMastery {
    /// Index = mastery.
    static let reviewIntervalsDays = [0, 1, 2, 4, 8, 16]
    static let maxMastery = 5

    enum Result { case correct, close, wrong }

    static func apply(_ result: Result, to phrase: SpanishPhrase, now: Date) {
        phrase.practiceAttempts += 1
        switch result {
        case .correct:
            phrase.mastery = min(maxMastery, phrase.mastery + 1)
            phrase.practiceCorrect += 1
        case .close:
            break
        case .wrong:
            phrase.mastery = max(0, phrase.mastery - 1)
        }
        let days = reviewIntervalsDays[phrase.mastery]
        phrase.nextReviewAt = now.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    static func chunkCount(masteredCount: Int) -> Int {
        switch masteredCount {
        case ..<10: return 2
        case 10..<30: return 3
        case 30..<60: return 4
        default: return 5
        }
    }
}
