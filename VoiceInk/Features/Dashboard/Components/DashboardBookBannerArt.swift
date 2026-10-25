import AppKit
import SwiftUI

/// Which image, if any, drives the hero's banner art (spec §8.6): custom banner, then cover, then none.
struct BookArtSource: Equatable {
    enum Kind: Equatable {
        case customBanner
        case cover
        case none
    }

    let kind: Kind

    static func resolve(book: DashboardBook, customBannerExists: Bool, coverCached: Bool) -> BookArtSource {
        if book.customBannerFile != nil, customBannerExists {
            return BookArtSource(kind: .customBanner)
        }
        if book.coverID != nil, coverCached {
            return BookArtSource(kind: .cover)
        }
        return BookArtSource(kind: .none)
    }
}

enum BannerTreatment {
    /// Open Library covers (`-L`, ~500 px) are always blurred when stretched into the banner.
    static let coverBlurRadius: CGFloat = 10
    /// Custom banners narrower than 1.5 × the art's pixel width get a lighter blur.
    static let lowResCustomBlurRadius: CGFloat = 4
    static let artWidthFraction: CGFloat = 0.55
    /// Below this card width the art and the open book are dropped so the copy is never truncated.
    static let minimumCardWidth: CGFloat = 620
    /// Blurred images are over-scaled so the blurred edges leave no transparent fringe.
    static let blurredOverscale: CGFloat = 1.15

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

    /// Boards colour: the stored banner average darkened ~20 %, else a deterministic palette colour.
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

/// Right-hand banner art for the hero card: the image fills its frame, dissolves into the beige
/// gradient on its left edge and is graded warm so the dark copy stays legible.
struct DashboardBookBannerArt: View {
    let image: NSImage
    let isCustomBanner: Bool
    /// Extra beige wash over the graded art. Used when the copy overlaps the art (no open book tier).
    var washOpacity: Double = 0

    @Environment(\.displayScale) private var displayScale
    var body: some View {
        GeometryReader { proxy in
            let blur = BannerTreatment.blurRadius(
                isCustomBanner: isCustomBanner,
                imagePixelWidth: BannerTreatment.pixelWidth(of: image),
                artWidth: proxy.size.width,
                backingScale: displayScale
            )
            // `Color.clear` carries the layout size so the image's intrinsic size can never leak into it.
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(blur > 0 ? BannerTreatment.blurredOverscale : 1)
                        .blur(radius: blur)
                        .saturation(0.85)
                }
                .overlay(Color(red: 1.0, green: 0.86, blue: 0.68).opacity(0.20))
                .overlay(Color.white.opacity(0.10))
                .overlay(Color(red: 0.98, green: 0.88, blue: 0.78).opacity(washOpacity))
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.4),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
