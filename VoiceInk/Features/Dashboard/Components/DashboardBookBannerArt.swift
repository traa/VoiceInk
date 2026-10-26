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

/// How a piece of art is composed into the hero's art region (spec §8.6).
/// Landscape art (true banners, the mountains bitmap) fills the region. Portrait or squarish art, i.e. almost
/// every real book cover, would be cropped to a thin blurred band that way, so it is drawn sharp, aspect-fit
/// in front of a blurred, darkened copy of itself.
enum ArtLayout: Equatable {
    case fullBleed
    case coverOnBackdrop

    /// Width / height below this is "not landscape".
    static let landscapeThreshold: CGFloat = 1.15

    static func resolve(imagePixelSize size: CGSize) -> ArtLayout {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .fullBleed }
        return size.width / size.height < landscapeThreshold ? .coverOnBackdrop : .fullBleed
    }

    /// Frame of the sharp cover inside an art region of `container` size: as tall as the region minus `inset`
    /// above and below (aspect-fit), centred in the area between `leadingInset` (the fade zone) and
    /// `container.width - trailingReserve`, and at least `inset` away from both sides of that area.
    static func coverFrame(
        container: CGSize, imageAspect: CGFloat, inset: CGFloat, leadingInset: CGFloat, trailingReserve: CGFloat
    ) -> CGRect {
        let width = container.width.isFinite ? max(container.width, 0) : 0
        let height = container.height.isFinite ? max(container.height, 0) : 0
        let aspect = imageAspect.isFinite && imageAspect > 0 ? imageAspect : 2.0 / 3.0
        let areaMinX = min(max(leadingInset, 0), width)
        let areaMaxX = max(areaMinX, width - max(trailingReserve, 0))
        let maxWidth = max(areaMaxX - areaMinX - 2 * inset, 0)
        var coverHeight = max(height - 2 * inset, 0)
        var coverWidth = coverHeight * aspect
        if coverWidth > maxWidth {
            coverWidth = maxWidth
            coverHeight = coverWidth / aspect
        }
        return CGRect(
            x: (areaMinX + areaMaxX - coverWidth) / 2,
            y: (height - coverHeight) / 2,
            width: coverWidth,
            height: coverHeight
        )
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
    /// The mountains bitmap is zoomed toward its top-right so its plain beige left side is cropped away.
    static let defaultBannerZoom: CGFloat = 1.3
    /// Share of the art's width over which un-gridded art (locked, or no book) dissolves into the beige
    /// gradient on its left edge (the locked prompt overlaps the art).
    static let leftFadeFraction: CGFloat = 0.25
    /// Width in points of the left fade of the grid reveal. The mask covers muted base, full-colour cells and
    /// hairlines together, so the whole grid dissolves into the beige card (no hard edge).
    static let gridFadeWidth: CGFloat = 32
    /// Locked insights state (spec §8.6 item 5): blur added on top of the art's own blur logic,
    /// plus the same desaturation and white veil the old bitmap background got.
    static let lockedExtraBlurRadius: CGFloat = 2.5
    static let lockedSaturation: Double = 0.78
    static let lockedWhiteOverlayOpacity: Double = 0.32
    /// Beige wash over locked art so the lock prompt stays legible where it meets the art.
    static let lockedWashOpacity: Double = 0.5
    /// Grid reveal (spec §8.7): art in the not-yet-dictated cells.
    static let mutedSaturation: Double = 0.3
    static let mutedDarkening: Double = 0.15
    static let cellCornerRadius: CGFloat = 2
    static let cellHairlineOpacity: Double = 0.15
    /// Portrait covers (spec §8.6): blurred backdrop (moderate, so colours still read), darkening, and the
    /// sharp cover's inset, trailing reserve (room for the caption pill) and corner radius.
    static let backdropBlurRadius: CGFloat = 14
    static let backdropDarkening: Double = 0.18
    static let coverInset: CGFloat = 12
    static let coverTrailingReserve: CGFloat = 140
    static let coverCornerRadius: CGFloat = 3

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
        Int(pixelSize(of: image).width)
    }

    /// Largest bitmap representation's pixel size, falling back to the point size.
    static func pixelSize(of image: NSImage) -> CGSize {
        let rep = image.representations.max { $0.pixelsWide < $1.pixelsWide }
        if let rep, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
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
                if let reveal, showsGrid {
                    revealLayers(reveal: reveal, size: size, blur: blur)
                } else {
                    artImage(size: size, blur: blur + (isLocked ? BannerTreatment.lockedExtraBlurRadius : 0))
                        .saturation(isLocked ? BannerTreatment.lockedSaturation : 1)
                        .overlay(Color.white.opacity(isLocked ? BannerTreatment.lockedWhiteOverlayOpacity : 0))
                        .overlay(Color(red: 0.98, green: 0.88, blue: 0.78).opacity(isLocked ? BannerTreatment.lockedWashOpacity : 0))
                }
            }
            .frame(width: size.width, height: size.height)
            .mask(fadeMask(artWidth: size.width))
            .accessibilityHidden(true)
            .overlay(alignment: .bottomTrailing) {
                if let reveal, showsGrid, showsCaption {
                    captionPill(reveal: reveal)
                        .padding(10)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var showsGrid: Bool { reveal != nil && !isLocked }

    // MARK: - Layers

    /// Blur of the sharp/full-bleed art itself. Portrait covers stay sharp (their backdrop has its own blur).
    private func blurRadius(artWidth: CGFloat) -> CGFloat {
        if isDefaultBanner || layout == .coverOnBackdrop { return 0 }
        return BannerTreatment.blurRadius(
            isCustomBanner: isCustomBanner,
            imagePixelWidth: BannerTreatment.pixelWidth(of: image),
            artWidth: artWidth,
            backingScale: displayScale
        )
    }

    private var layout: ArtLayout {
        isDefaultBanner ? .fullBleed : ArtLayout.resolve(imagePixelSize: BannerTreatment.pixelSize(of: image))
    }

    /// The composed art for one layer (muted, full colour or locked), always exactly `size`: either the image
    /// filling the region, or (portrait covers) a sharp cover standing on a blurred, darkened backdrop.
    /// `Color.clear` carries the layout size so the image's intrinsic size can never leak into it.
    @ViewBuilder
    private func artImage(size: CGSize, blur: CGFloat) -> some View {
        switch layout {
        case .fullBleed:
            Color.clear
                .overlay(alignment: isDefaultBanner ? .trailing : .center) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(blur > 0 ? BannerTreatment.blurredOverscale : 1)
                        .scaleEffect(isDefaultBanner ? BannerTreatment.defaultBannerZoom : 1, anchor: .topTrailing)
                        .blur(radius: blur)
                }
                .clipped()
        case .coverOnBackdrop:
            let pixels = BannerTreatment.pixelSize(of: image)
            let frame = ArtLayout.coverFrame(
                container: size,
                imageAspect: pixels.height > 0 ? pixels.width / pixels.height : 2.0 / 3.0,
                inset: BannerTreatment.coverInset,
                leadingInset: BannerTreatment.gridFadeWidth,
                trailingReserve: BannerTreatment.coverTrailingReserve
            )
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(BannerTreatment.blurredOverscale)
                        .blur(radius: BannerTreatment.backdropBlurRadius + blur)
                        .overlay(Color.black.opacity(BannerTreatment.backdropDarkening))
                }
                .overlay(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: BannerTreatment.coverCornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 3)
                        .blur(radius: blur)
                        .offset(x: frame.minX, y: frame.minY)
                }
                .clipped()
        }
    }

    @ViewBuilder
    private func revealLayers(reveal: BookRevealInput, size: CGSize, blur: CGFloat) -> some View {
        let grid = ProgressGrid.make(totalPages: reveal.totalPages, size: size)
        let state = GridReveal.make(ratio: reveal.ratio, cellCount: grid.cellCount)
        let radius = min(BannerTreatment.cellCornerRadius, min(grid.cellWidth, grid.cellHeight) / 4)
        ZStack {
            // Muted base over the whole art: it also fills the 1 pt gaps, so the art stays one picture.
            artImage(size: size, blur: blur)
                .saturation(BannerTreatment.mutedSaturation)
                .overlay(Color.black.opacity(BannerTreatment.mutedDarkening))

            // Full colour through the filled cells (the next one partially).
            artImage(size: size, blur: blur)
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

    private func fadeMask(artWidth: CGFloat) -> some View {
        let fraction = showsGrid
            ? min(BannerTreatment.gridFadeWidth / max(artWidth, 1), 0.5)
            : BannerTreatment.leftFadeFraction
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fraction),
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
