import AppKit
import os
import SwiftUI

// MARK: - View model

/// Search, pick and add flow for the Add Book sheet (spec §8.3/§8.4).
///
/// Nothing is written to the store until `add()`, `submitManualWordCount(_:)` or `addManually(…)`
/// succeeds, so dismissing the sheet discards every pending search result and prepared banner.
@MainActor
final class AddBookViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded([BookSearchResult])
        case empty
        case failed(BookSearchError)
        /// The picked result has no page count anywhere; the user must type a word count.
        case needsWordCount(BookSearchResult)
    }

    static let minimumQueryLength = 3
    /// Sanity bound on provider page counts so `pages * 275` can never overflow.
    private static let maximumPlausiblePages = 100_000

    @Published var query = ""
    @Published private(set) var state: State = .idle
    @Published var selected: BookSearchResult?
    @Published var preparedBannerData: Data?
    @Published private(set) var isAdding = false

    let bannerEditor: BookBannerEditorModel

    private let store: DashboardBookStore
    private let search: BookSearching
    private let pageCounts: PageCountProviding
    private let covers: BookCoverCache
    private let debounce: Duration
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AddBookViewModel")

    private var searchTask: Task<Void, Never>?
    private var generation = 0
    /// Bumped by `cancel()`; an `add()` that started before it must not write or report success.
    private var addEpoch = 0

    init(
        store: DashboardBookStore,
        search: BookSearching,
        pageCounts: PageCountProviding,
        covers: BookCoverCache,
        bannerEditor: BookBannerEditorModel,
        debounce: Duration = .milliseconds(400)
    ) {
        self.store = store
        self.search = search
        self.pageCounts = pageCounts
        self.covers = covers
        self.bannerEditor = bannerEditor
        self.debounce = debounce
    }

    // MARK: Search

    /// Call whenever `query` changes: cancels the previous search and schedules a debounced one.
    func queryChanged() {
        searchTask?.cancel()
        generation += 1
        let trimmed = trimmedQuery
        guard trimmed.count >= Self.minimumQueryLength else {
            searchTask = nil
            selected = nil
            state = .idle
            return
        }
        let token = generation
        let delay = debounce
        searchTask = Task {
            if delay > .zero {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            await performSearch(trimmed, token: token)
        }
    }

    /// Re-runs the current query immediately (no debounce).
    func retry() {
        searchTask?.cancel()
        generation += 1
        let trimmed = trimmedQuery
        guard trimmed.count >= Self.minimumQueryLength else {
            searchTask = nil
            state = .idle
            return
        }
        let token = generation
        searchTask = Task { await performSearch(trimmed, token: token) }
    }

    /// Waits for the scheduled search, if any (tests).
    func settle() async {
        await searchTask?.value
    }

    /// Discards everything pending; call when the sheet is dismissed without adding.
    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        generation += 1
        addEpoch += 1
        bannerEditor.cancel()
        preparedBannerData = nil
        selected = nil
    }

    func isAlreadyAdded(_ result: BookSearchResult) -> Bool {
        store.contains(workKey: result.workKey)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performSearch(_ title: String, token: Int) async {
        guard token == generation else { return }
        state = .loading
        do {
            let results = try await search.search(title: title)
            guard token == generation else { return }
            if let current = selected, !results.contains(current) { selected = nil }
            state = results.isEmpty ? .empty : .loaded(results)
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            selected = nil
            state = .failed(Self.searchError(from: error))
        }
    }

    private static func searchError(from error: Error) -> BookSearchError {
        if let searchError = error as? BookSearchError { return searchError }
        if error is URLError { return .offline }
        return .decoding
    }

    // MARK: Adding

    /// Adds the selected result. Returns nil when nothing is selected, the result is a duplicate, or no
    /// page count is available (then `state` becomes `.needsWordCount`; read it to tell the cases apart).
    func add() async -> DashboardBook? {
        guard !isAdding, let result = selected, !isAlreadyAdded(result) else { return nil }
        isAdding = true
        defer { isAdding = false }
        let epoch = addEpoch

        var pages = Self.plausible(result.pagesMedian)
        var provider = DashboardBook.PageCountProvider.openLibrary
        if pages == nil, GoogleBooksPageCountService.isGoogleBooksFallbackEnabled {
            let fallback = await pageCounts.pageCount(title: result.title, author: result.authors.first)
            if let fallback = Self.plausible(fallback) {
                pages = fallback
                provider = .googleBooks
            }
        }
        guard epoch == addEpoch, !Task.isCancelled else { return nil }
        guard !isAlreadyAdded(result) else { return nil }
        guard let pages else {
            state = .needsWordCount(result)
            return nil
        }

        let words = DashboardBookEstimation.words(forPages: pages)
        let book = makeBook(
            title: result.title,
            author: result.authors.first,
            wordCount: words,
            source: .estimatedFromPages(pages: pages, provider: provider),
            estimatedWordCount: words,
            pageCount: pages,
            workKey: result.workKey,
            coverID: result.coverID
        )
        return commit(book)
    }

    /// Completes a pick that had no page count with a user-typed exact word count (integer > 0).
    func submitManualWordCount(_ text: String) async -> DashboardBook? {
        guard !isAdding, case .needsWordCount(let result) = state,
            !isAlreadyAdded(result), let words = Self.parseWordCount(text)
        else { return nil }

        let book = makeBook(
            title: result.title,
            author: result.authors.first,
            wordCount: words,
            source: .userOverride,
            estimatedWordCount: nil,
            pageCount: nil,
            workKey: result.workKey,
            coverID: result.coverID
        )
        return commit(book)
    }

    /// Offline escape hatch: a title and an exact word count, no cover, no work key.
    func addManually(title: String, wordCountText: String) -> DashboardBook? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let words = Self.parseWordCount(wordCountText) else { return nil }

        let book = makeBook(
            title: trimmedTitle,
            author: nil,
            wordCount: words,
            source: .userOverride,
            estimatedWordCount: nil,
            pageCount: nil,
            workKey: nil,
            coverID: nil
        )
        return commit(book)
    }

    // MARK: Helpers

    /// Only plain ASCII digits forming an `Int` > 0 are accepted ("12.5", "1,000", "-5", "+5" are not).
    static func parseWordCount(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
            let value = Int(trimmed), value > 0
        else { return nil }
        return value
    }

    private static func plausible(_ pages: Int?) -> Int? {
        guard let pages, (1...maximumPlausiblePages).contains(pages) else { return nil }
        return pages
    }

    private func makeBook(
        title: String,
        author: String?,
        wordCount: Int,
        source: DashboardBook.WordCountSource,
        estimatedWordCount: Int?,
        pageCount: Int?,
        workKey: String?,
        coverID: Int?
    ) -> DashboardBook {
        DashboardBook(
            id: "custom.\(UUID().uuidString)",
            kind: .custom,
            title: title,
            author: author,
            wordCount: wordCount,
            wordCountSource: source,
            estimatedWordCount: estimatedWordCount,
            pageCount: pageCount,
            openLibraryWorkKey: workKey,
            coverID: coverID,
            coverTint: nil,
            customBannerFile: nil,
            addedAt: Date()
        )
    }

    /// Writes the book, applies the prepared banner (always already normalised by the importer), and kicks
    /// off the background cover fetch when the book has a cover but no banner.
    private func commit(_ book: DashboardBook) -> DashboardBook {
        store.add(book)

        var hasBanner = false
        if let data = preparedBannerData {
            do {
                try store.setBanner(data, forBookID: book.id)
                hasBanner = true
            } catch {
                logger.error("Could not save prepared banner: \(String(describing: error), privacy: .public)")
            }
        }
        preparedBannerData = nil

        if !hasBanner, let coverID = book.coverID {
            let store = store
            let covers = covers
            let bookID = book.id
            Task {
                guard let image = await covers.image(for: coverID),
                    let tint = ImageTint.averageColor(of: image)
                else { return }
                store.setCoverTint(tint, forBookID: bookID)
            }
        }

        return store.customBooks.first { $0.id == book.id } ?? book
    }
}

// MARK: - Sheet

struct AddBookSheet: View {
    let onAdded: (DashboardBook) -> Void

    @StateObject private var viewModel: AddBookViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var manualWordCount = ""
    @State private var showsManualForm = false
    @State private var manualTitle = ""
    @State private var manualCount = ""
    @State private var showsBannerEditor = false
    @State private var addTask: Task<Void, Never>?

    init(onAdded: @escaping (DashboardBook) -> Void) {
        self.onAdded = onAdded
        _viewModel = StateObject(
            wrappedValue: AddBookViewModel(
                store: .shared,
                search: OpenLibraryBookSearchService(),
                pageCounts: GoogleBooksPageCountService(),
                covers: .shared,
                bannerEditor: BookBannerEditorModel(importer: BannerImageImporter())
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .overlay(Divider().opacity(0.5), alignment: .bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showsManualForm {
                        manualForm
                    } else {
                        searchField
                        content
                        if viewModel.selected != nil { bannerSection }
                    }
                }
                .padding()
            }
        }
        .frame(width: 460, height: 520)
        .onDisappear {
            addTask?.cancel()
            viewModel.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Text("Add Book")
                .font(.headline)

            Spacer()

            if !showsManualForm, !isAwaitingWordCount {
                Button {
                    addSelected()
                } label: {
                    if viewModel.isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.selected == nil || viewModel.isAdding)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(AppCardBackground(isSelected: false, cornerRadius: 16))
    }

    // MARK: Search

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Book title", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.query) { _, _ in viewModel.queryChanged() }
            Text(footnote)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footnote: String {
        if GoogleBooksPageCountService.isGoogleBooksFallbackEnabled {
            return String(
                localized:
                    "Searches Open Library over the internet. Only the title you type is sent; page counts may come from Google Books."
            )
        }
        return String(localized: "Searches Open Library over the internet. Only the title you type is sent.")
    }

    private var isAwaitingWordCount: Bool {
        if case .needsWordCount = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            Text("Type at least 3 letters of a book title to search.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        case .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        case .loaded(let results):
            LazyVStack(spacing: 6) {
                ForEach(results) { result in
                    resultRow(result)
                }
            }
        case .empty:
            messageBlock(String(localized: "No books found. Try a shorter title."), showsRetry: false)
        case .failed(let error):
            switch error {
            case .offline, .timedOut:
                messageBlock(
                    String(localized: "Can't reach Open Library. Check your connection, or add the book manually."),
                    showsRetry: true)
            case .http, .decoding:
                messageBlock(String(localized: "Search failed."), showsRetry: true, showsManual: false)
            }
        case .needsWordCount(let result):
            wordCountForm(for: result)
        }
    }

    private func messageBlock(_ text: String, showsRetry: Bool, showsManual: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                if showsRetry {
                    Button("Retry") { viewModel.retry() }
                }
                if showsManual {
                    Button("Add manually…") { showsManualForm = true }
                }
            }
        }
    }

    private func resultRow(_ result: BookSearchResult) -> some View {
        let isAdded = viewModel.isAlreadyAdded(result)
        let isSelected = viewModel.selected == result
        return Button {
            viewModel.selected = result
        } label: {
            HStack(spacing: 10) {
                thumbnail(for: result)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: result.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    if let detail = detailLine(for: result) {
                        Text(verbatim: detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: trailingLabel(for: result, isAdded: isAdded))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .opacity(isAdded ? 0.55 : 1)
    }

    private func thumbnail(for result: BookSearchResult) -> some View {
        let placeholder = RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.primary.opacity(0.1))
        return Group {
            if let coverID = result.coverID,
                let url = URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-S.jpg?default=false")
            {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 32, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func detailLine(for result: BookSearchResult) -> String? {
        var parts: [String] = []
        if let author = result.authors.first { parts.append(author) }
        if let year = result.firstPublishYear { parts.append(String(year)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trailingLabel(for result: BookSearchResult, isAdded: Bool) -> String {
        if isAdded { return String(localized: "Already added") }
        guard let pages = result.pagesMedian, pages > 0 else { return String(localized: "No page count") }
        let words = Formatters.formattedNumber(DashboardBookEstimation.words(forPages: pages))
        return String(localized: "~\(words) words")
    }

    // MARK: Word count (no page count found)

    private func wordCountForm(for result: BookSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: result.title)
                .font(.system(size: 13, weight: .medium))
            Text("We couldn't find a page count. Enter the word count:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack {
                TextField("Word count", text: $manualWordCount)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submitWordCount)
                Button("Add", action: submitWordCount)
                    .buttonStyle(.borderedProminent)
                    .disabled(AddBookViewModel.parseWordCount(manualWordCount) == nil || viewModel.isAdding)
            }
        }
    }

    private func submitWordCount() {
        let text = manualWordCount
        Task {
            if let book = await viewModel.submitManualWordCount(text) {
                onAdded(book)
                dismiss()
            }
        }
    }

    // MARK: Banner

    private var bannerSection: some View {
        DisclosureGroup(isExpanded: $showsBannerEditor) {
            VStack(alignment: .leading, spacing: 8) {
                BookBannerEditor(
                    model: viewModel.bannerEditor,
                    hasCustomBanner: viewModel.preparedBannerData != nil,
                    previewImage: viewModel.preparedBannerData.flatMap { NSImage(data: $0) },
                    onPrepared: { viewModel.preparedBannerData = $0 },
                    onRemove: { viewModel.preparedBannerData = nil }
                )
            }
            .padding(.top, 6)
        } label: {
            Text("Banner image (optional)")
                .font(.system(size: 13, weight: .medium))
        }
    }

    // MARK: Manual

    private var manualForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a book manually")
                .font(.headline)
            TextField("Book title", text: $manualTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Word count", text: $manualCount)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addManually)
            HStack {
                Button("Back") { showsManualForm = false }
                Spacer()
                Button("Add", action: addManually)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || AddBookViewModel.parseWordCount(manualCount) == nil)
            }
            bannerSection
        }
    }

    // MARK: Actions

    private func addSelected() {
        addTask?.cancel()
        addTask = Task {
            if let book = await viewModel.add() {
                onAdded(book)
                dismiss()
            }
        }
    }

    private func addManually() {
        if let book = viewModel.addManually(title: manualTitle, wordCountText: manualCount) {
            onAdded(book)
            dismiss()
        }
    }
}
