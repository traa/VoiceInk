import CoreGraphics
import Foundation

/// Pure layout of the "grid colour reveal" over the hero's banner art (spec §8.7).
///
/// The art rectangle is covered exactly by `columns × rows` cells (no ragged or hidden cells), each at
/// most `maxCellSide` points and with an aspect ratio of 0.85...1.15 whenever the size allows. The cell
/// count `cellCount` aims at the page count (`min(totalPages, 240)`), raised so cells stay small for tiny
/// books; the reveal is proportional (`filled = floor(p · cellCount)`), so a cell is `pagesPerCell`
/// (possibly fractional) pages. Cells fill column-major: top to bottom within a column, columns left to
/// right (like the consistency calendar).
struct ProgressGrid: Equatable {
    struct Position: Equatable {
        let column: Int
        let row: Int
    }

    static let maxCells = 240
    /// Cells never exceed this side length (points) when the art is large enough to be subdivided.
    static let maxCellSide: CGFloat = 44
    static let minAspect = 0.85
    static let maxAspect = 1.15
    /// Visible gap between neighbouring cells, in points.
    static let gap: CGFloat = 1

    let columns: Int
    let rows: Int
    let cellCount: Int
    let pagesPerCell: Double
    /// Size of one grid slot (cell plus its share of the gap). `cellWidth × columns` is the art width.
    let cellWidth: CGFloat
    let cellHeight: CGFloat

    static func make(totalPages: Int, size: CGSize) -> ProgressGrid {
        let pages = max(totalPages, 1)
        let width = size.width.isFinite ? max(size.width, 1) : 1
        let height = size.height.isFinite ? max(size.height, 1) : 1

        // Fewest cells keeping every cell within `maxCellSide`, never more than the cap.
        let smallestCount = Int((width / maxCellSide).rounded(.up)) * Int((height / maxCellSide).rounded(.up))
        let target = min(max(min(pages, maxCells), smallestCount), maxCells)

        var best: (columns: Int, rows: Int, score: Double)?
        var fallback: (columns: Int, rows: Int, score: Double)?
        for columns in 1...maxCells {
            for rows in 1...(maxCells / columns) {
                let count = columns * rows
                let slotWidth = Double(width) / Double(columns)
                let slotHeight = Double(height) / Double(rows)
                let aspect = slotWidth / slotHeight
                let countError = abs(Double(count - target)) / Double(target)
                let aspectError = abs(log(aspect))
                if aspect >= minAspect, aspect <= maxAspect, CGFloat(slotWidth) <= maxCellSide + 0.5 || count == maxCells,
                    best == nil || countError < best!.score {
                    best = (columns, rows, countError)
                }
                let blended = countError + aspectError
                if fallback == nil || blended < fallback!.score {
                    fallback = (columns, rows, blended)
                }
            }
        }
        let chosen = best ?? fallback ?? (1, 1, 0)
        let count = chosen.columns * chosen.rows
        return ProgressGrid(
            columns: chosen.columns,
            rows: chosen.rows,
            cellCount: count,
            pagesPerCell: Double(pages) / Double(count),
            cellWidth: width / CGFloat(chosen.columns),
            cellHeight: height / CGFloat(chosen.rows)
        )
    }

    /// Column-major position of the `index`-th cell.
    func position(ofCell index: Int) -> Position {
        Position(column: index / rows, row: index % rows)
    }

    /// Drawn rectangle of a cell: its slot inset by half the gap on every side.
    func rect(ofCell index: Int) -> CGRect {
        let position = position(ofCell: index)
        let half = Self.gap / 2
        return CGRect(
            x: CGFloat(position.column) * cellWidth + half,
            y: CGFloat(position.row) * cellHeight + half,
            width: max(cellWidth - Self.gap, 0),
            height: max(cellHeight - Self.gap, 0)
        )
    }
}

/// How many cells are in full colour for a progress ratio, plus the exact page count for the caption.
struct GridReveal: Equatable {
    let cellCount: Int
    let filledCells: Int
    /// Opacity (0..<1) of the cell right after the last filled one.
    let partialOpacity: Double
    let isFinished: Bool

    /// - Parameter ratio: `words / bookWords`, clamped here to 0...1 (NaN counts as 0).
    static func make(ratio: Double, cellCount: Int) -> GridReveal {
        let cells = max(cellCount, 0)
        let progress = clamped(ratio)
        guard cells > 0 else {
            return GridReveal(cellCount: 0, filledCells: 0, partialOpacity: 0, isFinished: progress >= 1)
        }
        if progress >= 1 {
            return GridReveal(cellCount: cells, filledCells: cells, partialOpacity: 0, isFinished: true)
        }
        var exact = progress * Double(cells)
        // `k / n * n` can land a hair below `k`; snap so exact boundaries fill exactly `k` cells.
        let nearest = exact.rounded()
        if abs(exact - nearest) < 1e-9 { exact = nearest }
        let filled = min(Int(exact.rounded(.down)), cells - 1)
        return GridReveal(
            cellCount: cells,
            filledCells: filled,
            partialOpacity: exact - Double(filled),
            isFinished: false
        )
    }

    /// Full-colour opacity of one cell: 1 when filled, the fractional part for the next one, else 0.
    func opacity(ofCell index: Int) -> Double {
        guard index >= 0, index < cellCount else { return 0 }
        if index < filledCells { return 1 }
        if index == filledCells { return partialOpacity }
        return 0
    }

    /// Pages shown in the caption. Never equals the total before the book is finished.
    static func pagesDictated(ratio: Double, totalPages: Int) -> Int {
        let pages = max(totalPages, 2)
        let progress = clamped(ratio)
        let rounded = Int((progress * Double(pages)).rounded())
        return progress >= 1 ? pages : min(pages - 1, rounded)
    }

    private static func clamped(_ ratio: Double) -> Double {
        if ratio.isNaN { return 0 }
        return min(max(ratio, 0), 1)
    }
}

enum ProgressCaption {
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
