import CoreGraphics
import Foundation
import Testing
@testable import VoiceInk

/// Portrait/squarish art (book covers) is drawn sharp on a blurred backdrop; landscape art fills the banner.
struct ArtLayoutTests {
    // MARK: - resolve

    @Test func portraitCoverIsDrawnOnABackdrop() {
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 330, height: 500)) == .coverOnBackdrop)
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 1000, height: 1500)) == .coverOnBackdrop)
    }

    @Test func landscapeArtIsFullBleed() {
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 1500, height: 500)) == .fullBleed)
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 2300, height: 597)) == .fullBleed)
    }

    @Test func squarishThreshold() {
        #expect(ArtLayout.landscapeThreshold == 1.15)
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 800, height: 800)) == .coverOnBackdrop)
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 1140, height: 1000)) == .coverOnBackdrop)
        #expect(ArtLayout.resolve(imagePixelSize: CGSize(width: 1150, height: 1000)) == .fullBleed)
    }

    @Test func degenerateSizesAreFullBleed() {
        for size in [
            CGSize.zero,
            CGSize(width: 0, height: 500),
            CGSize(width: 500, height: 0),
            CGSize(width: -300, height: 500),
            CGSize(width: CGFloat.nan, height: 500),
            CGSize(width: 300, height: CGFloat.infinity),
        ] {
            #expect(ArtLayout.resolve(imagePixelSize: size) == .fullBleed, "\(size)")
        }
    }

    // MARK: - coverFrame

    private let container = CGSize(width: 375, height: 200)

    @Test func coverFitsTheHeightMinusInsetsAndKeepsItsAspect() {
        let frame = ArtLayout.coverFrame(
            container: container, imageAspect: 330.0 / 500.0, inset: 12, leadingInset: 32, trailingReserve: 0)
        #expect(abs(frame.height - 176) < 0.001)
        #expect(abs(frame.width / frame.height - 330.0 / 500.0) < 0.001)
        #expect(abs(frame.minY - 12) < 0.001)
    }

    @Test func coverStaysInsideTheUsableArea() {
        for reserve in [CGFloat(0), 60, 160] {
            let frame = ArtLayout.coverFrame(
                container: container, imageAspect: 0.66, inset: 12, leadingInset: 32, trailingReserve: reserve)
            #expect(frame.minX >= 32 - 0.001)
            #expect(frame.maxX <= container.width - 12 + 0.001)
            #expect(frame.minY >= 12 - 0.001 && frame.maxY <= container.height - 12 + 0.001)
        }
    }

    @Test func coverIsCentredInTheAreaLeftOfTheReserve() {
        let frame = ArtLayout.coverFrame(
            container: container, imageAspect: 0.66, inset: 12, leadingInset: 32, trailingReserve: 100)
        let areaMid = (32 + (container.width - 100)) / 2
        #expect(abs(frame.midX - areaMid) < 0.001)
    }

    @Test func tooWideCoverIsCappedToTheAvailableWidth() {
        let frame = ArtLayout.coverFrame(
            container: CGSize(width: 120, height: 200), imageAspect: 1.1, inset: 12, leadingInset: 32, trailingReserve: 0)
        #expect(frame.width <= 120 - 32 - 12 + 0.001)
        #expect(abs(frame.width / frame.height - 1.1) < 0.001)
        #expect(frame.minX >= 32 - 0.001)
    }

    @Test func degenerateInputsProduceAFiniteFrame() {
        let frame = ArtLayout.coverFrame(
            container: .zero, imageAspect: .nan, inset: 12, leadingInset: 32, trailingReserve: 0)
        #expect(frame.origin.x.isFinite && frame.origin.y.isFinite)
        #expect(frame.width.isFinite && frame.height.isFinite)
        #expect(frame.width >= 0 && frame.height >= 0)
    }
}
