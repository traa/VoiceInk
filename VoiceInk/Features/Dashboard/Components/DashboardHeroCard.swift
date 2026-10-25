import Foundation
import SwiftUI

enum DashboardHeroHeadline {
    case calculatingProgress
    case startRecordingProgress
    case savedTime(String)
}

struct DashboardHeroCard: View {
    private static let headlineFont: Font = .system(size: 23, weight: .bold, design: .rounded)
    private static let highlightedHeadlineFont: Font = .system(size: 30, weight: .black, design: .rounded)

    let isLocked: Bool
    let headline: DashboardHeroHeadline
    let subtext: String
    let actionTitle: LocalizedStringKey
    let actionIcon: String
    let canViewInsights: Bool
    let actionHelp: String
    let actionAccessibilityLabel: String
    let reviewCorrectionCount: Int?
    let hasLoadedStats: Bool
    let book: DashboardBook?
    /// Clamped progress `P` (0...1) of the resolved book.
    let progress: Double
    /// Unclamped for repeats-allowed books, clamped otherwise (see `DashboardProgressBenchmark.openBookRatio`).
    let progressRatio: Double
    let bannerImage: NSImage?
    /// No cover/custom banner: draw the original bitmap as the full-card background.
    let usesDefaultBanner: Bool
    let isCustomBanner: Bool
    let boardsTint: RGB
    let bookChipImage: NSImage?
    /// Cached cover (or banner) for a menu row; disk/memory only, never fetched. Nil draws the tinted placeholder.
    let menuThumbnailSource: (DashboardBook) -> NSImage?
    let menuBooks: [DashboardBook]
    /// Total dictated words; books with `wordCount <= totalWords` are marked completed in the menu.
    let totalWords: Int
    let isAutomaticSelected: Bool
    let selectedBookID: String?
    let onSelectAutomatic: () -> Void
    let onSelectBook: (DashboardBook) -> Void
    let onAddBook: () -> Void
    let onManageBooks: () -> Void
    let onViewInsights: () -> Void
    let onReviewCorrections: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Tier 1 (wide): banner art + open book. No ideal-width override: the wide variant's ideal
            // width is copy (wraps freely) + book, so it is only chosen when the book fits unsqueezed.
            cardContent(showsBook: artPlan(tierShowsBook: true).drawsBook)
                .background(alignment: .trailing) { artLayer(plan: artPlan(tierShowsBook: true)) }
                .frame(minWidth: BannerTreatment.minimumCardWidth, maxWidth: .infinity, alignment: .leading)

            // Tier 2 (narrower): the book is dropped, the banner art stays (when there is one).
            // Tier 3 (no art source): plain gradient, drawn by `DashboardImpactBackground`.
            cardContent(showsBook: false)
                .background(alignment: .trailing) { artLayer(plan: artPlan(tierShowsBook: false)) }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(DashboardImpactBackground(isLocked: isLocked, usesDefaultBanner: usesDefaultBanner))
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
    }

    private func artPlan(tierShowsBook: Bool) -> BannerTreatment.ArtPlan {
        BannerTreatment.artPlan(
            isLocked: isLocked,
            hasBook: book != nil,
            hasArtImage: bannerImage != nil,
            tierShowsBook: tierShowsBook
        )
    }

    /// The open book is drawn at 80 % so copy + book fit the app's fixed 950 pt window (hero ≈ 682 pt).
    private static let bookScale: CGFloat = 0.8

    /// Centre of the open book from the card's trailing edge: card padding (28) + half the scaled book.
    private static let bookCenterInset: CGFloat = 28 + 240 * bookScale / 2

    @ViewBuilder
    private func artLayer(plan: BannerTreatment.ArtPlan) -> some View {
        if plan.drawsBook || plan.drawsArt {
            GeometryReader { proxy in
                let width = proxy.size.width
                let height = proxy.size.height
                ZStack(alignment: .topLeading) {
                    if plan.drawsArt, let bannerImage {
                        let artWidth = width * BannerTreatment.artWidthFraction
                        DashboardBookBannerArt(
                            image: bannerImage,
                            isCustomBanner: isCustomBanner,
                            washOpacity: plan.washOpacity,
                            isLocked: plan.artIsLocked
                        )
                            .frame(width: artWidth, height: height)
                            .offset(x: width - artWidth)
                    }

                    if plan.drawsBook {
                        // Soft light pool behind the book and its caption: separates the cream pages from the
                        // gradient (no art) and keeps the caption legible over any art.
                        RadialGradient(
                            colors: [Color.white.opacity(bannerImage == nil ? 0.45 : 0.62), Color.white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 190
                        )
                        .frame(width: 380, height: 380)
                        .position(x: width - Self.bookCenterInset, y: height / 2)
                    }
                }
                .frame(width: width, height: height)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func cardContent(showsBook: Bool) -> some View {
        HStack(alignment: .center, spacing: 20) {
            copyColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsBook, let book {
                DashboardOpenBookView(
                    progress: hasLoadedStats ? progress : 0,
                    ratio: hasLoadedStats ? progressRatio : 0,
                    totalPages: book.pagesEquivalent,
                    title: book.displayTitle,
                    boardsTint: boardsTint,
                    showsCaption: hasLoadedStats
                )
                .fixedSize()
                .scaleEffect(Self.bookScale)
                .frame(width: 240 * Self.bookScale, height: 140 * Self.bookScale)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
    }

    private var copyColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLocked {
                lockedInsightsPrompt
            } else {
                heroCopy
            }

            HeroButtonFlow(spacing: 12, lineSpacing: 10) {
                Button(action: onViewInsights) {
                    DashboardMomentumActionLabel(
                        title: actionTitle,
                        icon: actionIcon,
                        isPrimary: canViewInsights,
                        isLocked: !canViewInsights
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canViewInsights)
                .help(actionHelp)
                .accessibilityLabel(Text(actionAccessibilityLabel))

                if let reviewCorrectionCount {
                    Button(action: onReviewCorrections) {
                        DashboardMomentumActionLabel(
                            title: "Review Corrections",
                            icon: "text.book.closed",
                            isPrimary: false
                        )
                    }
                    .buttonStyle(.plain)
                    .help(reviewCorrectionsHelp(count: reviewCorrectionCount))
                    .accessibilityLabel("Review corrections")
                    .accessibilityValue(
                        Text(
                            String(
                                format: String(localized: "%lld pending corrections"),
                                Int64(reviewCorrectionCount)
                            )
                        )
                    )
                }

                if !isLocked {
                    bookChip
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Book chip

    private var bookChip: some View {
        Menu {
            Button(action: onSelectAutomatic) {
                menuLabel(String(localized: "Automatic"), isSelected: isAutomaticSelected)
            }

            if !menuBooks.isEmpty {
                Divider()
                ForEach(menuBooks) { menuBook in
                    Toggle(
                        isOn: Binding(
                            get: { menuBook.id == selectedBookID },
                            set: { _ in onSelectBook(menuBook) }
                        )
                    ) {
                        let isPassed = DashboardProgressBenchmark.isPassed(book: menuBook, totalWords: totalWords)
                        let rowTitle = Text(menuTitle(for: menuBook))
                        Label {
                            // Only passed rows are restyled: forcing `.primary` on the others dims them in NSMenu.
                            if isPassed { rowTitle.foregroundStyle(.secondary) } else { rowTitle }
                        } icon: {
                            Image(nsImage: BookMenuThumbnail.make(
                                from: menuThumbnailSource(menuBook),
                                tint: BannerTreatment.boardsTint(for: menuBook),
                                isPassed: isPassed))
                        }
                        .accessibilityValue(isPassed ? Text("Completed") : Text(verbatim: ""))
                    }
                }
            }

            Divider()
            Button("Add Book…", action: onAddBook)
            Button("Manage Books…", action: onManageBooks)
        } label: {
            DashboardBookChipLabel(
                title: book?.displayTitle ?? String(localized: "Choose a book"),
                image: bookChipImage,
                placeholderTint: boardsTint
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Choose the book your progress is compared to")
        .accessibilityLabel("Book for progress comparison")
        .accessibilityValue(book?.displayTitle ?? "")
    }

    @ViewBuilder
    private func menuLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func menuTitle(for book: DashboardBook) -> String {
        let words = Formatters.formattedNumber(book.wordCount)
        if book.isEstimate {
            return String(localized: "\(book.displayTitle) — ~\(words) words")
        }
        return String(localized: "\(book.displayTitle) — \(words) words")
    }

    private func reviewCorrectionsHelp(count: Int) -> String {
        String(
            format: String(localized: "Review %lld pending corrections"),
            Int64(count)
        )
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 10) {
            headlineText
                .frame(idealWidth: 200, maxWidth: 720, alignment: .leading)

            Text(subtext)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashboardMomentumBackground.subtext)
                .frame(idealWidth: 200, maxWidth: 620, alignment: .leading)
        }
    }

    private var headlineText: Text {
        Text(styledHeadline)
    }

    private var styledHeadline: AttributedString {
        let highlightedValue: String
        var text: AttributedString

        switch headline {
        case .calculatingProgress:
            highlightedValue = String(localized: "VoiceInk progress")
            text = AttributedString(localized: "Calculating \(highlightedValue).")
        case .startRecordingProgress:
            highlightedValue = String(localized: "VoiceInk progress")
            text = AttributedString(localized: "Start recording to build \(highlightedValue).")
        case .savedTime(let value):
            highlightedValue = value
            text = AttributedString(localized: "You have saved \(highlightedValue) with VoiceInk")
        }

        text.font = Self.headlineFont
        text.foregroundColor = DashboardMomentumBackground.headline

        if let highlightedRange = text.range(of: highlightedValue) {
            text[highlightedRange].font = Self.highlightedHeadlineFont
            text[highlightedRange].foregroundColor = DashboardMomentumBackground.accent
        }

        return text
    }

    private var lockedInsightsPrompt: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.78))

                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DashboardMomentumBackground.accent)
            }
            .frame(width: 42, height: 42)

            Text("Continue using VoiceInk to unlock stats and insights.")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(DashboardMomentumBackground.headline)
                .frame(maxWidth: 540, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 16×22 pt menu-row thumbnail: aspect-filled cover/banner, or the tinted placeholder. Passed (completed)
/// books get a green check badge in the bottom-right corner. The image is never a template, so the
/// colour survives in an `NSMenu`.
enum BookMenuThumbnail {
    static let size = NSSize(width: 16, height: 22)
    static let badgeDiameter: CGFloat = 11
    /// Fixed green (not the adaptive system green) so the badge reads the same on light and dark menus.
    private static let passedGreen = NSColor(srgbRed: 0.10, green: 0.60, blue: 0.25, alpha: 1)

    static func make(from source: NSImage?, tint: RGB, isPassed: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            clip.addClip()
            if let source, source.size.width > 0, source.size.height > 0 {
                let scale = max(rect.width / source.size.width, rect.height / source.size.height)
                let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
                let drawRect = NSRect(
                    x: rect.midX - drawSize.width / 2, y: rect.midY - drawSize.height / 2,
                    width: drawSize.width, height: drawSize.height)
                source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                NSColor(srgbRed: tint.red, green: tint.green, blue: tint.blue, alpha: 1).setFill()
                rect.fill()
            }
            NSColor.black.withAlphaComponent(0.2).setStroke()
            clip.lineWidth = 0.5
            clip.stroke()
            NSGraphicsContext.restoreGraphicsState()

            if isPassed { drawPassedBadge(in: rect) }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// White ring + green `checkmark.circle.fill`, tucked into the bottom-right corner of `rect`.
    private static func drawPassedBadge(in rect: NSRect) {
        let badge = NSRect(
            x: rect.maxX - badgeDiameter, y: rect.minY, width: badgeDiameter, height: badgeDiameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: badge).fill()

        let glyph = badge.insetBy(dx: 1, dy: 1)
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.white, passedGreen])
        if let symbol = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        {
            symbol.draw(in: glyph, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            passedGreen.setFill()
            NSBezierPath(ovalIn: glyph).fill()
        }
    }
}

private struct DashboardMomentumActionLabel: View {
    private static let cornerRadius: CGFloat = 12

    let title: LocalizedStringKey
    let icon: String
    let isPrimary: Bool
    var isLocked = false

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .lineLimit(2)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, 18)
        .frame(minHeight: 40)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 5, y: 2)
    }

    private var foregroundColor: Color {
        if isPrimary {
            return Color.white
        }

        return isLocked
            ? DashboardMomentumBackground.subtext
            : DashboardMomentumBackground.headline
    }

    private var backgroundColor: Color {
        if isPrimary {
            return DashboardMomentumBackground.accent
        }

        return isLocked ? Color.white.opacity(0.64) : Color.white.opacity(0.82)
    }

    private var borderColor: Color {
        if isPrimary {
            return Color.clear
        }

        return isLocked ? DashboardMomentumBackground.accent.opacity(0.22) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        isPrimary ? DashboardMomentumBackground.accent.opacity(0.18) : Color.black.opacity(0.06)
    }
}

private struct DashboardBookChipLabel: View {
    let title: String
    let image: NSImage?
    let placeholderTint: RGB

    var body: some View {
        HStack(spacing: 8) {
            thumbnail

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(DashboardMomentumBackground.headline)
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color.white.opacity(0.82))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
        .contentShape(Capsule())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 16, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                )
        } else {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(red: placeholderTint.red, green: placeholderTint.green, blue: placeholderTint.blue))
                .frame(width: 16, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
                )
        }
    }
}

private struct DashboardImpactBackground: View {
    var isLocked = false
    /// True: the original full-card low-poly bitmap. False: the beige gradient (banner art is drawn above it).
    var usesDefaultBanner = false

    var body: some View {
        ZStack {
            if usesDefaultBanner {
                Image("momentum-hero-bg")
                    .resizable()
                    .scaledToFill()
                    .blur(radius: isLocked ? BannerTreatment.lockedExtraBlurRadius : 0)
                    .saturation(isLocked ? BannerTreatment.lockedSaturation : 1)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.85, blue: 0.74),
                        Color(red: 0.99, green: 0.91, blue: 0.83),
                    ],
                    startPoint: .topLeading,
                    endPoint: .trailing
                )
                .saturation(isLocked ? BannerTreatment.lockedSaturation : 1)
            }

            if isLocked {
                Color.white.opacity(BannerTreatment.lockedWhiteOverlayOpacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardLayout.cardCornerRadius, style: .continuous)
                .stroke(AppTheme.Border.card, lineWidth: 1)
        )
    }
}

struct DashboardMomentumBackground {
    static let accent = Color(red: 0.76, green: 0.31, blue: 0.08)
    static let headline = Color(red: 0.10, green: 0.08, blue: 0.06)
    static let subtext = Color(red: 0.40, green: 0.34, blue: 0.28)
}

/// Left-to-right row that wraps onto further lines instead of squeezing its children. With no width
/// proposal it reports the size wrapped at `idealWrapWidth` (about the two action buttons), so the
/// hero's wide variant does not demand the full single-line width.
private struct HeroButtonFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    static let idealWrapWidth: CGFloat = 340

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? Self.idealWrapWidth).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (subview, position) in zip(subviews, result.positions) {
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }
}
