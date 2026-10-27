import Testing
@testable import VoiceInk

struct SpanishCardParserTests {
    private let english = "I'm actually learning Spanish, so I'm very interested in that, and it could help me learn it."

    private func json(sentence: String, chunks: [(String, String, String)]) -> String {
        let items = chunks.map { #"{"source":"\#($0.0)","spanish":"\#($0.1)","gloss":"\#($0.2)"}"# }.joined(separator: ",")
        return #"{"sentence":"\#(sentence)","chunks":[\#(items)]}"#
    }

    @Test func validResponseParses() {
        let response = json(sentence: english, chunks: [
            ("it could help me", "podría ayudarme", "podría = could · ayudarme = help me"),
            ("learning Spanish", "aprendiendo español", "aprendiendo = learning · español = Spanish"),
        ])
        let card = SpanishCardParser.parse(response, dictation: english, maxChunks: 3)
        #expect(card?.chunks.map(\.spanish) == ["aprendiendo español", "podría ayudarme"])
    }

    @Test func fencedJSONParses() {
        let response = "```json\n" + json(sentence: english, chunks: [("learning Spanish", "aprendiendo español", "g")]) + "\n```"
        #expect(SpanishCardParser.parse(response, dictation: english, maxChunks: 2)?.chunks.count == 1)
    }

    @Test func chunkNotInSentenceIsDropped() {
        let response = json(sentence: english, chunks: [
            ("banana", "plátano", "g"),
            ("learning Spanish", "aprendiendo español", "g"),
        ])
        let card = SpanishCardParser.parse(response, dictation: english, maxChunks: 3)
        #expect(card?.chunks.map(\.source) == ["learning Spanish"])
    }

    @Test func russianDictationParses() {
        let dictation = "Я сейчас учу испанский, и мне это очень интересно."
        let response = json(sentence: dictation, chunks: [
            ("учу испанский", "aprendo español", "aprendo = учу · español = испанский"),
        ])
        #expect(SpanishCardParser.parse(response, dictation: dictation, maxChunks: 2)?.chunks.count == 1)
    }

    @Test func shortDictationParses() {
        let response = json(sentence: "Thanks for the help", chunks: [("Thanks", "Gracias", "g")])
        #expect(SpanishCardParser.parse(response, dictation: "Thanks for the help", maxChunks: 1)?.chunks.count == 1)
    }

    @Test func sentenceNotInDictationReturnsNil() {
        let response = json(sentence: "Something else entirely", chunks: [("Something", "Algo", "g")])
        #expect(SpanishCardParser.parse(response, dictation: english, maxChunks: 2) == nil)
    }

    @Test func overlappingChunksKeepFirst() {
        let response = json(sentence: english, chunks: [
            ("learning Spanish", "aprendiendo español", "g"),
            ("Spanish", "español", "g"),
        ])
        let card = SpanishCardParser.parse(response, dictation: english, maxChunks: 3)
        #expect(card?.chunks.map(\.spanish) == ["aprendiendo español"])
    }

    @Test func truncatesToMaxChunks() {
        let dictation = "one two three four five six seven eight"
        let response = json(sentence: dictation, chunks: [
            ("one", "uno", "g"), ("three", "tres", "g"), ("five", "cinco", "g"), ("seven", "siete", "g"),
        ])
        #expect(SpanishCardParser.parse(response, dictation: dictation, maxChunks: 2)?.chunks.map(\.spanish) == ["uno", "tres"])
    }

    @Test func garbageReturnsNil() {
        #expect(SpanishCardParser.parse("Sorry, I can't", dictation: english, maxChunks: 2) == nil)
    }

    @Test func emptyResultReturnsNil() {
        #expect(SpanishCardParser.parse(#"{"sentence": "", "chunks": []}"#, dictation: english, maxChunks: 2) == nil)
    }
}
