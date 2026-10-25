import AppKit
import Combine
import SwiftUI

/// Actions behind the Manage Books panel.
///
/// Built-in books can only be hidden/shown and given a banner; custom books can also be deleted and
/// have their word count overridden. Hiding or deleting the selected book clears the stored selection
/// here, so persisted state never points at a missing book.
@MainActor
final class ManageBooksViewModel: ObservableObject {
    let store: DashboardBookStore
    private let hidden: Binding<HiddenBookIDs>
    private let selectedID: Binding<String>
    private let covers: BookCoverCache
    private var storeObservation: AnyCancellable?

    init(
        store: DashboardBookStore,
        hidden: Binding<HiddenBookIDs>,
        selectedID: Binding<String>,
        covers: BookCoverCache = .shared
    ) {
        self.store = store
        self.hidden = hidden
        self.selectedID = selectedID
        self.covers = covers
        storeObservation = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Listing

    /// Custom books in the order they were added.
    var yourBooks: [DashboardBook] {
        store.customBooks
    }

    /// Every built-in book (hidden ones included), merged with its custom banner art.
    var builtInBooks: [DashboardBook] {
        store.allBooks(hiddenBuiltIns: [])
            .filter { $0.kind == .builtIn }
            .sorted { ($0.wordCount, $0.id) < ($1.wordCount, $1.id) }
    }

    func isHidden(_ book: DashboardBook) -> Bool {
        hidden.wrappedValue.ids.contains(book.id)
    }

    /// Custom banner if any, else the cached cover; nil falls back to a drawn placeholder.
    func thumbnail(for book: DashboardBook) -> NSImage? {
        if let banner = store.bannerImage(for: book) { return banner }
        guard let coverID = book.coverID else { return nil }
        return covers.cachedImage(for: coverID)
    }

    /// Preview for the banner editor: only a custom banner (not the cover).
    func bannerPreview(for book: DashboardBook) -> NSImage? {
        store.bannerImage(for: book)
    }

    // MARK: - Built-in books

    func toggleHidden(_ book: DashboardBook) {
        guard book.kind == .builtIn else { return }
        var current = hidden.wrappedValue
        if current.ids.contains(book.id) {
            current.ids.remove(book.id)
        } else {
            current.ids.insert(book.id)
            if selectedID.wrappedValue == book.id {
                selectedID.wrappedValue = ""
            }
        }
        hidden.wrappedValue = current
        objectWillChange.send()
    }

    // MARK: - Custom books

    func delete(_ book: DashboardBook) {
        guard book.kind == .custom, let stored = customBook(withID: book.id) else { return }
        if selectedID.wrappedValue == stored.id {
            selectedID.wrappedValue = ""
        }
        store.delete(id: stored.id)  // also removes the banner file
        if let coverID = stored.coverID, !store.customBooks.contains(where: { $0.coverID == coverID }) {
            covers.removeCover(for: coverID)
        }
    }

    /// Sets an exact, user-typed word count (`.userOverride`), keeping the estimate and page count.
    /// Returns false (and changes nothing) for garbage input or built-in books.
    @discardableResult
    func saveWordCount(_ text: String, for book: DashboardBook) -> Bool {
        guard book.kind == .custom, var stored = customBook(withID: book.id),
            let words = AddBookViewModel.parseWordCount(text)
        else { return false }
        stored.wordCount = words
        stored.wordCountSource = .userOverride
        store.update(stored)
        return true
    }

    func canResetToEstimate(_ book: DashboardBook) -> Bool {
        guard book.kind == .custom, let stored = customBook(withID: book.id) else { return false }
        return stored.wordCountSource == .userOverride && stored.estimatedWordCount != nil && stored.pageCount != nil
    }

    func resetToEstimate(_ book: DashboardBook) {
        guard canResetToEstimate(book), var stored = customBook(withID: book.id),
            let estimate = stored.estimatedWordCount, let pages = stored.pageCount
        else { return }
        stored.wordCount = estimate
        // The provider is lost on override and never shown, so restore the default.
        stored.wordCountSource = .estimatedFromPages(pages: pages, provider: .openLibrary)
        store.update(stored)
    }

    // MARK: - Banners (any book)

    /// `data` must already be normalised by `BannerImageImporter` (via `BookBannerEditorModel`).
    func applyBanner(_ data: Data, to book: DashboardBook) throws {
        try store.setBanner(data, forBookID: book.id)
    }

    func removeBanner(from book: DashboardBook) {
        store.removeBanner(forBookID: book.id)
    }

    // MARK: - Labels

    func sourceLabel(for book: DashboardBook) -> String {
        switch book.wordCountSource {
        case .curated:
            return String(localized: "curated")
        case .estimatedFromPages(let pages, _):
            return String(localized: "estimated from \(pages) pages")
        case .userOverride:
            return String(localized: "exact (you entered)")
        }
    }

    private func customBook(withID id: String) -> DashboardBook? {
        store.customBooks.first { $0.id == id }
    }
}

// MARK: - Panel

struct ManageBooksPanel: View {
    @ObservedObject var viewModel: ManageBooksViewModel
    let onClose: () -> Void
    let onAddBook: () -> Void

    init(viewModel: ManageBooksViewModel, onClose: @escaping () -> Void = {}, onAddBook: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onAddBook = onAddBook
    }

    var body: some View {
        QuickPanelScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    section(title: "Your books", books: viewModel.yourBooks, emptyText: "No custom books yet.")
                    section(title: "Built-in books", books: viewModel.builtInBooks, emptyText: nil)
                }
                .padding(.horizontal, 18)
                .padding(.top, 76)
                .padding(.bottom, 72)
            }
        } header: {
            ModelInsightPanelHeader(title: "Manage Books", onClose: onClose)
        } footer: {
            HStack {
                Spacer()
                Button("Add Book…", action: onAddBook)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .frame(height: QuickPanelMetrics.footerHeight)
        }
        .background(AppTheme.Insights.page)
    }

    @ViewBuilder
    private func section(title: LocalizedStringKey, books: [DashboardBook], emptyText: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            if books.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ForEach(books) { book in
                ManageBookRow(viewModel: viewModel, book: book)
            }
        }
    }
}

private struct ManageBookRow: View {
    @ObservedObject var viewModel: ManageBooksViewModel
    let book: DashboardBook

    @State private var showsWordCountEditor = false
    @State private var showsBannerEditor = false
    @State private var showsDeleteConfirmation = false

    private var isCustom: Bool { book.kind == .custom }
    private var isHidden: Bool { viewModel.isHidden(book) }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: book.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                if let author = book.author, !author.isEmpty {
                    Text(verbatim: author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(verbatim: wordCountLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            actions
        }
        .padding(10)
        .background(AppCardBackground(isSelected: false, cornerRadius: 12))
        .opacity(isHidden ? 0.55 : 1)
        .confirmationDialog(
            Text("Delete this book?"),
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { viewModel.delete(book) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(book.displayTitle)” and its custom banner will be removed.")
        }
    }

    private var wordCountLine: String {
        let words = Formatters.formattedNumber(book.wordCount)
        let count = book.isEstimate ? String(localized: "~\(words) words") : String(localized: "\(words) words")
        return "\(count) · \(viewModel.sourceLabel(for: book))"
    }

    private var thumbnail: some View {
        Group {
            if let image = viewModel.thumbnail(for: book) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.1))
            }
        }
        .frame(width: 32, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if isCustom {
                Button { showsWordCountEditor = true } label: {
                    Image(systemName: "pencil")
                }
                .help(String(localized: "Edit word count…"))
                .accessibilityLabel(Text("Edit word count…"))
                .popover(isPresented: $showsWordCountEditor, arrowEdge: .bottom) {
                    WordCountEditor(viewModel: viewModel, book: book) { showsWordCountEditor = false }
                }
            } else {
                Button { viewModel.toggleHidden(book) } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                }
                .help(isHidden ? String(localized: "Show") : String(localized: "Hide"))
                .accessibilityLabel(isHidden ? Text("Show") : Text("Hide"))
            }

            Button { showsBannerEditor = true } label: {
                Image(systemName: "photo")
            }
            .help(String(localized: "Banner…"))
            .accessibilityLabel(Text("Banner…"))
            .popover(isPresented: $showsBannerEditor, arrowEdge: .bottom) {
                BannerPopover(viewModel: viewModel, book: book)
            }

            if isCustom {
                Button(role: .destructive) { showsDeleteConfirmation = true } label: {
                    Image(systemName: "trash")
                }
                .help(String(localized: "Delete"))
                .accessibilityLabel(Text("Delete"))
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct WordCountEditor: View {
    @ObservedObject var viewModel: ManageBooksViewModel
    let book: DashboardBook
    let onDone: () -> Void

    @State private var text: String

    init(viewModel: ManageBooksViewModel, book: DashboardBook, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.book = book
        self.onDone = onDone
        _text = State(initialValue: String(book.wordCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exact word count")
                .font(.system(size: 13, weight: .medium))
            TextField("Word count", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                if viewModel.canResetToEstimate(book) {
                    Button("Reset to estimate") {
                        viewModel.resetToEstimate(book)
                        onDone()
                    }
                }
                Spacer()
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(AddBookViewModel.parseWordCount(text) == nil)
            }
        }
        .padding(14)
        .frame(width: 260)
    }

    private func save() {
        if viewModel.saveWordCount(text, for: book) {
            onDone()
        }
    }
}

private struct BannerPopover: View {
    @ObservedObject var viewModel: ManageBooksViewModel
    let book: DashboardBook

    @StateObject private var editorModel = BookBannerEditorModel(importer: BannerImageImporter())
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookBannerEditor(
                model: editorModel,
                hasCustomBanner: book.customBannerFile != nil,
                previewImage: viewModel.bannerPreview(for: book),
                onPrepared: { data in
                    do {
                        try viewModel.applyBanner(data, to: book)
                        saveError = nil
                    } catch {
                        saveError = String(localized: "Couldn't save that image.")
                    }
                },
                onRemove: { viewModel.removeBanner(from: book) }
            )
            if let saveError {
                Text(verbatim: saveError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 320)
        .onDisappear { editorModel.cancel() }
    }
}
