import SwiftData
import SwiftUI

struct MySpanishView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var aiService: AIService
    @ObservedObject private var coach = SpanishCoachService.shared
    @Query(sort: \SpanishPhrase.lastSeenAt, order: .reverse) private var phrases: [SpanishPhrase]

    @AppStorage(SpanishCoachSettings.isEnabledKey) private var isEnabled = false
    @AppStorage(SpanishCoachSettings.pausedUntilKey) private var pausedUntilInterval = 0.0

    @State private var isPracticing = false

    private var pausedUntil: Date { Date(timeIntervalSince1970: pausedUntilInterval) }
    private var dueCount: Int {
        let now = Date()
        return phrases.filter { $0.nextReviewAt <= now }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsStrip
            header
            if phrases.isEmpty {
                emptyState
            } else {
                phraseList
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPracticing) {
            SpanishPracticeView()
                .frame(minWidth: 460, minHeight: 360)
        }
    }

    private var settingsStrip: some View {
        let resolved = coach.resolvedProvider()
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Show Spanish after each dictation", isOn: $isEnabled)
                .disabled(resolved == nil)
            if let resolved {
                Text("Uses \(resolved.provider.rawValue) · \(resolved.model) — change in AI Models")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect an AI provider in AI Models to use this.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if pausedUntil > Date() {
                HStack(spacing: 8) {
                    Text("Paused until \(pausedUntil, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Resume") {
                        pausedUntilInterval = 0
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text("\(phrases.count) phrases · \(dueCount) to practise")
                .font(.headline)
            Spacer()
            Button("Practise") { isPracticing = true }
                .buttonStyle(.borderedProminent)
                .disabled(phrases.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Group {
                if isEnabled {
                    Text("Dictate as usual — phrases from your dictations will appear here.")
                } else {
                    Text(
                        "Learn Spanish from your own words. Turn this on and VoiceInk will show a few words of what you just dictated in Spanish (Spain)."
                    )
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var phraseList: some View {
        List(phrases) { phrase in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(phrase.spanish).bold()
                    Text(phrase.source).foregroundStyle(.secondary)
                    Spacer()
                    masteryDots(phrase.mastery)
                }
                Text(phrase.exampleSentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Delete", role: .destructive) {
                    modelContext.delete(phrase)
                    try? modelContext.save()
                }
            }
        }
    }

    private func masteryDots(_ mastery: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<SpanishMastery.maxMastery, id: \.self) { index in
                Circle()
                    .fill(index < mastery ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }
}
