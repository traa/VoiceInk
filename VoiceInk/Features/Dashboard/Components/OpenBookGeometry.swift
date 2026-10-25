import SwiftUI

/// Pure, unit-testable geometry for the static open book (spec §8.7).
///
/// Everything is laid out in a 240×118 design frame (origin top-left) and scaled uniformly
/// (and centred) into the requested size. Depths are reported in the final coordinate space.
///
/// The only distortion of the exact proportion `left : right = P : (1 - P)` is a 0.5 pt hairline
/// applied when `0 < P < 0.04` or `0.96 < P < 1`, so a non-zero side never disappears.
struct OpenBookGeometry: Equatable {
    let progress: Double
    let totalPages: Int
    let pagesDictated: Int
    let isFinished: Bool
    let leftDepth: CGFloat
    let rightDepth: CGFloat
    let leftStackLineCount: Int
    let rightStackLineCount: Int
    let leftPage: Path
    let rightPage: Path
    let leftStack: Path
    let rightStack: Path
    /// Thin leaf lines drawn over each stack (empty when the side has no stack).
    let leftStackLines: Path
    let rightStackLines: Path
    /// Deterministic text-hint rows following each page's curvature.
    let leftTextRows: Path
    let rightTextRows: Path

    /// Total edge depth distributed between the two stacks, in design points.
    static let totalStackDepth: CGFloat = 14
    static let defaultSize = CGSize(width: 240, height: 118)

    // MARK: Design-frame constants (shared with the painter)

    static let gutterX: CGFloat = 120
    static let blockTop: CGFloat = 14
    static let blockBottom: CGFloat = 104
    static let leftOuterX: CGFloat = 20
    static let rightOuterX: CGFloat = 220
    static let hairline: CGFloat = 0.5
    static let hairlineProgressBand: Double = 0.04
    static let stackLineSpacing: CGFloat = 1.1
    /// Rounded-rect the hardcover boards occupy (before their 4 pt thickness).
    static let boardsRect = CGRect(x: 4, y: 10, width: 232, height: 100)
    static let boardsThickness: CGFloat = 4

    static func make(size: CGSize, progress: Double, totalPages: Int) -> OpenBookGeometry {
        let clamped: Double
        if progress.isNaN {
            clamped = 0
        } else {
            clamped = min(max(progress, 0), 1)
        }
        let pages = max(totalPages, 2)
        let dictated = Int((clamped * Double(pages)).rounded())

        var sL = totalStackDepth * CGFloat(clamped)
        var sR = totalStackDepth * CGFloat(1 - clamped)
        if clamped > 0, clamped < hairlineProgressBand { sL = max(sL, hairline) }
        if clamped > 1 - hairlineProgressBand, clamped < 1 { sR = max(sR, hairline) }

        let design = defaultSize
        let scale = max(min(size.width / design.width, size.height / design.height), 0)
        let finiteScale = scale.isFinite ? scale : 1
        let transform = CGAffineTransform(
            translationX: (size.width - design.width * finiteScale) / 2,
            y: (size.height - design.height * finiteScale) / 2
        ).scaledBy(x: finiteScale, y: finiteScale)

        let left = Side(direction: -1, outerX: leftOuterX, depth: sL)
        let right = Side(direction: 1, outerX: rightOuterX, depth: sR)

        func placed(_ path: Path) -> Path { path.applying(transform) }

        return OpenBookGeometry(
            progress: clamped,
            totalPages: pages,
            pagesDictated: dictated,
            isFinished: clamped >= 1,
            leftDepth: sL * finiteScale,
            rightDepth: sR * finiteScale,
            leftStackLineCount: lineCount(forDepth: sL),
            rightStackLineCount: lineCount(forDepth: sR),
            leftPage: placed(left.page()),
            rightPage: placed(right.page()),
            leftStack: placed(left.stack()),
            rightStack: placed(right.stack()),
            leftStackLines: placed(left.stackLines()),
            rightStackLines: placed(right.stackLines()),
            leftTextRows: placed(left.textRows(lengths: leftRowLengths)),
            rightTextRows: placed(right.textRows(lengths: rightRowLengths))
        )
    }

    private static func lineCount(forDepth depth: CGFloat) -> Int {
        depth > 0 ? max(1, Int(depth / stackLineSpacing)) : 0
    }

    // Fixed pseudo-random row lengths (fraction of the usable page width); deterministic by design.
    private static let leftRowLengths: [CGFloat] = [1.0, 0.94, 1.0, 0.78, 1.0, 0.97, 0.9, 1.0, 0.46]
    private static let rightRowLengths: [CGFloat] = [0.92, 1.0, 0.86, 1.0, 0.95, 0.7, 1.0, 0.98, 0.55]

    // MARK: One page + stack (design frame)

    private struct Side {
        /// -1 for the left page, +1 for the right page (the outward direction).
        let direction: CGFloat
        let outerX: CGFloat
        /// Stack depth `s` in design points.
        let depth: CGFloat

        private var topOuter: CGPoint { CGPoint(x: outerX, y: blockTop + depth) }
        private var topGutter: CGPoint { CGPoint(x: gutterX, y: 22 + depth) }
        private var topControl: CGPoint { CGPoint(x: lerp(outerX, gutterX, 0.55), y: 6 + depth) }
        private var bottomOuter: CGPoint { CGPoint(x: outerX, y: blockBottom - depth * 0.2) }
        private var bottomGutter: CGPoint { CGPoint(x: gutterX, y: 100) }
        private var bottomControl: CGPoint {
            CGPoint(x: lerp(outerX, gutterX, 0.55), y: (bottomOuter.y + bottomGutter.y) / 2 + 3)
        }
        /// Control for the slightly convex outer edge, bulging 3 pt outward.
        private func outerControl(from a: CGPoint, to b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + direction * 3, y: (a.y + b.y) / 2)
        }
        /// Offset between the top page and the deepest leaf: outward by `s`, down by 0.6·`s`.
        private var stackOffset: CGSize { CGSize(width: direction * depth, height: depth * 0.6) }

        func page() -> Path {
            var path = Path()
            path.move(to: topOuter)
            path.addQuadCurve(to: topGutter, control: topControl)
            path.addLine(to: bottomGutter)
            path.addQuadCurve(to: bottomOuter, control: bottomControl)
            path.addQuadCurve(to: topOuter, control: outerControl(from: bottomOuter, to: topOuter))
            path.closeSubpath()
            return path
        }

        func stack() -> Path {
            guard depth > 0 else { return Path() }
            let o = stackOffset
            let outerBottomShifted = CGPoint(x: bottomOuter.x + o.width, y: bottomOuter.y + o.height)
            let topShifted = CGPoint(x: topOuter.x + o.width, y: topOuter.y + o.height)
            var path = Path()
            path.move(to: topOuter)
            path.addLine(to: topShifted)
            path.addQuadCurve(to: outerBottomShifted, control: outerControl(from: topShifted, to: outerBottomShifted))
            path.addQuadCurve(
                to: bottomGutter,
                control: CGPoint(x: bottomControl.x + o.width * 0.5, y: bottomControl.y + o.height * 0.9)
            )
            path.addQuadCurve(to: bottomOuter, control: bottomControl)
            path.addQuadCurve(to: topOuter, control: outerControl(from: bottomOuter, to: topOuter))
            path.closeSubpath()
            return path
        }

        func stackLines() -> Path {
            let count = OpenBookGeometry.lineCount(forDepth: depth)
            guard count > 0 else { return Path() }
            let o = stackOffset
            var path = Path()
            for index in 1...count {
                let t = CGFloat(index) / CGFloat(count + 1)
                let start = CGPoint(x: topOuter.x + o.width * t, y: topOuter.y + o.height * t)
                let corner = CGPoint(x: bottomOuter.x + o.width * t, y: bottomOuter.y + o.height * t)
                path.move(to: start)
                path.addQuadCurve(to: corner, control: outerControl(from: start, to: corner))
                path.addQuadCurve(
                    to: bottomGutter,
                    control: CGPoint(x: bottomControl.x + o.width * 0.5 * t, y: bottomControl.y + o.height * 0.9 * t)
                )
            }
            return path
        }

        /// Rows sample the top and bottom quadratics at the same parameter `t`, so they bow with the page.
        func textRows(lengths: [CGFloat]) -> Path {
            let startT: CGFloat = 0.1
            let spanT: CGFloat = 0.74
            let segments = 6
            var path = Path()
            for (index, length) in lengths.enumerated() {
                let fraction = 0.13 + 0.74 * CGFloat(index) / CGFloat(max(lengths.count - 1, 1))
                for step in 0...segments {
                    let t = startT + spanT * length * CGFloat(step) / CGFloat(segments)
                    let top = quad(topOuter, topControl, topGutter, t)
                    let bottom = quad(bottomOuter, bottomControl, bottomGutter, t)
                    let point = CGPoint(x: top.x, y: lerp(top.y, bottom.y, fraction))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            return path
        }
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

private func quad(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return CGPoint(
        x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
        y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
    )
}

enum OpenBookCaption {
    static func text(pagesDictated: Int, totalPages: Int, ratio: Double, isFinished: Bool) -> String {
        let pages = Formatters.formattedNumber(totalPages)
        if isFinished {
            if ratio >= 2 {
                let multiple = Formatters.formattedNumber(Int(min(ratio, 1_000_000_000).rounded(.down)))
                return String(localized: "All \(pages) pages · \(multiple)×")
            }
            return String(localized: "All \(pages) pages dictated")
        }
        let dictated = Formatters.formattedNumber(pagesDictated)
        return String(localized: "~\(dictated) of \(pages) pages dictated")
    }
}
