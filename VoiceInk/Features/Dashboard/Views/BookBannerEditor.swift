import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives `BookBannerEditor`: turns a pasted URL or a chosen file into normalised JPEG bytes.
///
/// It never touches the store. The caller decides what to do with the prepared bytes (the Add Book
/// sheet holds them until **Add**, Manage Books writes them straight away). All work runs off the
/// main actor; a generation counter drops the result of anything cancelled or superseded.
@MainActor
final class BookBannerEditorModel: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let importer: BannerImporting
    private var generation = 0
    private var currentTask: Task<Data, Error>?

    init(importer: BannerImporting) {
        self.importer = importer
    }

    /// Downloads and normalises the image at `text` (trimmed). Returns nil on failure, cancellation or
    /// when superseded; failures set `errorMessage`.
    func useURL(_ text: String) async -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            cancel()
            errorMessage = BannerImportError.invalidURL.userMessage
            return nil
        }
        let importer = importer
        return await run { try await importer.importImage(from: url) }
    }

    /// Reads and normalises a local file. The importer is synchronous (HEIC decode), so it runs detached.
    func useFile(_ url: URL) async -> Data? {
        let importer = importer
        return await run { try importer.importImage(fromFile: url) }
    }

    /// Stops any in-flight request and clears the working state without reporting an error.
    func cancel() {
        generation += 1
        currentTask?.cancel()
        currentTask = nil
        isWorking = false
    }

    func clearError() {
        errorMessage = nil
    }

    private func run(_ operation: @escaping @Sendable () async throws -> Data) async -> Data? {
        cancel()
        errorMessage = nil
        isWorking = true
        let token = generation

        let task = Task.detached(priority: .userInitiated) { try await operation() }
        currentTask = task

        do {
            let data = try await task.value
            guard token == generation else { return nil }
            finish()
            return data
        } catch {
            guard token == generation else { return nil }
            finish()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    private func finish() {
        currentTask = nil
        isWorking = false
    }

    private static func message(for error: Error) -> String {
        if let importError = error as? BannerImportError {
            return importError.userMessage
        }
        return BannerImportError.unreachable.userMessage
    }
}

/// Shared "custom banner" controls: image URL + **Use URL**, **Upload…**, **Remove custom banner**.
/// Used by the Add Book sheet and (Task 8) the Manage Books banner popover.
struct BookBannerEditor: View {
    @ObservedObject var model: BookBannerEditorModel
    let hasCustomBanner: Bool
    let previewImage: NSImage?
    let onPrepared: (Data) -> Void
    let onRemove: (() -> Void)?

    @State private var urlText = ""

    init(
        model: BookBannerEditorModel,
        hasCustomBanner: Bool,
        previewImage: NSImage?,
        onPrepared: @escaping (Data) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.model = model
        self.hasCustomBanner = hasCustomBanner
        self.previewImage = previewImage
        self.onPrepared = onPrepared
        self.onRemove = onRemove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Image URL", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isWorking)
                        .onSubmit(useURL)
                        .onChange(of: urlText) { _, _ in model.clearError() }

                    if model.isWorking {
                        ProgressView()
                            .controlSize(.small)
                        Button("Cancel") { model.cancel() }
                    } else {
                        Button("Use URL", action: useURL)
                            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Text("Downloads the image from the address you enter.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button("Upload…", action: chooseFile)
                    .disabled(model.isWorking)
                if let onRemove {
                    Button("Remove custom banner", role: .destructive, action: onRemove)
                        .disabled(!hasCustomBanner || model.isWorking)
                }
            }

            if let message = model.errorMessage {
                Text(verbatim: message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func useURL() {
        let text = urlText
        Task {
            if let data = await model.useURL(text) {
                urlText = ""
                onPrepared(data)
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Banner Image")
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                if let data = await model.useFile(url) {
                    onPrepared(data)
                }
            }
        }
    }
}
