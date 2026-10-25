import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BannerImportError: Error, Equatable {
    case invalidURL
    case unsupportedScheme
    case unreachable
    case timedOut
    case notAnImage
    case tooLarge
    case tooSmall

    var userMessage: String {
        switch self {
        case .invalidURL, .unsupportedScheme:
            String(localized: "Enter a web address starting with http:// or https://.")
        case .unreachable:
            String(localized: "Couldn't download that image. Check the address and your connection.")
        case .timedOut:
            String(localized: "The server took too long to respond.")
        case .notAnImage:
            String(localized: "That doesn't look like an image (PNG, JPEG or HEIC).")
        case .tooLarge:
            String(localized: "That image is larger than 10 MB.")
        case .tooSmall:
            String(localized: "That image is too small to use as a banner (at least 300 px wide).")
        }
    }
}

protocol BannerImporting: Sendable {
    func importImage(from url: URL) async throws -> Data
    func importImage(fromFile url: URL) throws -> Data
}

/// Turns a user-supplied URL or file into normalised banner bytes (JPEG, at most 1600 px wide).
/// It never writes to disk; `DashboardBookStore.setBanner` does.
struct BannerImageImporter: BannerImporting {
    static let maxBytes = 10 * 1024 * 1024
    static let maxPixelWidth = 1600
    static let minPixelWidth = 300
    static let defaultOverallTimeout: TimeInterval = 10
    static let jpegQuality = 0.85

    private let session: URLSession
    private let overallTimeout: TimeInterval

    init(
        session: URLSession = BannerImageImporter.makeSession(),
        overallTimeout: TimeInterval = BannerImageImporter.defaultOverallTimeout
    ) {
        self.session = session
        self.overallTimeout = overallTimeout
    }

    static func makeSession() -> URLSession {
        BookServiceHTTP.makeEphemeralSession()
    }

    // MARK: - Remote

    func importImage(from url: URL) async throws -> Data {
        try Self.validateScheme(of: url)
        let downloaded = try await withDeadline(overallTimeout) { try await download(url) }
        return try Self.normalise(downloaded)
    }

    /// `.invalidURL` for a scheme-less URL or an http(s) URL without host; any other scheme is unsupported.
    private static func validateScheme(of url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { throw BannerImportError.invalidURL }
        guard scheme == "http" || scheme == "https" else { throw BannerImportError.unsupportedScheme }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { throw BannerImportError.invalidURL }
    }

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = BookServiceHTTP.requestTimeout
        request.setValue(BookServiceHTTP.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let redirects = RedirectPolicy()
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
            if redirects.refusedNonHTTPRedirect { throw BannerImportError.unsupportedScheme }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw BannerImportError.unreachable
            }
            if http.expectedContentLength > Int64(Self.maxBytes) { throw BannerImportError.tooLarge }

            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxBytes { throw BannerImportError.tooLarge }
            }
            return data
        } catch let error as BannerImportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if redirects.refusedNonHTTPRedirect { throw BannerImportError.unsupportedScheme }
            switch error.code {
            case .timedOut: throw BannerImportError.timedOut
            case .cancelled: throw CancellationError()
            default: throw BannerImportError.unreachable
            }
        } catch {
            throw BannerImportError.unreachable
        }
    }

    // MARK: - Local file

    func importImage(fromFile url: URL) throws -> Data {
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw BannerImportError.notAnImage
        }
        if let size, size > Self.maxBytes { throw BannerImportError.tooLarge }
        guard let data = try? Data(contentsOf: url) else { throw BannerImportError.notAnImage }
        if data.count > Self.maxBytes { throw BannerImportError.tooLarge }
        return try Self.normalise(data)
    }

    // MARK: - Decoding

    /// Validates the bytes with ImageIO (never trusting `Content-Type`) and re-encodes them as JPEG.
    private static func normalise(_ data: Data) throws -> Data {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              type.conforms(to: .image), !type.conforms(to: .pdf), !type.conforms(to: .svg),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw BannerImportError.notAnImage }

        // EXIF orientations 5...8 swap the axes, so the displayed width is the stored height.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let displayedWidth = (5...8).contains(orientation) ? pixelHeight : pixelWidth
        guard displayedWidth >= minPixelWidth else { throw BannerImportError.tooSmall }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelWidth,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw BannerImportError.notAnImage
        }
        return try encodeJPEG(flattenedOntoWhite: thumbnail)
    }

    private static func encodeJPEG(flattenedOntoWhite image: CGImage) throws -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { throw BannerImportError.notAnImage }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)

        let output = NSMutableData()
        guard let flattened = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw BannerImportError.notAnImage }
        CGImageDestinationAddImage(
            destination,
            flattened,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw BannerImportError.notAnImage }
        return output as Data
    }
}

// MARK: - Redirects

/// Per-request delegate: redirects may only lead to http/https.
private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var refused = false

    var refusedNonHTTPRedirect: Bool { lock.withLock { refused } }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let scheme = request.url?.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
            completionHandler(request)
        } else {
            lock.withLock { refused = true }
            completionHandler(nil)
        }
    }
}

// MARK: - Overall deadline

/// Runs `operation` against a wall-clock deadline without waiting for a slow loser: whichever
/// finishes first resumes the caller, the other task is cancelled.
private func withDeadline<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.install(continuation)
            let work = Task {
                do { race.finish(.success(try await operation())) } catch { race.finish(.failure(error)) }
            }
            let timer = Task {
                do { try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) } catch { return }
                race.finish(.failure(BannerImportError.timedOut))
            }
            race.setTasks([work, timer])
        }
    } onCancel: {
        race.cancel()
    }
}

private final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false
    private var cancelRequested = false

    func install(_ continuation: CheckedContinuation<T, Error>) {
        let alreadyCancelled: Bool = lock.withLock {
            if cancelRequested {
                finished = true
                return true
            }
            self.continuation = continuation
            return false
        }
        if alreadyCancelled { continuation.resume(throwing: CancellationError()) }
    }

    func setTasks(_ newTasks: [Task<Void, Never>]) {
        let cancelNow: Bool = lock.withLock {
            if finished { return true }
            tasks = newTasks
            return false
        }
        if cancelNow { newTasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<T, Error>) {
        let (continuation, tasks): (CheckedContinuation<T, Error>?, [Task<Void, Never>]) = lock.withLock {
            guard !finished else { return (nil, []) }
            finished = true
            return (self.continuation, self.tasks)
        }
        continuation?.resume(with: result)
        tasks.forEach { $0.cancel() }
    }

    func cancel() {
        lock.withLock { cancelRequested = true }
        finish(.failure(CancellationError()))
    }
}
