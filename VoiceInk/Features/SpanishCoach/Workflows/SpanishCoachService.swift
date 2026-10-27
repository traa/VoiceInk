import AppKit
import Foundation
import OSLog
import SwiftData

@MainActor
final class SpanishCoachService: ObservableObject {
    static let shared = SpanishCoachService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "SpanishCoach")
    private var aiService: AIService?
    private var modelContainer: ModelContainer?
    private var isCardTaskRunning = false

    private init() {}

    func configure(aiService: AIService, modelContainer: ModelContainer) {
        self.aiService = aiService
        self.modelContainer = modelContainer
    }

    /// Selected provider if usable, else the first connected usable one; nil when unavailable.
    func resolvedProvider() -> (provider: AIProvider, model: String)? {
        guard let aiService else { return nil }
        let connected = aiService.connectedProviders.filter { AutoLearnProviderPolicy.isSupported($0) }
        let provider =
            connected.contains(aiService.selectedProvider) ? aiService.selectedProvider : connected.first
        guard let provider else { return nil }
        return (provider, aiService.selectedModel(for: provider))
    }

    func pause(for duration: TimeInterval) {
        SpanishCoachSettings.pausedUntil = Date().addingTimeInterval(duration)
        objectWillChange.send()
    }

    /// Fire-and-forget; returns immediately and never affects the paste.
    func dictationDidPaste(_ text: String) {
        guard let aiService, let modelContainer, !isCardTaskRunning else { return }
        let resolved = resolvedProvider()
        let now = Date()
        let decision = SpanishCardGate.evaluate(
            text: text,
            isEnabled: SpanishCoachSettings.isEnabled,
            hasProvider: resolved != nil,
            pausedUntil: SpanishCoachSettings.pausedUntil,
            lastCardShownAt: SpanishCoachSettings.lastCardShownAt,
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: now)
        guard case .show = decision, let resolved else {
            logger.debug("Skipping Spanish card: \(String(describing: decision), privacy: .public)")
            return
        }

        // Claim the cooldown before the network call so bursts can't fan out.
        SpanishCoachSettings.lastCardShownAt = now
        isCardTaskRunning = true

        Task { @MainActor [weak self] in
            defer { self?.isCardTaskRunning = false }
            guard let self else { return }
            do {
                let store = SpanishPhraseStore(context: ModelContext(modelContainer))
                let chunkCount = SpanishMastery.chunkCount(masteredCount: (try? store.masteredCount()) ?? 0)
                let payload = try Self.encodePayload(
                    dictation: text,
                    chunkCount: chunkCount,
                    reinforce: (try? store.reinforcementCandidates(limit: 20)) ?? [],
                    avoid: (try? store.masteredPhrases(limit: 50)) ?? [])

                let response = try await aiService.performChatCompletion(
                    provider: resolved.provider,
                    modelName: resolved.model,
                    messages: [.user(payload)],
                    systemPrompt: SpanishPrompts.cardSystemPrompt,
                    localUserPrompt: payload,
                    timeout: EnhancementRequestSettings.timeout
                ).text

                guard let card = SpanishCardParser.parse(response, dictation: text, maxChunks: chunkCount)
                else {
                    self.logger.debug("Spanish card response had no valid chunks; showing nothing")
                    return
                }
                try store.upsert(card, now: Date())
                SpanishCardPanel.shared.show(card)
            } catch {
                self.logger.error("Spanish card failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func encodePayload(
        dictation: String, chunkCount: Int, reinforce: [SpanishPhrase], avoid: [SpanishPhrase]
    ) throws -> String {
        struct Reinforce: Encodable { let source: String; let spanish: String }
        struct Payload: Encodable {
            let dictation: String
            let chunkCount: Int
            let reinforce: [Reinforce]
            let avoid: [String]
        }
        let payload = Payload(
            dictation: dictation,
            chunkCount: chunkCount,
            reinforce: reinforce.map { Reinforce(source: $0.source, spanish: $0.spanish) },
            avoid: avoid.map(\.spanish))
        let data = try JSONEncoder().encode(payload)
        return String(decoding: data, as: UTF8.self)
    }
}
