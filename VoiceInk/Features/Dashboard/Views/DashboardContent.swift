import Foundation
import SwiftData
import SwiftUI
import os

struct DashboardContent: View {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DashboardContent")
    private static let fallbackDisplayName = String(localized: "there")
    private static let displayNameFontSize: CGFloat = 28
    private static let displayNameFontWeight: NSFont.Weight = .bold
    private static let displayNameMinWidth: CGFloat = 72
    private static let displayNameMaxWidth: CGFloat = 280
    private static let displayNameHorizontalPadding: CGFloat = 8
    private static let insightsUnlockDuration: TimeInterval = 30 * 60
    private static let peakHoursUnlockDuration: TimeInterval = 30 * 60
    private static let reviewBacklogActionThreshold = 50
    // Above this count, skip live auto-refresh (full reload is expensive); tab reopen still refreshes.
    private static let automaticStatsRefreshMetricLimit = 2_000
    private static let statsRefreshDebounceNanoseconds: UInt64 = 750_000_000
    let modelContext: ModelContext
    let licenseState: LicenseViewModel.LicenseState
    let onAddLicenseKey: () -> Void

    @State private var statsSummary: DashboardStatsSummary = .empty
    @State private var hasLoadedStatsSnapshot: Bool = false
    @State private var statsSnapshotGeneratedAt: Date?
    @State private var isDashboardStatsRefreshing = false
    @State private var dashboardStatsTask: Task<Void, Never>?
    @State private var dashboardStatsLoadGeneration = 0
    @State private var isModelPerformancePanelPresented = false
    @State private var isModelUsagePanelPresented = false
    @State private var isAutoLearnFailurePanelPresented = false
    @State private var isAutoLearnReviewPanelPresented = false
    @State private var autoLearnReviewBacklogCount = 0
    @State private var autoLearnBacklogRefreshGeneration = 0
    @State private var autoLearnFailurePresentationTask: Task<Void, Never>?
    @State private var isInsightsViewPresented = false
    @State private var selectedInsightPeriod: DashboardInsightPeriod = .allTime
    @State private var isAccessibilityEnabled = AXIsProcessTrusted()
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @ObservedObject private var modeManager = ModeManager.shared
    @ObservedObject private var starPrompt = GitHubStarPromptCoordinator.shared
    @State private var isSystemInfoCopied = false
    @State private var isEditingDisplayName = false
    @State private var displayNameDraft = ""
    @AppStorage("dashboardDisplayName") private var dashboardDisplayName: String = ""
    @AppStorage(AutoLearnSettings.isEnabledKey) private var isAutoLearnEnabled = true
    @AppStorage(AutoLearnSettings.hasFailureKey) private var hasAutoLearnFailure = false
    @AppStorage(AutoLearnSettings.failureAcknowledgedKey) private var isAutoLearnFailureAcknowledged = false
    @AppStorage("dashboardSelectedBookID") private var selectedBookID: String = ""
    @AppStorage("dashboardHiddenBuiltInBookIDs") private var hiddenBooks = HiddenBookIDs()
    @ObservedObject private var bookStore = DashboardBookStore.shared
    @State private var isAddBookSheetPresented = false
    @State private var isManageBooksPanelPresented = false
    @State private var manageBooksViewModel: ManageBooksViewModel?
    /// Bumped when a background cover fetch lands so the hero re-reads the (disk-only) cover cache.
    @State private var coverRevision = 0
    /// Books whose cover fetch was already attempted this app session (no retry after failure).
    private static var coverFetchAttempts = Set<String>()
    @FocusState private var isNameFieldFocused: Bool
    @Query(Self.recentTranscriptionsDescriptor()) private var recentTranscriptionCandidates: [Transcription]

    private static func recentTranscriptionsDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 25
        return descriptor
    }

    init(
        modelContext: ModelContext,
        licenseState: LicenseViewModel.LicenseState,
        onAddLicenseKey: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.licenseState = licenseState
        self.onAddLicenseKey = onAddLicenseKey

        let cachedSummary = DashboardStatsCache.shared.currentSummary()
        let cachedMetadata = DashboardStatsCache.shared.currentMetadata()
        _statsSummary = State(initialValue: cachedSummary ?? .empty)
        _hasLoadedStatsSnapshot = State(initialValue: cachedSummary != nil)
        _statsSnapshotGeneratedAt = State(initialValue: cachedMetadata?.generatedAt)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = DashboardLayout.contentWidth(for: geometry.size.width)

            ZStack(alignment: .top) {
                if isInsightsViewPresented && canViewInsights {
                    AppTheme.Insights.page
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                } else {
                    DashboardAmbientBackground()
                }

                ScrollView {
                    Group {
                        if isInsightsViewPresented && canViewInsights {
                            dashboardInsightsView
                        } else {
                            dashboardMainContent(availableWidth: contentWidth)
                        }
                    }
                    .frame(width: contentWidth, alignment: .top)
                    .frame(
                        minHeight: max(0, geometry.size.height - DashboardLayout.contentBottomOffset),
                        alignment: .top
                    )
                    .padding(.vertical, DashboardLayout.pageVerticalPadding)
                    .padding(.horizontal, DashboardLayout.pageHorizontalPadding)
                }
            }
        }
        .task {
            scheduleDashboardStatsRefresh(allowSkipWhenFresh: hasLoadedStatsSnapshot)
        }
        .task {
            await refreshAutoLearnReviewBacklogCount()
        }
        .onAppear {
            refreshAccessibilityStatus()
            updaterViewModel.checkForUpdatesIfDue()
            if shouldAutomaticallyPresentAutoLearnFailure {
                scheduleAutoLearnFailurePresentation()
            }
        }
        .onChange(of: hasAutoLearnFailure) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnEnabled) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnFailureAcknowledged) { _, _ in
            updateAutoLearnFailurePresentation()
        }
        .onChange(of: isAutoLearnFailurePanelPresented) { wasPresented, isPresented in
            if wasPresented, !isPresented, hasAutoLearnFailure, isAutoLearnEnabled {
                AutoLearnSettings.acknowledgeCurrentFailure()
            }
        }
        .onReceive(LifecycleObserver.shared.publisher(for: .applicationDidBecomeActive)) { _ in
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionMetricsDidChange)) { _ in
            DashboardStatsCache.shared.markStale()

            if shouldRefreshStatsAfterMetricChange {
                scheduleDashboardStatsRefresh(debounce: true, allowSkipWhenFresh: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .autoLearnQueueDidChange)) { _ in
            scheduleAutoLearnReviewBacklogRefresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .autoLearnReviewProposalsDidChange)
        ) { _ in
            scheduleAutoLearnReviewBacklogRefresh()
        }
        .onDisappear {
            dashboardStatsTask?.cancel()
            dashboardStatsTask = nil
            dashboardStatsLoadGeneration += 1
            isDashboardStatsRefreshing = false
            autoLearnFailurePresentationTask?.cancel()
            autoLearnFailurePresentationTask = nil
        }
        .onAppear {
            clearStaleBookSelection()
            ensureCoverTint()
        }
        .onChange(of: visibleBooks.map(\.id)) { _, _ in
            clearStaleBookSelection()
        }
        .onChange(of: resolvedBook?.book.id) { _, _ in
            ensureCoverTint()
        }
        .onChange(of: bookStore.customBooks) { _, _ in
            ensureCoverTint()
        }
        .onChange(of: bookStore.builtInArt) { _, _ in
            ensureCoverTint()
        }
        .sheet(isPresented: $isAddBookSheetPresented) {
            AddBookSheet { book in
                selectedBookID = book.id
            }
        }
        .sidePanel(isPresented: $isModelPerformancePanelPresented) {
            ModelPerformancePanel(
                summaries: selectedModelPerformance
            ) {
                isModelPerformancePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isModelUsagePanelPresented) {
            ModelUsagePanel(
                summary: selectedModelUsage
            ) {
                isModelUsagePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isAutoLearnFailurePanelPresented) {
            AutoLearnFailurePanel {
                isAutoLearnFailurePanelPresented = false
            }
        }
        .sidePanel(isPresented: $isAutoLearnReviewPanelPresented) {
            AutoLearnReviewPanel {
                isAutoLearnReviewPanelPresented = false
            }
        }
        .sidePanel(isPresented: $isManageBooksPanelPresented) {
            if let manageBooksViewModel {
                ManageBooksPanel(
                    viewModel: manageBooksViewModel,
                    onClose: { isManageBooksPanelPresented = false },
                    onAddBook: { isAddBookSheetPresented = true }
                )
            }
        }
    }

    private func scheduleAutoLearnFailurePresentation() {
        autoLearnFailurePresentationTask?.cancel()
        autoLearnFailurePresentationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, shouldAutomaticallyPresentAutoLearnFailure else { return }
            isAutoLearnFailurePanelPresented = true
            autoLearnFailurePresentationTask = nil
        }
    }

    private var shouldAutomaticallyPresentAutoLearnFailure: Bool {
        hasAutoLearnFailure && isAutoLearnEnabled && !isAutoLearnFailureAcknowledged
    }

    private var dashboardReviewCorrectionCount: Int? {
        guard isAutoLearnEnabled,
            autoLearnReviewBacklogCount > Self.reviewBacklogActionThreshold
        else {
            return nil
        }
        return autoLearnReviewBacklogCount
    }

    @MainActor
    private func refreshAutoLearnReviewBacklogCount() async {
        let generation = autoLearnBacklogRefreshGeneration
        let queuedCount = (try? await AutoLearnService.shared.outstandingReviewCount()) ?? 0
        let proposalCount = (try? await AutoLearnService.shared.reviewProposalCount()) ?? 0
        guard generation == autoLearnBacklogRefreshGeneration else { return }
        autoLearnReviewBacklogCount = queuedCount + proposalCount
    }

    private func scheduleAutoLearnReviewBacklogRefresh() {
        autoLearnBacklogRefreshGeneration += 1
        Task { await refreshAutoLearnReviewBacklogCount() }
    }

    private func updateAutoLearnFailurePresentation() {
        if shouldAutomaticallyPresentAutoLearnFailure {
            scheduleAutoLearnFailurePresentation()
        } else {
            autoLearnFailurePresentationTask?.cancel()
            autoLearnFailurePresentationTask = nil
            isAutoLearnFailurePanelPresented = false
        }
    }

    private func dashboardMainContent(availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DashboardLayout.sectionSpacing) {
            licenseStatusMessage

            greetingHeader

            nameEditorDismissArea {
                heroSection
            }

            if !isAccessibilityEnabled {
                nameEditorDismissArea {
                    accessibilityReminder
                }
            }

            if !modeManager.hasEnabledConfiguration {
                nameEditorDismissArea {
                    DashboardNoModesReminder(onOpenModes: ModeSetupNavigator.openModesSettings)
                }
            }

            if !recentDashboardTranscriptions.isEmpty {
                nameEditorDismissArea {
                    DashboardTranscriptCards(transcriptions: recentDashboardTranscriptions)
                }
            }

            Spacer(minLength: DashboardLayout.footerTopSpacing)

            nameEditorDismissArea {
                HStack {
                    Spacer()
                    footerActionsView
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: availableWidth, alignment: .topLeading)
    }

    private var recentDashboardTranscriptions: [Transcription] {
        Array(
            recentTranscriptionCandidates
                .filter { transcription in
                    isRecentDashboardTranscription(transcription)
                }
                .prefix(5)
        )
    }

    private func isRecentDashboardTranscription(_ transcription: Transcription) -> Bool {
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        if transcription.transcriptionStatus == TranscriptionStatus.failed.rawValue
            || transcription.transcriptionStatus == TranscriptionStatus.canceled.rawValue
        {
            return false
        }

        return text.range(of: "Transcription Failed:", options: [.caseInsensitive, .anchored]) == nil
    }

    private var selectedDailyActivityPoints: [DashboardProductivityPoint] {
        statsSummary.dailyActivity(for: selectedInsightPeriod)
    }

    private var selectedModelPerformance: [ModelPerformanceSummary] {
        statsSummary.modelPerformance(for: selectedInsightPeriod)
    }

    private var selectedModelUsage: ModelUsageSummary {
        statsSummary.modelUsage(for: selectedInsightPeriod)
    }

    private var selectedPeakHours: DashboardPeakHoursSummary {
        statsSummary.peakHours(for: selectedInsightPeriod)
    }

    private var selectedTotals: DashboardMetricTotals {
        statsSummary.totals(for: selectedInsightPeriod)
    }

    private var selectedTimeSavedSummary: DashboardTimeSavedSummary {
        return DashboardTimeSavedSummary(
            timeSaved: DashboardTimeSaving.timeSaved(words: selectedTotals.words, duration: selectedTotals.duration),
            wordCount: selectedTotals.words,
            sessionCount: selectedTotals.count
        )
    }

    private var canViewInsights: Bool {
        #if LOCAL_BUILD
            hasLoadedStatsSnapshot
        #else
            hasLoadedStatsSnapshot && statsSummary.totalDuration >= Self.insightsUnlockDuration
        #endif
    }

    private var shouldShowLockedInsightsState: Bool {
        hasLoadedStatsSnapshot && !canViewInsights
    }

    private var canViewPeakHours: Bool {
        #if LOCAL_BUILD
            hasLoadedStatsSnapshot && selectedPeakHours.hasData
        #else
            hasLoadedStatsSnapshot && selectedTotals.duration >= Self.peakHoursUnlockDuration && selectedPeakHours.hasData
        #endif
    }

    private var shouldLockPeakHours: Bool {
        hasLoadedStatsSnapshot && !canViewPeakHours
    }

    private var shouldRefreshStatsAfterMetricChange: Bool {
        !hasLoadedStatsSnapshot || statsSummary.totalCount < Self.automaticStatsRefreshMetricLimit
    }

    private var insightsActionTitle: LocalizedStringKey {
        canViewInsights ? "View Insights" : "Insights Locked"
    }

    private var insightsActionIcon: String {
        canViewInsights ? "chart.line.uptrend.xyaxis" : "lock.fill"
    }

    private var insightsActionHelp: String {
        if canViewInsights {
            return String(localized: "View dashboard insights")
        }

        return String(localized: "Continue using VoiceInk to unlock these stats.")
    }

    private var insightsActionAccessibilityLabel: String {
        canViewInsights ? "View insights" : "Insights locked"
    }

    private var accessibilityReminder: some View {
        DashboardAccessibilityReminder(onOpenSettings: openAccessibilitySettings)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(greetingEmoji)
                    .font(.system(size: 25))
                    .accessibilityHidden(true)

                Text("\(greetingText),")
                    .font(displayNameFont)
                    .foregroundStyle(AppTheme.Text.primary)
                    .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)

                displayNameView

                dismissingSpacer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            HStack(alignment: .top, spacing: 0) {
                Text(headerSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Text.secondary)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var displayNameView: some View {
        if isEditingDisplayName {
            TextField("your name", text: displayNameBinding)
                .textFieldStyle(.plain)
                .font(displayNameFont)
                .foregroundStyle(AppTheme.Text.primary)
                .focused($isNameFieldFocused)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .padding(.horizontal, Self.displayNameHorizontalPadding)
                .padding(.vertical, 3)
                .background(AppTheme.Accent.fill)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(AppTheme.Accent.border, lineWidth: 1)
                )
                .onSubmit(finishEditingDisplayName)
                .onChange(of: isNameFieldFocused) { _, isFocused in
                    if !isFocused {
                        finishEditingDisplayName()
                    }
                }
        } else {
            Text(defaultedDisplayName)
                .font(displayNameFont)
                .foregroundStyle(AppTheme.Text.primary)
                .lineLimit(1)
                .frame(width: displayNameFieldWidth, alignment: .leading)
                .help("Click to edit dashboard name")
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditingDisplayName)
        }
    }

    private var displayNameFont: Font {
        .system(size: Self.displayNameFontSize, weight: .bold, design: .rounded)
    }

    private var dismissingSpacer: some View {
        Spacer(minLength: 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
    }

    private func nameEditorDismissArea<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .onTapGesture(perform: dismissDisplayNameEditorIfNeeded)
    }

    private func refreshAccessibilityStatus() {
        isAccessibilityEnabled = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInsightsIfAvailable() {
        guard canViewInsights else {
            return
        }

        isInsightsViewPresented = true
    }

    private func openModelPerformancePanel() {
        isModelPerformancePanelPresented = true
    }

    private func openModelUsagePanel() {
        isModelUsagePanelPresented = true
    }

    private func openAutoLearnReviewPanel() {
        isAutoLearnReviewPanelPresented = true
    }

    @MainActor
    private func scheduleDashboardStatsRefresh(
        debounce: Bool = false,
        allowSkipWhenFresh: Bool = false
    ) {
        dashboardStatsTask?.cancel()
        dashboardStatsLoadGeneration += 1

        let generation = dashboardStatsLoadGeneration
        let modelContainer = modelContext.container

        dashboardStatsTask = Task {
            if debounce {
                try? await Task.sleep(nanoseconds: Self.statsRefreshDebounceNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
            }

            await loadDashboardStatsEfficiently(
                from: modelContainer,
                generation: generation,
                allowSkipWhenFresh: allowSkipWhenFresh
            )
        }
    }

    private func loadDashboardStatsEfficiently(
        from modelContainer: ModelContainer,
        generation: Int,
        allowSkipWhenFresh: Bool
    ) async {
        do {
            if allowSkipWhenFresh {
                let shouldRefreshAutomatically =
                    SessionMetricMigrationService.shared.isRunning
                    || DashboardStatsCache.shared.shouldRefreshSnapshotAutomatically()

                guard shouldRefreshAutomatically else {
                    return
                }
            }

            let shouldStartRefresh = await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return false
                }

                self.isDashboardStatsRefreshing = true
                return true
            }

            guard shouldStartRefresh else {
                return
            }

            let summary = try await DashboardStatsLoader.load(from: modelContainer)

            guard !Task.isCancelled else {
                await finishDashboardStatsRefresh(generation: generation)
                return
            }

            let shouldAcceptSummary = summary.totalCount > 0 || !SessionMetricMigrationService.shared.isRunning

            await MainActor.run {
                guard generation == dashboardStatsLoadGeneration else {
                    return
                }

                self.isDashboardStatsRefreshing = false

                guard shouldAcceptSummary else {
                    return
                }

                self.statsSummary = summary
                let metadata = DashboardStatsCache.shared.update(summary)
                self.statsSnapshotGeneratedAt = metadata.generatedAt
                self.hasLoadedStatsSnapshot = true
            }
        } catch is CancellationError {
            await finishDashboardStatsRefresh(generation: generation)
        } catch {
            await finishDashboardStatsRefresh(generation: generation)
            logger.error("Error loading dashboard stats: \(error, privacy: .public)")
        }
    }

    private func finishDashboardStatsRefresh(generation: Int) async {
        await MainActor.run {
            guard generation == dashboardStatsLoadGeneration else {
                return
            }

            self.isDashboardStatsRefreshing = false
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var licenseStatusMessage: some View {
        switch licenseState {
        case .unlicensed:
            TrialMessageView(
                message: Text("Activate a license to continue using VoiceInk."),
                type: .licenseRequired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trial(let daysRemaining):
            TrialMessageView(
                message: Text(String(localized: "You have \(daysRemaining) days left in your trial")),
                type: daysRemaining <= 2 ? .warning : .info,
                onAddLicenseKey: onAddLicenseKey
            )
        case .trialExpired:
            TrialMessageView(
                message: nil,
                type: .expired,
                onAddLicenseKey: onAddLicenseKey
            )
        case .licensed:
            EmptyView()
        }
    }

    private var dashboardInsightsView: some View {
        DashboardInsightsView(
            selectedPeriod: $selectedInsightPeriod,
            dailyActivityPoints: selectedDailyActivityPoints,
            allTimeDailyActivityPoints: statsSummary.allTimeDailyActivity,
            peakHoursSummary: selectedPeakHours,
            isPeakHoursLocked: shouldLockPeakHours,
            timeSavedSummary: selectedTimeSavedSummary,
            modelUsage: selectedModelUsage,
            modelPerformanceSummaries: selectedModelPerformance,
            onBack: { isInsightsViewPresented = false },
            onViewModelUsage: openModelUsagePanel,
            onViewModelPerformance: openModelPerformancePanel
        )
    }

    private var heroSection: some View {
        let resolved = resolvedBook
        let art = bannerArt(for: resolved?.book)
        return DashboardHeroCard(
            isLocked: shouldShowLockedInsightsState,
            headline: momentumHeadline,
            subtext: momentumSubtext,
            actionTitle: insightsActionTitle,
            actionIcon: insightsActionIcon,
            canViewInsights: canViewInsights,
            actionHelp: insightsActionHelp,
            actionAccessibilityLabel: insightsActionAccessibilityLabel,
            reviewCorrectionCount: dashboardReviewCorrectionCount,
            hasLoadedStats: hasLoadedStatsSnapshot,
            book: resolved?.book,
            progress: resolved.map {
                DashboardProgressBenchmark.progress(words: statsSummary.totalWords, book: $0.book)
            } ?? 0,
            progressRatio: resolved.map {
                DashboardProgressBenchmark.openBookRatio(
                    words: statsSummary.totalWords,
                    book: $0.book,
                    allowsRepeats: $0.allowsRepeats
                )
            } ?? 0,
            bannerImage: art.image,
            isCustomBanner: art.isCustomBanner,
            boardsTint: resolved.map { BannerTreatment.boardsTint(for: $0.book) } ?? ImageTint.clothPalette[0],
            bookChipImage: art.coverImage,
            menuBooks: visibleBooks.sorted { ($0.wordCount, $0.id) < ($1.wordCount, $1.id) },
            isAutomaticSelected: selectedBookID.isEmpty,
            selectedBookID: selectedBookID.isEmpty ? nil : selectedBookID,
            onSelectAutomatic: { selectedBookID = "" },
            onSelectBook: { selectedBookID = $0.id },
            onAddBook: { isAddBookSheetPresented = true },
            onManageBooks: openManageBooksPanel,
            onViewInsights: openInsightsIfAvailable,
            onReviewCorrections: openAutoLearnReviewPanel
        )
    }

    // MARK: - Books

    private var visibleBooks: [DashboardBook] {
        bookStore.allBooks(hiddenBuiltIns: hiddenBooks.ids)
    }

    private var resolvedBook: ResolvedBook? {
        DashboardProgressBenchmark.resolveBook(
            words: statsSummary.totalWords,
            visible: visibleBooks,
            selectedID: selectedBookID.isEmpty ? nil : selectedBookID
        )
    }

    private struct BannerArt {
        var image: NSImage?
        var isCustomBanner = false
        var coverImage: NSImage?
    }

    /// Disk-only lookups: the hero never waits on the network.
    private func bannerArt(for book: DashboardBook?) -> BannerArt {
        _ = coverRevision
        guard let book else { return BannerArt() }
        let custom = bookStore.bannerImage(for: book)
        let cover = book.coverID.flatMap { BookCoverCache.shared.cachedImage(for: $0) }
        let source = BookArtSource.resolve(
            book: book,
            customBannerExists: custom != nil,
            coverCached: cover != nil
        )
        switch source.kind {
        case .customBanner: return BannerArt(image: custom, isCustomBanner: true, coverImage: cover)
        case .cover: return BannerArt(image: cover, isCustomBanner: false, coverImage: cover)
        case .none: return BannerArt(coverImage: cover)
        }
    }

    private func clearStaleBookSelection() {
        if DashboardProgressBenchmark.isSelectionStale(
            selectedID: selectedBookID.isEmpty ? nil : selectedBookID,
            visible: visibleBooks
        ) {
            selectedBookID = ""
        }
    }

    private func openManageBooksPanel() {
        manageBooksViewModel = ManageBooksViewModel(
            store: bookStore,
            hidden: $hiddenBooks,
            selectedID: $selectedBookID
        )
        isManageBooksPanelPresented = true
    }

    /// Keeps the persisted `coverTint` in step with the active banner source. When the cover isn't on
    /// disk yet, starts one silent, non-blocking fetch per book per session.
    private func ensureCoverTint() {
        guard let book = resolvedBook?.book, book.coverTint == nil else { return }

        if let banner = bookStore.bannerImage(for: book) {
            if let tint = ImageTint.averageColor(of: banner) {
                bookStore.setCoverTint(tint, forBookID: book.id)
            }
            return
        }

        guard let coverID = book.coverID else { return }
        if let cover = BookCoverCache.shared.cachedImage(for: coverID) {
            if let tint = ImageTint.averageColor(of: cover) {
                bookStore.setCoverTint(tint, forBookID: book.id)
            }
            return
        }

        guard book.kind == .custom, Self.coverFetchAttempts.insert(book.id).inserted else { return }
        let bookID = book.id
        Task(priority: .utility) {
            let cover = await BookCoverCache.shared.image(for: coverID)
            coverRevision += 1
            guard let cover,
                let current = bookStore.customBooks.first(where: { $0.id == bookID }),
                current.coverTint == nil,
                bookStore.bannerImage(for: current) == nil,
                let tint = ImageTint.averageColor(of: cover)
            else { return }
            bookStore.setCoverTint(tint, forBookID: bookID)
        }
    }

    @ViewBuilder
    private var footerStarButtonLabel: some View {
        if starPrompt.openFailed {
            footerActionLabel(icon: "exclamationmark.triangle.fill", title: "Couldn't open — try again", color: .orange)
        } else {
            switch starPrompt.completionState {
            case .starred:
                footerActionLabel(icon: "checkmark", title: "Starred — thank you!", color: AppTheme.Sidebar.license)
            case .opened:
                footerActionLabel(icon: "arrow.up.right", title: "GitHub opened", color: AppTheme.Sidebar.fallback)
            case .none:
                footerActionLabel(icon: "star", title: "Star on GitHub", color: AppTheme.Sidebar.fallback)
            }
        }
    }

    private var footerActionsView: some View {
        HStack(alignment: .center, spacing: 12) {
            if starPrompt.showsFooterStarButton {
                Button(action: { starPrompt.star() }) {
                    footerStarButtonLabel
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: true)
                .disabled(starPrompt.isStarring || starPrompt.completionState != .none)
                .animation(.easeInOut(duration: 0.15), value: starPrompt.openFailed)
            }

            if let availableUpdate = updaterViewModel.availableUpdate {
                Button(action: updaterViewModel.checkForUpdates) {
                    footerActionLabel(
                        icon: "arrow.down.circle.fill",
                        title: "Update Available",
                        color: AppTheme.Status.infoStrong
                    )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: true)
                .disabled(!updaterViewModel.canCheckForUpdates)
                .help(
                    String(
                        format: String(localized: "Open the VoiceInk %@ update"),
                        availableUpdate.displayVersion
                    )
                )
                .accessibilityLabel("Update Available")
                .accessibilityValue(Text(verbatim: availableUpdate.displayVersion))
                .accessibilityHint("Opens the update window")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button(action: copySystemInfo) {
                footerActionLabel(
                    icon: isSystemInfoCopied ? "checkmark" : "doc.on.doc",
                    title: isSystemInfoCopied ? "Copied!" : "Copy System Info",
                    color: isSystemInfoCopied ? AppTheme.Sidebar.license : AppTheme.Sidebar.fallback
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: true)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSystemInfoCopied)
        }
        .animation(.easeOut(duration: 0.2), value: updaterViewModel.availableUpdate)
    }

    @ViewBuilder
    private func footerActionLabel(icon: String, title: LocalizedStringKey, color: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            DashboardIconGlyph(systemName: icon, color: color, size: 13, frameSize: 16)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .frame(height: DashboardLayout.footerButtonHeight)
        .background(AppCardBackground(cornerRadius: 18))
    }

    private func copySystemInfo() {
        SystemInfoService.shared.copySystemInfoToClipboard()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isSystemInfoCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isSystemInfoCopied = false
            }
        }
    }

    private var displayNameBinding: Binding<String> {
        Binding(
            get: {
                isEditingDisplayName ? displayNameDraft : defaultedDisplayName
            },
            set: { newValue in
                displayNameDraft = String(newValue.prefix(32))
            }
        )
    }

    private var displayNameFieldWidth: CGFloat {
        let name = isEditingDisplayName ? displayNameDraft : defaultedDisplayName
        let measuredWidth = (name as NSString).size(
            withAttributes: [
                .font: NSFont.systemFont(ofSize: Self.displayNameFontSize, weight: Self.displayNameFontWeight)
            ]
        ).width
        return min(
            max(measuredWidth + (Self.displayNameHorizontalPadding * 2) + 6, Self.displayNameMinWidth),
            Self.displayNameMaxWidth
        )
    }

    private var defaultedDisplayName: String {
        let storedName = sanitizedDisplayName(dashboardDisplayName)
        return storedName.isEmpty ? systemDisplayName : storedName
    }

    private var systemDisplayName: String {
        Self.systemAccountFirstName() ?? Self.fallbackDisplayName
    }

    private func beginEditingDisplayName() {
        displayNameDraft = defaultedDisplayName
        isEditingDisplayName = true
        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func finishEditingDisplayName() {
        dashboardDisplayName = String(sanitizedDisplayName(displayNameDraft).prefix(32))
        isEditingDisplayName = false
        isNameFieldFocused = false

        if sanitizedDisplayName(dashboardDisplayName).isEmpty {
            dashboardDisplayName = ""
        }
    }

    private func dismissDisplayNameEditorIfNeeded() {
        if isEditingDisplayName {
            finishEditingDisplayName()
        }
    }

    private func sanitizedDisplayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func systemAccountFirstName() -> String? {
        let fullName = sanitizedSystemName(NSFullUserName())

        if let fullName,
            let givenName = PersonNameComponentsFormatter().personNameComponents(from: fullName)?.givenName,
            !givenName.isEmpty
        {
            return givenName
        }

        if let fullName,
            let firstName = fullName.split(whereSeparator: \.isWhitespace).first
        {
            return String(firstName)
        }

        if let shortName = sanitizedSystemName(NSUserName()) {
            return
                shortName
                .split(separator: ".")
                .first
                .map(String.init) ?? shortName
        }

        return nil
    }

    private static func sanitizedSystemName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return String(localized: "Good morning")
        case 12..<17:
            return String(localized: "Good afternoon")
        case 17..<24:
            return String(localized: "Good evening")
        default:
            return String(localized: "Hi")
        }
    }

    private var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "☀️"
        case 12..<17:
            return "👋"
        case 17..<24:
            return "🌙"
        default:
            return "👋"
        }
    }

    private var headerSubtitle: String {
        guard hasLoadedStatsSnapshot else {
            return String(localized: "Pulling together your VoiceInk activity.")
        }

        guard statsSummary.totalCount > 0 else {
            return String(localized: "Record your first session to start building momentum.")
        }

        if statsSummary.recentSevenDayCount >= 5 {
            return String(localized: "You’re on a roll this week. Keep the momentum going.")
        }

        if statsSummary.recentSevenDayCount > 0 {
            return String(localized: "You’re building momentum this week. Keep it going.")
        }

        return String(localized: "Your data is not ready yet. Keep the momentum going.")
    }

    private var momentumHeadline: DashboardHeroHeadline {
        guard hasLoadedStatsSnapshot else {
            return .calculatingProgress
        }

        guard statsSummary.totalCount > 0 else {
            return .startRecordingProgress
        }

        return .savedTime(formattedAllTimeSaved)
    }

    private var momentumSubtext: String {
        guard hasLoadedStatsSnapshot else {
            return String(localized: "Your word count and benchmark will appear here.")
        }

        guard statsSummary.totalCount > 0 else {
            return String(localized: "Your first milestone appears after one session.")
        }

        return formattedProgressBenchmarkText
    }

    // MARK: - Computed Metrics

    private var allTimeSaved: TimeInterval {
        DashboardTimeSaving.timeSaved(words: statsSummary.totalWords, duration: statsSummary.totalDuration)
    }

    private var formattedAllTimeSaved: String {
        Formatters.formattedSavedTime(allTimeSaved)
    }

    private var formattedAllTimeWords: String {
        let words = Formatters.formattedNumber(statsSummary.totalWords)
        let wordUnit = statsSummary.totalWords == 1 ? String(localized: "word") : String(localized: "words")
        return String(localized: "\(words) \(wordUnit)")
    }

    private var formattedProgressBenchmarkText: String {
        let resolved = resolvedBook

        switch DashboardProgressBenchmark.equivalence(
            for: statsSummary.totalWords,
            book: resolved?.book,
            allowsRepeats: resolved?.allowsRepeats ?? false
        ) {
        case .matched(let title):
            return String(localized: "Dictated \(formattedAllTimeWords), equivalent to \(title).")
        case .repeated(let title, let count):
            return String(
                localized:
                    "Dictated \(formattedAllTimeWords), equivalent to \(title) \(DashboardProgressBenchmark.multipleText(count)).")
        case .remaining(let words, let title, let isEstimate):
            let remainingWords = Formatters.formattedNumber(words)
            if isEstimate {
                return String(localized: "Dictated \(formattedAllTimeWords), ~\(remainingWords) words from \(title).")
            }
            return String(localized: "Dictated \(formattedAllTimeWords), \(remainingWords) words from \(title).")
        case .none:
            return String(localized: "Dictated \(formattedAllTimeWords).")
        }
    }
}

private struct DashboardAccessibilityReminder: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Accent.fill)

                Image(systemName: "hand.raised")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Enable Accessibility Access")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Required for VoiceInk shortcuts and app-wide controls to work properly.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Open Settings", action: onOpenSettings)
                .controlSize(.small)
                .help("Open Accessibility settings")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: 16))
    }
}

private struct DashboardNoModesReminder: View {
    let onOpenModes: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.Accent.fill)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppTheme.Accent.primary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("Set Up a Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("VoiceInk needs at least one mode to record. Create one to start dictating.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button("Manage Modes", action: onOpenModes)
                .controlSize(.small)
                .help("Open Modes settings")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppCardBackground(cornerRadius: 16))
    }
}

private struct DashboardAmbientBackground: View {
    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
