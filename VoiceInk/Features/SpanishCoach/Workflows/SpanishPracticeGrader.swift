import Foundation

struct SpanishGrade: Equatable, Sendable {
    let result: SpanishMastery.Result
    let feedback: String
    let corrected: String
}

@MainActor
struct SpanishPracticeGrader {
    let aiService: AIService
    let provider: AIProvider
    let model: String

    init(aiService: AIService, provider: AIProvider, model: String) {
        self.aiService = aiService
        self.provider = provider
        self.model = model
    }

    private struct Response: Decodable {
        let verdict: String?
        let feedback: String?
        let corrected: String?
    }

    func grade(source: String, expected: String, userSaid: String) async -> SpanishGrade {
        do {
            let payload = try Self.encodePayload(source: source, expected: expected, userSaid: userSaid)
            let text = try await aiService.performChatCompletion(
                provider: provider,
                modelName: model,
                messages: [.user(payload)],
                systemPrompt: SpanishPrompts.gradeSystemPrompt,
                localUserPrompt: payload,
                timeout: EnhancementRequestSettings.timeout
            ).text
            if let grade = Self.parse(text, expected: expected) { return grade }
        } catch {}
        return Self.localFallback(expected: expected, userSaid: userSaid)
    }

    static func parse(_ modelResponse: String, expected: String) -> SpanishGrade? {
        let payload = AutoLearnAIReviewer.jsonPayload(fromModelResponse: modelResponse)
        guard let data = payload.data(using: .utf8),
            let response = try? JSONDecoder().decode(Response.self, from: data),
            let verdict = response.verdict?.lowercased()
        else { return nil }
        let result: SpanishMastery.Result
        switch verdict {
        case "correct": result = .correct
        case "close": result = .close
        case "wrong": result = .wrong
        default: return nil
        }
        let corrected = response.corrected?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SpanishGrade(
            result: result,
            feedback: response.feedback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            corrected: corrected.isEmpty ? expected : corrected)
    }

    static func localFallback(expected: String, userSaid: String) -> SpanishGrade {
        if SpanishLanguageKey.normalize(userSaid) == SpanishLanguageKey.normalize(expected) {
            return SpanishGrade(result: .correct, feedback: String(localized: "Matches."), corrected: expected)
        }
        return SpanishGrade(
            result: .wrong,
            feedback: String(localized: "Couldn't check this automatically. Compare with the answer."),
            corrected: expected)
    }

    private static func encodePayload(source: String, expected: String, userSaid: String) throws -> String {
        let data = try JSONEncoder().encode(["source": source, "expected": expected, "userSaid": userSaid])
        return String(decoding: data, as: UTF8.self)
    }
}
