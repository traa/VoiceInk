import AppKit
import Foundation
import SwiftUI
import Testing
@testable import VoiceInk

/// Regression for "Manage Books… does nothing on first click".
///
/// The dashboard used to store the panel's view model in an optional `@State` and flip the presentation
/// flag right after; the side-panel closure still read `nil` on first presentation, so the first open
/// showed nothing. The panel now builds its own view model, so the content exists the moment the panel is
/// built, from a single presentation flag.
@MainActor
struct ManageBooksPanelHostTests {
    private func makeStore() -> (DashboardBookStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManageBooksPanelHostTests-\(UUID().uuidString)", isDirectory: true)
        let store = DashboardBookStore(
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true)
        )
        return (store, root)
    }

    @Test func hostRendersPanelContentOnFirstBuild() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let host = ManageBooksPanelHost(
            store: store,
            hidden: .constant(HiddenBookIDs()),
            selectedID: .constant(""),
            totalWords: 0,
            onClose: {},
            onAddBook: {}
        )
        let hosting = NSHostingView(rootView: host.frame(width: 400, height: 700))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 700)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        // An empty panel (nil view model) draws nothing; the real panel paints its title, rows and background.
        var opaquePixels = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                opaquePixels += 1
            }
        }
        #expect(opaquePixels > 100)
    }
}
