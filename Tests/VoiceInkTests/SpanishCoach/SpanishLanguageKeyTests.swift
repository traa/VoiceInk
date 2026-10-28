import Testing
@testable import VoiceInk

struct SpanishLanguageKeyTests {
    @Test func prefersPlainEs() {
        #expect(SpanishLanguageKey.key(in: ["es": "Spanish", "en": "English"]) == "es")
    }

    @Test func prefersSpainVariant() {
        #expect(SpanishLanguageKey.key(in: ["es-MX": "Mexican", "es-ES": "Spain"]) == "es-ES")
    }

    @Test func fallsBackToAnyEsPrefix() {
        #expect(SpanishLanguageKey.key(in: ["es-US": "US Spanish", "en": "English"]) == "es-US")
    }

    @Test func englishOnlyModelHasNoKey() {
        #expect(SpanishLanguageKey.key(in: ["en": "English"]) == nil)
    }

    @Test func normalizeIgnoresCaseAccentsAndPunctuation() {
        #expect(SpanishLanguageKey.normalize("¿Podría ayudarme?") == SpanishLanguageKey.normalize("podria ayudarme"))
    }
}
