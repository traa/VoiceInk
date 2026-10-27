import SwiftData
import SwiftUI

struct SpanishPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var aiService: AIService

    private enum Step {
        case prompt
        case recording
        case working
        case graded(userSaid: String, grade: SpanishGrade)
        case revealed
    }

    @State private var queue: [SpanishPhrase] = []
    @State private var index = 0
    @State private var isLoaded = false
    @State private var correctCount = 0
    @State private var step: Step = .prompt
    @State private var recorder: Recorder?
    @State private var recordingURL: URL?
    @State private var errorMessage: String?
    @State private var notice: String?

    private var store: SpanishPhraseStore { SpanishPhraseStore(context: modelContext) }

    /// Current model if it can transcribe Spanish, else the first usable model that can.
    private var practiceModel: (model: any TranscriptionModel, language: String)? {
        let candidates = [transcriptionModelManager.currentTranscriptionModel].compactMap { $0 }
            + transcriptionModelManager.usableModels
        for model in candidates {
            if let key = SpanishLanguageKey.key(in: model.supportedLanguages) {
                return (model, key)
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 18) {
            if !isLoaded {
                ProgressView()
            } else if queue.isEmpty {
                caughtUp
            } else if index >= queue.count {
                summary
            } else {
                card(for: queue[index])
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { loadDue() }
        .onChange(of: engine.recordingState) { _, newState in
            if newState != .idle, case .recording = step { Task { await abortForDictation() } }
        }
        .onDisappear { Task { await discardRecording() } }
    }

    // MARK: Screens

    private var caughtUp: some View {
        VStack(spacing: 14) {
            Text("All caught up").font(.title2.bold())
            Button("Practise anyway") { loadWeakest() }
                .buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            Text("\(correctCount) of \(queue.count) correct").font(.title2.bold())
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func card(for phrase: SpanishPhrase) -> some View {
        VStack(spacing: 14) {
            Text("How do you say:").foregroundStyle(.secondary)
            Text(phrase.source).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(phrase.exampleSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch step {
            case .prompt, .recording, .working:
                promptControls(for: phrase)
            case .graded(let userSaid, let grade):
                gradedView(phrase: phrase, userSaid: userSaid, grade: grade)
            case .revealed:
                revealedView(phrase: phrase)
            }
        }
    }

    private func promptControls(for phrase: SpanishPhrase) -> some View {
        let model = practiceModel
        let isRecording: Bool = { if case .recording = step { return true } else { return false } }()
        let isWorking: Bool = { if case .working = step { return true } else { return false } }()
        let dictationBusy = engine.recordingState != .idle

        return VStack(spacing: 12) {
            if model == nil {
                Text(
                    "Your transcription model only understands English. Pick a multilingual model in AI Models to practise speaking."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            if let notice { Text(notice).font(.callout).foregroundStyle(.orange) }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }

            if isWorking {
                ProgressView()
            } else {
                HStack(spacing: 12) {
                    Button(isRecording ? "Stop" : "Say it") {
                        Task { isRecording ? await stopAndGrade(phrase) : await startRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecording ? .red : .accentColor)
                    .disabled(model == nil || (!isRecording && dictationBusy))

                    if !isRecording {
                        Button("Just show me") {
                            notice = nil
                            errorMessage = nil
                            step = .revealed
                        }
                    }
                }
            }
        }
    }

    private func gradedView(phrase: SpanishPhrase, userSaid: String, grade: SpanishGrade) -> some View {
        VStack(spacing: 10) {
            Text("You said: \(userSaid)").foregroundStyle(.secondary)
            switch grade.result {
            case .correct: Text("Correct!").font(.title3.bold()).foregroundStyle(.green)
            case .close: Text("Almost").font(.title3.bold()).foregroundStyle(.orange)
            case .wrong: Text("Not quite").font(.title3.bold()).foregroundStyle(.red)
            }
            if !grade.feedback.isEmpty { Text(grade.feedback).multilineTextAlignment(.center) }
            Text(grade.corrected).font(.title3.bold())
            if SpanishLanguageKey.normalize(phrase.spanish) != SpanishLanguageKey.normalize(grade.corrected) {
                Text(phrase.spanish).foregroundStyle(.secondary)
            }
            Button("Next") { advance() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func revealedView(phrase: SpanishPhrase) -> some View {
        VStack(spacing: 10) {
            Text(phrase.spanish).font(.title2.bold())
            Text(phrase.gloss).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("I knew it") { selfGrade(.correct, phrase) }
                    .buttonStyle(.borderedProminent)
                Button("I didn't") { selfGrade(.wrong, phrase) }
            }
        }
    }

    // MARK: Session

    private func loadDue() {
        queue = (try? store.duePhrases(now: Date(), limit: 10)) ?? []
        index = 0
        isLoaded = true
    }

    private func loadWeakest() {
        queue = (try? store.weakestPhrases(limit: 10)) ?? []
        index = 0
        correctCount = 0
    }

    private func advance() {
        index += 1
        step = .prompt
        notice = nil
        errorMessage = nil
    }

    private func record(_ result: SpanishMastery.Result, _ phrase: SpanishPhrase) {
        SpanishMastery.apply(result, to: phrase, now: Date())
        if result == .correct { correctCount += 1 }
        try? modelContext.save()
    }

    private func selfGrade(_ result: SpanishMastery.Result, _ phrase: SpanishPhrase) {
        record(result, phrase)
        advance()
    }

    // MARK: Speaking

    private func startRecording() async {
        guard practiceModel != nil, engine.recordingState == .idle else { return }
        notice = nil
        errorMessage = nil
        let activeRecorder = recorder ?? Recorder()
        recorder = activeRecorder
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spanish-practice-\(UUID().uuidString).wav")
        do {
            try await activeRecorder.startRecording(toOutputFile: url)
            recordingURL = url
            step = .recording
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopAndGrade(_ phrase: SpanishPhrase) async {
        guard let recorder, let url = recordingURL, let practice = practiceModel else { return }
        step = .working
        recordingURL = nil
        await recorder.stopRecording()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let raw = try await engine.serviceRegistry.transcribe(
                audioURL: url,
                model: practice.model,
                context: TranscriptionRequestContext(language: practice.language, prompt: nil))
            let said = TranscriptionOutputFilter.filter(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !said.isEmpty else {
                notice = String(localized: "Didn't catch that — try again.")
                step = .prompt
                return
            }
            let grade = await grade(userSaid: said, phrase: phrase)
            record(grade.result, phrase)
            step = .graded(userSaid: said, grade: grade)
        } catch {
            errorMessage = error.localizedDescription
            step = .prompt
        }
    }

    private func grade(userSaid: String, phrase: SpanishPhrase) async -> SpanishGrade {
        guard let resolved = SpanishCoachService.shared.resolvedProvider() else {
            return SpanishPracticeGrader.localFallback(expected: phrase.spanish, userSaid: userSaid)
        }
        return await SpanishPracticeGrader(aiService: aiService, provider: resolved.provider, model: resolved.model)
            .grade(source: phrase.source, expected: phrase.spanish, userSaid: userSaid)
    }

    /// Dictation always wins: drop the practice recording without transcribing or grading it.
    private func abortForDictation() async {
        step = .prompt
        notice = String(localized: "Practice paused for dictation.")
        await discardRecording()
    }

    private func discardRecording() async {
        guard let url = recordingURL else { return }
        recordingURL = nil
        await recorder?.stopRecording()
        try? FileManager.default.removeItem(at: url)
    }
}
