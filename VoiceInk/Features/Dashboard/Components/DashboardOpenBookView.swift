import SwiftUI

/// Static, natively drawn open book (spec §8.7). The left page stack is proportional to progress.
/// No timeline, no animation, no image assets: the view only paints `OpenBookGeometry`.
struct DashboardOpenBookView: View {
    /// Clamped progress `P` in 0...1.
    let progress: Double
    /// Unclamped `words / bookWords`, used only for the "N×" caption.
    let ratio: Double
    let totalPages: Int
    let title: String
    let boardsTint: RGB
    let showsCaption: Bool

    /// Room around the 240×118 frame for the boards' drop shadow (the canvas is not clipped to the layout frame).
    private static let bleed: CGFloat = 16

    private var geometry: OpenBookGeometry {
        OpenBookGeometry.make(size: OpenBookGeometry.defaultSize, progress: progress, totalPages: totalPages)
    }

    private var caption: String {
        let geometry = geometry
        return OpenBookCaption.text(
            pagesDictated: geometry.pagesDictated,
            totalPages: geometry.totalPages,
            ratio: ratio,
            isFinished: geometry.isFinished
        )
    }

    var body: some View {
        let geometry = geometry
        let caption = caption
        let tint = boardsTint
        VStack(spacing: 6) {
            Canvas { context, _ in
                context.translateBy(x: Self.bleed, y: Self.bleed)
                OpenBookPainter.paint(geometry: geometry, boardsTint: tint, in: &context)
            }
            .frame(
                width: OpenBookGeometry.defaultSize.width + Self.bleed * 2,
                height: OpenBookGeometry.defaultSize.height + Self.bleed * 2
            )
            .padding(-Self.bleed)
            .frame(width: OpenBookGeometry.defaultSize.width, height: OpenBookGeometry.defaultSize.height)
            .accessibilityHidden(true)

            if showsCaption {
                Text(caption)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .animation(nil, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Open book: \(title)"))
        .accessibilityValue(showsCaption ? caption : "")
    }
}

private enum OpenBookPainter {
    private static let paper = Color(hex: 0xFBF6EC)
    private static let paperShade = Color(hex: 0xEFE5D2)
    private static let creamTop = Color(hex: 0xF3EAD8)
    private static let creamBottom = Color(hex: 0xE3D6BE)

    static func paint(geometry: OpenBookGeometry, boardsTint: RGB, in context: inout GraphicsContext) {
        paintBoards(tint: boardsTint, in: &context)

        for (stack, lines) in [
            (geometry.leftStack, geometry.leftStackLines),
            (geometry.rightStack, geometry.rightStackLines),
        ] where !stack.isEmpty {
            context.fill(
                stack,
                with: .linearGradient(
                    Gradient(colors: [creamTop, creamBottom]),
                    startPoint: CGPoint(x: 0, y: stack.boundingRect.minY),
                    endPoint: CGPoint(x: 0, y: stack.boundingRect.maxY)
                )
            )
            context.stroke(lines, with: .color(.black.opacity(0.08)), lineWidth: 0.4)
        }

        paintPage(geometry.leftPage, outerX: OpenBookGeometry.leftOuterX, inwardSign: 1, in: &context)
        paintPage(geometry.rightPage, outerX: OpenBookGeometry.rightOuterX, inwardSign: -1, in: &context)

        for rows in [geometry.leftTextRows, geometry.rightTextRows] {
            context.stroke(
                rows,
                with: .color(.black.opacity(0.10)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            )
        }

        var crease = Path()
        crease.move(to: CGPoint(x: OpenBookGeometry.gutterX, y: 22 + min(geometry.leftDepth, geometry.rightDepth)))
        crease.addLine(to: CGPoint(x: OpenBookGeometry.gutterX, y: 100))
        context.stroke(crease, with: .color(.black.opacity(0.45)), lineWidth: 1)

        if geometry.isFinished {
            paintRibbon(in: &context)
        }
    }

    private static func paintBoards(tint: RGB, in context: inout GraphicsContext) {
        let base = Color(red: tint.red, green: tint.green, blue: tint.blue)
        let edge = Color(red: tint.red * 0.62, green: tint.green * 0.62, blue: tint.blue * 0.62)
        let rect = OpenBookGeometry.boardsRect
        let corner: CGFloat = 5
        let thickness = OpenBookGeometry.boardsThickness
        let top = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        let bottom = Path(roundedRect: rect.offsetBy(dx: 0, dy: thickness), cornerRadius: corner, style: .continuous)

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5))
            layer.fill(bottom, with: .color(edge))
            layer.fill(top, with: .color(base))
        }
        context.fill(
            top,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(0.14), .clear, .black.opacity(0.10)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.minX, y: rect.maxY)
            )
        )
        context.stroke(top, with: .color(edge), lineWidth: 1)
    }

    private static func paintPage(
        _ page: Path,
        outerX: CGFloat,
        inwardSign: CGFloat,
        in context: inout GraphicsContext
    ) {
        let gutterX = OpenBookGeometry.gutterX
        let width = abs(gutterX - outerX)
        context.fill(
            page,
            with: .linearGradient(
                Gradient(colors: [paper, paperShade]),
                startPoint: CGPoint(x: outerX, y: 0),
                endPoint: CGPoint(x: outerX + inwardSign * width * 0.85, y: 0)
            )
        )
        context.fill(
            page,
            with: .linearGradient(
                Gradient(colors: [.black.opacity(0.22), .black.opacity(0)]),
                startPoint: CGPoint(x: gutterX, y: 0),
                endPoint: CGPoint(x: gutterX - inwardSign * width * 0.18, y: 0)
            )
        )
        context.stroke(page, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
    }

    /// Notched-tail ribbon bookmark hanging from the gutter top over the right page.
    private static func paintRibbon(in context: inout GraphicsContext) {
        let x = OpenBookGeometry.gutterX + 4
        let top: CGFloat = 19
        var ribbon = Path()
        ribbon.move(to: CGPoint(x: x, y: top))
        ribbon.addLine(to: CGPoint(x: x + 5, y: top))
        ribbon.addLine(to: CGPoint(x: x + 5, y: top + 26))
        ribbon.addLine(to: CGPoint(x: x + 2.5, y: top + 21))
        ribbon.addLine(to: CGPoint(x: x, y: top + 26))
        ribbon.closeSubpath()
        context.fill(ribbon, with: .color(DashboardMomentumBackground.accent))
        context.stroke(ribbon, with: .color(.black.opacity(0.18)), lineWidth: 0.5)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
