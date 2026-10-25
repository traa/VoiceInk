import AppKit
import SwiftUI

/// Which image drives the hero's background (spec §8.6): custom banner, then cover (both drawn as
/// right-hand art over the beige gradient), else the original full-card default banner bitmap.
struct BookArtSource: Equatable {
    enum Kind: Equatable {
        case customBanner
        case cover
        /// No usable cover or custom banner: the original low-poly mountains bitmap (`momentum-hero-bg`).
        case defaultBanner
    }

    let kind: Kind

    static func resolve(book: DashboardBook?, customBannerExists: Bool, coverCached: Bool) -> BookArtSource {
        guard let book else { return BookArtSource(kind: .defaultBanner) }
        if book.customBannerFile != nil, customBannerExists {
            return BookArtSource(kind: .customBanner)
        }
        if book.coverID != nil, coverCached {
            return BookArtSource(kind: .cover)
        }
        return BookArtSource(kind: .defaultBanner)
    }
}

enum BannerTreatment {
    /// Open Library covers (`-L`, ~500 px) are always blurred when stretched into the banner.
    static let coverBlurRadius: CGFloat = 10
    /// Custom banners narrower than 1.5 × the art's pixel width get a lighter blur.
    static let lowResCustomBlurRadius: CGFloat = 4
    static let artWidthFraction: CGFloat = 0.55
    /// Blurred images are over-scaled so the blurred edges leave no transparent fringe.
    static let blurredOverscale: CGFloat = 1.15
    /// Share of the art's width over which it dissolves into the beige gradient on its left edge.
    static let leftFadeFraction: CGFloat = 0.12
    /// Locked insights state (spec §8.6 item 5): blur added on top of the art's own blur logic,
    /// plus the same desaturation and white veil the old bitmap background got.
    static let lockedExtraBlurRadius: CGFloat = 2.5
    static let lockedSaturation: Double = 0.78
    static let lockedWhiteOverlayOpacity: Double = 0.32
    /// Beige wash over locked art so the lock prompt stays legible where it meets the art.
    static let lockedWashOpacity: Double = 0.5
    /// Grid reveal (spec §8.7): art in the not-yet-dictated cells.
    static let mutedSaturation: Double = 0.25
    static let mutedDarkening: Double = 0.22
    static let cellCornerRadius: CGFloat = 2.5
    static let cellHairlineOpacity: Double = 0.16

    /// The original low-poly mountains bitmap, used as the art of books without cover or custom banner.
    static var defaultBannerImage: NSImage? { NSImage(named: "momentum-hero-bg") }

    static func blurRadius(
        isCustomBanner: Bool,
        imagePixelWidth: Int,
        artWidth: CGFloat,
        backingScale: CGFloat
    ) -> CGFloat {
        guard isCustomBanner else { return coverBlurRadius }
        let sharpThreshold = 1.5 * artWidth * backingScale
        return CGFloat(imagePixelWidth) >= sharpThreshold ? 0 : lowResCustomBlurRadius
    }

    /// Tint of the chip's placeholder thumbnail: the stored banner average darkened ~20 %, else a
    /// deterministic palette colour.
    static func boardsTint(for book: DashboardBook) -> RGB {
        if let tint = book.coverTint {
            return ImageTint.boardsTint(from: tint)
        }
        return ImageTint.paletteTint(forBookID: book.id)
    }

    static func pixelWidth(of image: NSImage) -> Int {
        let rep = image.representations.max { $0.pixelsWide < $1.pixelsWide }
        if let rep, rep.pixelsWide > 0 { return rep.pixelsWide }
        return Int(image.size.width)
    }
}

/// What the grid reveal needs from the book: its page count and the (repeat-aware) progress ratio.
struct BookRevealInput: Equatable {
    let totalPages: Int
    let ratio: Double
}

/// Right-hand banner art for the hero card. The image fills its frame and dissolves into the beige
/// gradient on its left edge. With a `reveal` input the art is drawn twice: muted everywhere, and in full
/// colour through the filled cells of the progress grid (spec §8.7). Without one (locked, or no book) it is
/// a single layer.
struct DashboardBookBannerArt: View {
    let image: NSImage
    let isCustomBanner: Bool
    /// The restored mountains bitmap: always sharp, anchored to its right (the mountains) side.
    var isDefaultBanner = false
    /// Locked insights state: extra blur, desaturation and a white veil (spec §8.6 item 5). No grid.
    var isLocked = false
    var reveal: BookRevealInput?
    /// The caption pill appears only once stats are loaded.
    var showsCaption = true

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let blur = blurRadius(artWidth: size.width)
            ZStack {
                if let reveal, !isLocked {
                    revealLayers(reveal: reveal, size: size, blur: blur)
                } else {
                    artImage(blur: blur + (isLocked ? BannerTreatment.lockedExtraBlurRadius : 0))
                        .saturation(isLocked ? BannerTreatment.lockedSaturation : 1)
                        .overlay(Color.white.opacity(isLocked ? BannerTreatment.lockedWhiteOverlayOpacity : 0))
                        .overlay(Color(red: 0.98, green: 0.88, blue: 0.78).opacity(isLocked ? BannerTreatment.lockedWashOpacity : 0))
                }
            }
            .frame(width: size.width, height: size.height)
            .mask(fadeMask)
            .accessibilityHidden(true)
            .overlay(alignment: .bottomTrailing) {
                if let reveal, !isLocked, showsCaption {
                    captionPill(reveal: reveal)
                        .padding(10)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Layers

    private func blurRadius(artWidth: CGFloat) -> CGFloat {
        if isDefaultBanner { return 0 }
        return BannerTreatment.blurRadius(
            isCustomBanner: isCustomBanner,
            imagePixelWidth: BannerTreatment.pixelWidth(of: image),
            artWidth: artWidth,
            backingScale: displayScale
        )
    }

    /// `Color.clear` carries the layout size so the image's intrinsic size can never leak into it.
    private func artImage(blur: CGFloat) -> some View {
        Color.clear
            .overlay(alignment: isDefaultBanner ? .trailing : .center) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(blur > 0 ? BannerTreatment.blurredOverscale : 1)
                    .blur(radius: blur)
            }
            .clipped()
    }

    @ViewBuilder
    private func revealLayers(reveal: BookRevealInput, size: CGSize, blur: CGFloat) -> some View {
        let grid = ProgressGrid.make(totalPages: reveal.totalPages, size: size)
        let state = GridReveal.make(ratio: reveal.ratio, cellCount: grid.cellCount)
        let radius = min(BannerTreatment.cellCornerRadius, min(grid.cellWidth, grid.cellHeight) / 4)
        ZStack {
            // Muted base, visible in every cell (the gaps show the beige card).
            artImage(blur: blur)
                .saturation(BannerTreatment.mutedSaturation)
                .overlay(Color.black.opacity(BannerTreatment.mutedDarkening))
                .mask(cellMask(grid: grid, radius: radius) { _ in 1 })

            // Full colour through the filled cells (the next one partially).
            artImage(blur: blur)
                .mask(cellMask(grid: grid, radius: radius) { state.opacity(ofCell: $0) })

            Canvas { context, _ in
                var edges = Path()
                for index in 0..<grid.cellCount {
                    edges.addPath(Path(roundedRect: grid.rect(ofCell: index), cornerRadius: radius, style: .continuous))
                }
                context.stroke(edges, with: .color(.white.opacity(BannerTreatment.cellHairlineOpacity)), lineWidth: 0.5)
            }
        }
    }

    private func cellMask(grid: ProgressGrid, radius: CGFloat, opacity: @escaping (Int) -> Double) -> some View {
        Canvas { context, _ in
            for index in 0..<grid.cellCount {
                let path = Path(roundedRect: grid.rect(ofCell: index), cornerRadius: radius, style: .continuous)
                context.fill(path, with: .color(.black.opacity(opacity(index))))
            }
        }
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: BannerTreatment.leftFadeFraction),
                .init(color: .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Caption

    /// Fixed colours (never semantic): readable over any art, in light and dark mode.
    private func captionPill(reveal: BookRevealInput) -> some View {
        let isFinished = reveal.ratio >= 1
        let pages = GridReveal.pagesDictated(ratio: reveal.ratio, totalPages: reveal.totalPages)
        let text = ProgressCaption.text(
            pagesDictated: pages,
            totalPages: max(reveal.totalPages, 2),
            ratio: reveal.ratio,
            isFinished: isFinished
        )
        return HStack(spacing: 5) {
            if isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.36, green: 0.85, blue: 0.5))
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}
