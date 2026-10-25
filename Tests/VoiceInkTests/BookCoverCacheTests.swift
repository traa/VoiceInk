import AppKit
import Foundation
import Testing
@testable import VoiceInk

struct BookCoverCacheTests {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BookCoverCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private static func pngData(width: Int = 8, height: Int = 12) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(.brown, atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }

    private func cache(
        directory: URL = BookCoverCacheTests.temporaryDirectory(),
        handler: @escaping StubURLProtocol.Handler
    ) -> BookCoverCache {
        BookCoverCache(directory: directory, session: StubURLProtocol.makeSession(handler: handler))
    }

    @Test func coverURLUsesLargeSizeAndDefaultFalse() {
        #expect(BookCoverCache.coverURL(for: 42).absoluteString == "https://covers.openlibrary.org/b/id/42-L.jpg?default=false")
    }

    @Test func fileURLIsCoverIDDashL() {
        let directory = Self.temporaryDirectory()
        let cache = cache(directory: directory) { request in
            (StubURLProtocol.response(for: request, status: 500), Data())
        }
        let url = cache.fileURL(for: 42)
        #expect(url.lastPathComponent == "42-L.jpg")
        #expect(url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
    }

    @Test func imageDownloadsOnceThenServesFromDisk() async {
        let requests = StubLockedBox<[URLRequest]>([])
        let png = Self.pngData()
        let directory = Self.temporaryDirectory()
        let cache = cache(directory: directory) { request in
            requests.value.append(request)
            return (StubURLProtocol.response(for: request, status: 200, headers: ["Content-Type": "image/jpeg"]), png)
        }

        let first = await cache.image(for: 42)
        let second = await cache.image(for: 42)

        #expect(first != nil)
        #expect(second != nil)
        #expect(requests.value.count == 1)
        #expect(requests.value.first?.url == BookCoverCache.coverURL(for: 42))
        #expect(requests.value.first?.value(forHTTPHeaderField: "Accept") != "application/json")
        #expect(FileManager.default.fileExists(atPath: cache.fileURL(for: 42).path))
        #expect(cache.cachedImage(for: 42) != nil)

        // A fresh instance over the same directory serves from disk without the network.
        let offline = BookCoverCache(directory: directory, session: StubURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        })
        #expect(offline.cachedImage(for: 42) != nil)
        #expect(await offline.image(for: 42) != nil)
    }

    @Test func cachedImageIsNilWithoutNetworkOrFile() {
        let requests = StubLockedBox(0)
        let cache = cache { request in
            requests.value += 1
            return (StubURLProtocol.response(for: request, status: 200), Self.pngData())
        }
        #expect(cache.cachedImage(for: 7) == nil)
        #expect(requests.value == 0)
    }

    @Test func notFoundReturnsNilAndWritesNothing() async {
        let cache = cache { request in
            (StubURLProtocol.response(for: request, status: 404), Self.pngData())
        }
        #expect(await cache.image(for: 42) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL(for: 42).path))
        #expect(cache.cachedImage(for: 42) == nil)
    }

    @Test func corruptDownloadIsNotCached() async {
        let cache = cache { request in
            (StubURLProtocol.response(for: request, status: 200, headers: ["Content-Type": "image/jpeg"]), Data("not an image".utf8))
        }
        #expect(await cache.image(for: 42) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.fileURL(for: 42).path))
        #expect(cache.cachedImage(for: 42) == nil)
    }
}
