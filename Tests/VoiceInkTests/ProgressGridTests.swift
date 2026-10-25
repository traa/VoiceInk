import CoreGraphics
import Foundation
import Testing
@testable import VoiceInk

struct ProgressGridTests {
    private let artSize = CGSize(width: 375, height: 190)

    // MARK: - Layout

    @Test func cellCountIsPagesForSmallBooksAndCappedAt240() {
        #expect(ProgressGrid.maxCells == 240)
        for pages in [2, 3, 17, 90, 239, 240] {
            #expect(ProgressGrid.make(totalPages: pages, size: artSize).cellCount == pages)
        }
        for pages in [241, 600, 2_545, 100_000] {
            #expect(ProgressGrid.make(totalPages: pages, size: artSize).cellCount == 240)
        }
    }

    @Test func pagesPerCellIsPagesOverCells() {
        #expect(ProgressGrid.make(totalPages: 90, size: artSize).pagesPerCell == 1)
        #expect(ProgressGrid.make(totalPages: 600, size: artSize).pagesPerCell == 2.5)
        #expect(ProgressGrid.make(totalPages: 2_400, size: artSize).pagesPerCell == 10)
    }

    @Test func gridAlwaysHoldsEveryCellAndCellsAreRoughlySquare() {
        for pages in [2, 5, 20, 77, 90, 118, 240, 600, 2_545] {
            for size in [CGSize(width: 375, height: 190), CGSize(width: 300, height: 160), CGSize(width: 520, height: 220)] {
                let grid = ProgressGrid.make(totalPages: pages, size: size)
                #expect(grid.columns * grid.rows >= grid.cellCount)
                // No fully empty trailing column.
                #expect((grid.columns - 1) * grid.rows < grid.cellCount)
                if grid.cellCount >= 24 {
                    let aspect = grid.cellWidth / grid.cellHeight
                    #expect(aspect > 0.6 && aspect < 1.6, "pages \(pages) size \(size): aspect \(aspect)")
                }
                #expect(grid.cellWidth * CGFloat(grid.columns) <= size.width + 0.001)
                #expect(grid.cellHeight * CGFloat(grid.rows) <= size.height + 0.001)
            }
        }
    }

    @Test func degenerateInputsStaySane() {
        let tiny = ProgressGrid.make(totalPages: 0, size: artSize)
        #expect(tiny.cellCount == 1 && tiny.columns == 1 && tiny.rows == 1)
        let negative = ProgressGrid.make(totalPages: -5, size: artSize)
        #expect(negative.cellCount == 1)
        let zeroSize = ProgressGrid.make(totalPages: 100, size: .zero)
        #expect(zeroSize.columns * zeroSize.rows >= zeroSize.cellCount)
        #expect(zeroSize.cellWidth.isFinite && zeroSize.cellHeight.isFinite)
    }

    @Test func cellsFillColumnMajorTopToBottomThenLeftToRight() {
        let grid = ProgressGrid.make(totalPages: 90, size: artSize)
        #expect(grid.position(ofCell: 0) == .init(column: 0, row: 0))
        #expect(grid.position(ofCell: 1) == .init(column: 0, row: 1))
        #expect(grid.position(ofCell: grid.rows - 1) == .init(column: 0, row: grid.rows - 1))
        #expect(grid.position(ofCell: grid.rows) == .init(column: 1, row: 0))
        let last = grid.position(ofCell: grid.cellCount - 1)
        #expect(last.column == grid.columns - 1)
        // Rectangles of consecutive cells in one column move down; the next column starts at the top, further right.
        let r0 = grid.rect(ofCell: 0), r1 = grid.rect(ofCell: 1), rNext = grid.rect(ofCell: grid.rows)
        #expect(r1.minY > r0.minY && r1.minX == r0.minX)
        #expect(rNext.minX > r0.minX && rNext.minY == r0.minY)
    }

    @Test func cellRectsStayInsideTheArtAndDoNotOverlap() {
        let grid = ProgressGrid.make(totalPages: 240, size: artSize)
        var rects: [CGRect] = []
        for index in 0..<grid.cellCount {
            let rect = grid.rect(ofCell: index)
            #expect(CGRect(origin: .zero, size: artSize).insetBy(dx: -0.001, dy: -0.001).contains(rect))
            rects.append(rect)
        }
        for i in 0..<rects.count {
            for j in (i + 1)..<rects.count {
                #expect(!rects[i].insetBy(dx: 0.01, dy: 0.01).intersects(rects[j].insetBy(dx: 0.01, dy: 0.01)))
            }
        }
    }

    // MARK: - Reveal math

    @Test func zeroProgressFillsNothing() {
        let reveal = GridReveal.make(ratio: 0, cellCount: 240)
        #expect(reveal.filledCells == 0)
        #expect(reveal.partialOpacity == 0)
        #expect(!reveal.isFinished)
        #expect(reveal.opacity(ofCell: 0) == 0)
    }

    @Test func fullProgressFillsEverything() {
        let reveal = GridReveal.make(ratio: 1, cellCount: 240)
        #expect(reveal.filledCells == 240)
        #expect(reveal.partialOpacity == 0)
        #expect(reveal.isFinished)
        #expect(reveal.opacity(ofCell: 239) == 1)
    }

    @Test func oneSixthOfSixHundredPagesIsAboutOneSixthOfTheCells() {
        let reveal = GridReveal.make(ratio: 100.0 / 600.0, cellCount: 240)
        let exact = reveal.filledCells.asDouble + reveal.partialOpacity
        #expect(abs(exact / 240 - 1.0 / 6.0) < 1.0 / 240.0)
        #expect(reveal.filledCells == 40)
    }

    @Test func nextCellIsPartiallyRevealedByTheFractionalPart() {
        let reveal = GridReveal.make(ratio: 0.5 + 0.25 / 240.0, cellCount: 240)
        #expect(reveal.filledCells == 120)
        #expect(abs(reveal.partialOpacity - 0.25) < 1e-9)
        #expect(reveal.opacity(ofCell: 119) == 1)
        #expect(abs(reveal.opacity(ofCell: 120) - 0.25) < 1e-9)
        #expect(reveal.opacity(ofCell: 121) == 0)
        #expect(reveal.opacity(ofCell: -1) == 0)
        #expect(reveal.opacity(ofCell: 500) == 0)
    }

    @Test func nearlyFinishedNeverShowsAllCellsFilled() {
        let reveal = GridReveal.make(ratio: 0.99999, cellCount: 240)
        #expect(reveal.filledCells == 239)
        #expect(reveal.partialOpacity > 0.9)
        #expect(!reveal.isFinished)
    }

    @Test func ratiosAboveOneClampAndBadValuesAreSafe() {
        #expect(GridReveal.make(ratio: 7.5, cellCount: 90).filledCells == 90)
        #expect(GridReveal.make(ratio: 7.5, cellCount: 90).isFinished)
        #expect(GridReveal.make(ratio: -3, cellCount: 90).filledCells == 0)
        #expect(GridReveal.make(ratio: .nan, cellCount: 90).filledCells == 0)
        #expect(GridReveal.make(ratio: .infinity, cellCount: 90).filledCells == 90)
        #expect(GridReveal.make(ratio: -.infinity, cellCount: 90).filledCells == 0)
        #expect(GridReveal.make(ratio: 0.5, cellCount: 0).filledCells == 0)
    }

    @Test func exactCellBoundariesAreNotLostToFloatingPoint() {
        for cells in [3, 7, 90, 240] {
            for k in 0...cells {
                let reveal = GridReveal.make(ratio: Double(k) / Double(cells), cellCount: cells)
                #expect(reveal.filledCells == k, "k \(k) of \(cells)")
                #expect(reveal.partialOpacity == 0)
            }
        }
    }

    // MARK: - Pages dictated and caption

    @Test func unfinishedBookNeverShowsAllPages() {
        #expect(GridReveal.pagesDictated(ratio: 0.9999, totalPages: 600) == 599)
        #expect(GridReveal.pagesDictated(ratio: 0.9999, totalPages: 2) == 1)
        #expect(GridReveal.pagesDictated(ratio: 1, totalPages: 600) == 600)
        #expect(GridReveal.pagesDictated(ratio: 0.5, totalPages: 600) == 300)
        #expect(GridReveal.pagesDictated(ratio: 1.0 / 6, totalPages: 600) == 100)
        #expect(GridReveal.pagesDictated(ratio: .nan, totalPages: 600) == 0)
        #expect(GridReveal.pagesDictated(ratio: 3, totalPages: 600) == 600)
    }

    @Test func captionVariants() {
        #expect(
            ProgressCaption.text(pagesDictated: 100, totalPages: 600, ratio: 1.0 / 6, isFinished: false)
                == "~100 of 600 pages dictated"
        )
        #expect(
            ProgressCaption.text(pagesDictated: 100, totalPages: 600, ratio: 1.0 / 6, isFinished: false)
                == String(localized: "~\(Formatters.formattedNumber(100)) of \(Formatters.formattedNumber(600)) pages dictated")
        )
        #expect(
            ProgressCaption.text(pagesDictated: 600, totalPages: 600, ratio: 1.0, isFinished: true)
                == "All 600 pages dictated"
        )
        let repeated = ProgressCaption.text(pagesDictated: 600, totalPages: 600, ratio: 2.5, isFinished: true)
        #expect(repeated.contains("2") && repeated.contains("×") && repeated.contains("600"))
        #expect(
            ProgressCaption.text(pagesDictated: 0, totalPages: 600, ratio: 0, isFinished: false)
                == "~0 of 600 pages dictated"
        )
    }

    @Test func multiplierOnlyOnRepeats() {
        #expect(!ProgressCaption.text(pagesDictated: 600, totalPages: 600, ratio: 1.99, isFinished: true).contains("×"))
        #expect(ProgressCaption.text(pagesDictated: 600, totalPages: 600, ratio: 2, isFinished: true).contains("×"))
        #expect(!ProgressCaption.text(pagesDictated: 300, totalPages: 600, ratio: 0.5, isFinished: false).contains("×"))
    }

    @Test func captionNeverReadsNOfNBeforeFinished() {
        for ratio in stride(from: 0.0, to: 1.0, by: 0.0173) {
            let reveal = GridReveal.make(ratio: ratio, cellCount: 90)
            let pages = GridReveal.pagesDictated(ratio: ratio, totalPages: 90)
            #expect(pages < 90)
            #expect(!reveal.isFinished)
        }
    }
}

private extension Int {
    var asDouble: Double { Double(self) }
}
