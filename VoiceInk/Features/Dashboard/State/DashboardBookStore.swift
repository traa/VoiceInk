import AppKit
import Foundation
import os

/// Custom banner and cover tint for a built-in book (built-ins themselves are not persisted).
struct BuiltInArt: Codable, Equatable {
    var customBannerFile: String?
    var coverTint: RGB?

    var isEmpty: Bool { customBannerFile == nil && coverTint == nil }
}

@MainActor
final class DashboardBookStore: ObservableObject {
    enum StoreError: Error {
        case unknownBook
        case undecodableImage
    }

    private struct Envelope: Codable {
        var version: Int
        var books: [DashboardBook]
        var builtInArt: [String: BuiltInArt]?
    }

    private static let currentVersion = 1

    static let shared: DashboardBookStore = {
        let fileManager = FileManager.default
        let appSupportRoot =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true)
        let root = appSupportRoot.appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
        return DashboardBookStore(
            fileURL: root.appendingPathComponent("dashboard-books.json"),
            bannersDirectory: root.appendingPathComponent("BookBanners", isDirectory: true),
            fileManager: fileManager
        )
    }()

    @Published private(set) var customBooks: [DashboardBook] = []
    @Published private(set) var builtInArt: [String: BuiltInArt] = [:]

    private let fileURL: URL
    private let bannersDirectory: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "DashboardBookStore")
    private let saveQueue = DispatchQueue(label: "com.prakashjoshipax.voiceink.dashboardBookStore", qos: .utility)
    private var imageCache: [String: (modified: Date, image: NSImage)] = [:]

    init(fileURL: URL, bannersDirectory: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.bannersDirectory = bannersDirectory
        self.fileManager = fileManager
        load()
    }

    // MARK: - Books

    func add(_ book: DashboardBook) {
        customBooks.append(book)
        save()
    }

    func update(_ book: DashboardBook) {
        guard let index = customBooks.firstIndex(where: { $0.id == book.id }) else { return }
        customBooks[index] = book
        save()
    }

    func delete(id: String) {
        guard let index = customBooks.firstIndex(where: { $0.id == id }) else { return }
        let book = customBooks.remove(at: index)
        if let file = book.customBannerFile {
            removeBannerFile(named: file, bookID: id)
        }
        save()
    }

    func contains(workKey: String) -> Bool {
        customBooks.contains { $0.openLibraryWorkKey == workKey }
    }

    /// Built-ins merged with their `builtInArt`, hidden ones removed, custom books appended.
    func allBooks(hiddenBuiltIns: Set<String>) -> [DashboardBook] {
        let builtIns = DashboardProgressBenchmark.builtInBooks
            .filter { !hiddenBuiltIns.contains($0.id) }
            .map { book -> DashboardBook in
                guard let art = builtInArt[book.id] else { return book }
                var merged = book
                merged.customBannerFile = art.customBannerFile
                merged.coverTint = art.coverTint
                return merged
            }
        return builtIns + customBooks
    }

    // MARK: - Banners

    func setBanner(_ jpegData: Data, forBookID id: String) throws {
        let isCustom = customBooks.contains { $0.id == id }
        guard isCustom || Self.isBuiltInID(id) else { throw StoreError.unknownBook }
        guard let image = NSImage(data: jpegData) else { throw StoreError.undecodableImage }

        let fileName = "\(id).jpg"
        try fileManager.createDirectory(at: bannersDirectory, withIntermediateDirectories: true)
        try jpegData.write(to: bannersDirectory.appendingPathComponent(fileName), options: [.atomic])
        imageCache[id] = nil

        let tint = ImageTint.averageColor(of: image)
        mutateArt(forBookID: id) { file, coverTint in
            file = fileName
            coverTint = tint
        }
    }

    func removeBanner(forBookID id: String) {
        let file = customBooks.first { $0.id == id }?.customBannerFile ?? builtInArt[id]?.customBannerFile
        if let file {
            removeBannerFile(named: file, bookID: id)
        }
        mutateArt(forBookID: id) { file, coverTint in
            file = nil
            coverTint = nil
        }
    }

    func setCoverTint(_ tint: RGB?, forBookID id: String) {
        mutateArt(forBookID: id) { _, coverTint in
            coverTint = tint
        }
    }

    /// For background cover fetches that finish late: applies `tint` only when the custom book still exists,
    /// has no banner and no tint (a banner set meanwhile owns the tint). Returns whether it was applied.
    @discardableResult
    func setCoverTintIfUnset(_ tint: RGB, forBookID id: String) -> Bool {
        guard let current = customBooks.first(where: { $0.id == id }),
            current.coverTint == nil,
            current.customBannerFile == nil
        else { return false }
        setCoverTint(tint, forBookID: id)
        return true
    }

    /// Synchronous, disk-backed lookup cached by book ID and file modification date.
    func bannerImage(for book: DashboardBook) -> NSImage? {
        guard let file = book.customBannerFile else { return nil }
        let url = bannersDirectory.appendingPathComponent(file)
        guard
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        else {
            imageCache[book.id] = nil
            return nil
        }
        if let cached = imageCache[book.id], cached.modified == modified {
            return cached.image
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache[book.id] = (modified, image)
        return image
    }

    // MARK: - Persistence

    /// Blocks until queued writes have finished (tests).
    func waitForPendingWrites() {
        saveQueue.sync {}
    }

    private static func isBuiltInID(_ id: String) -> Bool {
        DashboardProgressBenchmark.builtInBooks.contains { $0.id == id }
    }

    private func mutateArt(forBookID id: String, _ change: (inout String?, inout RGB?) -> Void) {
        if let index = customBooks.firstIndex(where: { $0.id == id }) {
            var file = customBooks[index].customBannerFile
            var tint = customBooks[index].coverTint
            change(&file, &tint)
            customBooks[index].customBannerFile = file
            customBooks[index].coverTint = tint
            save()
        } else if Self.isBuiltInID(id) {
            var art = builtInArt[id] ?? BuiltInArt()
            change(&art.customBannerFile, &art.coverTint)
            builtInArt[id] = art.isEmpty ? nil : art
            save()
        }
    }

    private func removeBannerFile(named file: String, bookID: String) {
        imageCache[bookID] = nil
        let url = bannersDirectory.appendingPathComponent(file)
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        } catch {
            logger.error("Failed to remove banner \(file, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            customBooks = envelope.books
            builtInArt = envelope.builtInArt ?? [:]
        } catch {
            logger.error("Failed to load dashboard books: \(error, privacy: .public)")
            quarantineCorruptFile()
        }
    }

    private func quarantineCorruptFile() {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let destination = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(timestamp).json")
        do {
            try fileManager.moveItem(at: fileURL, to: destination)
        } catch {
            logger.error("Failed to quarantine corrupt dashboard books file: \(error, privacy: .public)")
        }
    }

    private func save() {
        let envelope = Envelope(version: Self.currentVersion, books: customBooks, builtInArt: builtInArt)
        let fileURL = fileURL
        let logger = logger
        let data: Data
        do {
            data = try JSONEncoder().encode(envelope)
        } catch {
            logger.error("Failed to encode dashboard books: \(error, privacy: .public)")
            return
        }
        saveQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                logger.error("Failed to save dashboard books: \(error, privacy: .public)")
            }
        }
    }
}
