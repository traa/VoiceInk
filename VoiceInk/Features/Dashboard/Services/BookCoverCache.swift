import AppKit
import Foundation

/// Disk-backed cache of Open Library `-L` cover images, with an in-memory `NSCache` in front.
///
/// The hero only calls the synchronous, disk-only `cachedImage(for:)`; `image(for:)` is for
/// background fetches. Failures of any kind yield `nil` and are never cached.
final class BookCoverCache: @unchecked Sendable {
    static let shared = BookCoverCache(
        directory: FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            .appendingPathComponent("BookCovers", isDirectory: true),
        session: BookServiceHTTP.makeEphemeralSession()
    )

    private let directory: URL
    private let session: URLSession
    private let memory = NSCache<NSNumber, NSImage>()

    init(directory: URL, session: URLSession) {
        self.directory = directory
        self.session = session
    }

    static func coverURL(for coverID: Int) -> URL {
        URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg?default=false")!
    }

    func fileURL(for coverID: Int) -> URL {
        directory.appendingPathComponent("\(coverID)-L.jpg", isDirectory: false)
    }

    /// Synchronous and offline: memory, then disk. Never touches the network.
    func cachedImage(for coverID: Int) -> NSImage? {
        let key = NSNumber(value: coverID)
        if let image = memory.object(forKey: key) { return image }
        guard let image = NSImage(contentsOf: fileURL(for: coverID)) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Deletes the cached cover file and evicts the in-memory entry. A missing cover is a no-op.
    func removeCover(for coverID: Int) {
        memory.removeObject(forKey: NSNumber(value: coverID))
        try? FileManager.default.removeItem(at: fileURL(for: coverID))
    }

    func image(for coverID: Int) async -> NSImage? {
        if let image = cachedImage(for: coverID) { return image }

        var request = URLRequest(url: Self.coverURL(for: coverID))
        request.timeoutInterval = BookServiceHTTP.requestTimeout
        request.setValue(BookServiceHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty,
              let image = NSImage(data: data),
              image.isValid
        else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: coverID), options: .atomic)
        } catch {
            // Disk write failed: still hand back the image, it just won't persist.
        }
        memory.setObject(image, forKey: NSNumber(value: coverID))
        return image
    }
}
