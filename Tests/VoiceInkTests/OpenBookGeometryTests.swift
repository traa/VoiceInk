import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import VoiceInk

struct OpenBookGeometryTests {
    private func make(_ progress: Double, totalPages: Int = 600) -> OpenBookGeometry {
        OpenBookGeometry.make(size: OpenBookGeometry.defaultSize, progress: progress, totalPages: totalPages)
    }

    private func isSane(_ value: CGFloat) -> Bool {
        value.isFinite && value >= 0
    }

    @Test func oneSixthProgressGivesOneToFiveStacks() {
        let geometry = make(100.0 / 600)
        let share = geometry.leftDepth / (geometry.leftDepth + geometry.rightDepth)
        #expect(abs(share - 1.0 / 6) <= 0.01)
        #expect(abs(geometry.leftDepth - 2.33) < 0.01)
        #expect(abs(geometry.rightDepth - 11.67) < 0.01)
        #expect(geometry.pagesDictated == 100)
        #expect(OpenBookGeometry.totalStackDepth == 14)
    }

    @Test func zeroProgressHasNoLeftStack() {
        let geometry = make(0)
        #expect(geometry.leftDepth == 0)
        #expect(geometry.rightDepth == 14)
        #expect(geometry.pagesDictated == 0)
        #expect(!geometry.isFinished)
    }

    @Test func fullProgressIsFinished() {
        let geometry = make(1)
        #expect(geometry.rightDepth == 0)
        #expect(geometry.leftDepth == 14)
        #expect(geometry.isFinished)
        #expect(geometry.pagesDictated == geometry.totalPages)
        #expect(geometry.pagesDictated == 600)
    }

    @Test func overOneClampsToOne() {
        let geometry = make(3.7)
        #expect(geometry.progress == 1)
        #expect(geometry.isFinished)
        #expect(geometry.rightDepth == 0)
    }

    @Test func negativeAndNaNProgressClampToZero() {
        for value in [-0.5, -Double.infinity, Double.nan] {
            let geometry = make(value)
            #expect(geometry.progress == 0)
            #expect(geometry.leftDepth == 0)
            #expect(geometry.rightDepth == 14)
            #expect(geometry.pagesDictated == 0)
        }
    }

    @Test func hairlineOnlyNearEdges() {
        #expect(make(0.02).leftDepth >= 0.5)
        #expect(make(0.98).rightDepth >= 0.5)

        let half = make(0.5)
        #expect(half.leftDepth == 7.0)
        #expect(half.rightDepth == 7.0)

        let low = make(0.04)
        #expect(low.leftDepth == 14 * 0.04)
        #expect(low.rightDepth == 14 * (1 - 0.04))

        let high = make(0.96)
        #expect(high.leftDepth == 14 * 0.96)
        #expect(high.rightDepth == 14 * (1 - 0.96))
    }

    @Test func tinyBookTwoPagesHasSaneGeometry() {
        let geometry = make(0.5, totalPages: 2)
        #expect(geometry.pagesDictated == 1)
        #expect(isSane(geometry.leftDepth))
        #expect(isSane(geometry.rightDepth))
        #expect(!geometry.leftPage.isEmpty)
        #expect(!geometry.rightPage.isEmpty)
        #expect(!geometry.leftStack.isEmpty)
        #expect(!geometry.rightStack.isEmpty)
        for path in [geometry.leftPage, geometry.rightPage, geometry.leftStack, geometry.rightStack] {
            let bounds = path.boundingRect
            #expect(bounds.minX.isFinite && bounds.minY.isFinite && bounds.width.isFinite && bounds.height.isFinite)
        }
    }

    @Test func tinyProgressOfHugeBookKeepsLeftVisible() {
        let geometry = make(0.0001, totalPages: 1_500)
        #expect(geometry.leftDepth == 0.5)
        #expect(geometry.pagesDictated == 0)
        #expect(!geometry.leftStack.isEmpty)
    }

    @Test func stackLineCountFollowsDepth() {
        for progress in [0.0, 0.0001, 0.02, 100.0 / 600, 0.5, 0.9, 0.98, 1.0] {
            let geometry = make(progress)
            let expectedLeft = geometry.leftDepth > 0 ? max(1, Int(geometry.leftDepth / 1.1)) : 0
            let expectedRight = geometry.rightDepth > 0 ? max(1, Int(geometry.rightDepth / 1.1)) : 0
            #expect(geometry.leftStackLineCount == expectedLeft)
            #expect(geometry.rightStackLineCount == expectedRight)
        }
        #expect(make(0).leftStackLineCount == 0)
        #expect(make(1).rightStackLineCount == 0)
        #expect(make(0).rightStackLineCount == 12)
    }

    @Test func captionVariants() {
        #expect(
            OpenBookCaption.text(pagesDictated: 100, totalPages: 600, ratio: 1.0 / 6, isFinished: false)
                == String(localized: "~\(Formatters.formattedNumber(100)) of \(Formatters.formattedNumber(600)) pages dictated")
        )
        #expect(
            OpenBookCaption.text(pagesDictated: 100, totalPages: 600, ratio: 1.0 / 6, isFinished: false)
                == "~100 of 600 pages dictated"
        )
        #expect(
            OpenBookCaption.text(pagesDictated: 600, totalPages: 600, ratio: 1.0, isFinished: true)
                == "All 600 pages dictated"
        )
        let repeated = OpenBookCaption.text(pagesDictated: 600, totalPages: 600, ratio: 2.5, isFinished: true)
        #expect(repeated.contains("2"))
        #expect(repeated.contains("×"))
        #expect(repeated.contains("600"))
        #expect(
            OpenBookCaption.text(pagesDictated: 0, totalPages: 600, ratio: 0, isFinished: false)
                == "~0 of 600 pages dictated"
        )
    }
}
