import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VoiceInk

struct BannerImageImporterTests {
    // MARK: - Fixtures

    /// Encodes a solid-colour image of the given pixel size with `CGImageDestination`.
    private static func makeImageData(
        width: Int,
        height: Int,
        type: UTType = .png,
        orientation: Int? = nil
    ) -> Data? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func png(width: Int, height: Int) throws -> Data {
        try #require(makeImageData(width: width, height: height, type: .png))
    }

    private static func pdfData() -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 800, height: 600)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let context = CGContext(consumer: consumer, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static let svgData = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="800" height="600"><rect width="800" height="600" fill="red"/></svg>
    """.utf8)

    private struct Decoded {
        let type: UTType?
        let width: Int
        let height: Int
    }

    private static func decode(_ data: Data) throws -> Decoded {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        return Decoded(
            type: type,
            width: try #require(properties[kCGImagePropertyPixelWidth] as? Int),
            height: try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        )
    }

    private static let imageURL = URL(string: "https://images.example.com/banner.png")!

    /// Importer whose session answers every request with `handler` and records the requests.
    private static func importer(
        overallTimeout: TimeInterval = 10,
        requests: StubLockedBox<[URLRequest]> = StubLockedBox([]),
        handler: @escaping StubURLProtocol.Handler
    ) -> BannerImageImporter {
        let session = StubURLProtocol.makeSession { request in
            requests.value.append(request)
            return try handler(request)
        }
        return BannerImageImporter(session: session, overallTimeout: overallTimeout)
    }

    private static func serving(
        _ body: Data,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "image/png"]
    ) -> BannerImageImporter {
        importer { request in
            (StubURLProtocol.response(for: request, status: status, headers: headers), body)
        }
    }

    private static func importError(
        _ operation: () async throws -> Data
    ) async -> BannerImportError? {
        do {
            _ = try await operation()
            return nil
        } catch let error as BannerImportError {
            return error
        } catch {
            Issue.record("Unexpected error type: \(error)")
            return nil
        }
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BannerImageImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Decoding and normalisation

    @Test func acceptsPNGJPEGAndHEICAndOutputsJPEG() async throws {
        for type in [UTType.png, .jpeg, .heic] {
            let input = try #require(Self.makeImageData(width: 640, height: 400, type: type), "Could not encode \(type)")
            let output = try await Self.serving(input).importImage(from: Self.imageURL)
            let decoded = try Self.decode(output)
            #expect(decoded.type == .jpeg, "input \(type)")
            #expect(decoded.width == 640)
            #expect(decoded.height == 400)
        }
    }

    @Test func downscalesToMax1600Wide() async throws {
        let output = try await Self.serving(try Self.png(width: 3200, height: 1000)).importImage(from: Self.imageURL)
        let decoded = try Self.decode(output)
        #expect(decoded.width == 1600)
        #expect(decoded.height == 500)
    }

    @Test func doesNotUpscaleSmallerImages() async throws {
        let output = try await Self.serving(try Self.png(width: 800, height: 500)).importImage(from: Self.imageURL)
        let decoded = try Self.decode(output)
        #expect(decoded.width == 800)
        #expect(decoded.height == 500)
    }

    @Test func appliesEXIFOrientation() async throws {
        let input = try #require(Self.makeImageData(width: 600, height: 300, type: .jpeg, orientation: 6))
        let output = try await Self.serving(input).importImage(from: Self.imageURL)
        let decoded = try Self.decode(output)
        #expect(decoded.width == 300)
        #expect(decoded.height == 600)
    }

    @Test func flattensTransparencyOntoWhite() async throws {
        guard let context = CGContext(
            data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { Issue.record("no context"); return }
        context.clear(CGRect(x: 0, y: 0, width: 400, height: 300))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let output = try await Self.serving(data as Data).importImage(from: Self.imageURL)
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixel = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        pixel.draw(decoded, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = try #require(pixel.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[0] > 245 && bytes[1] > 245 && bytes[2] > 245)
    }

    // MARK: - URL validation

    @Test func rejectsNonHTTPSchemes() async throws {
        let requests = StubLockedBox<[URLRequest]>([])
        let importer = Self.importer(requests: requests) { request in
            (StubURLProtocol.response(for: request, status: 200), try Self.png(width: 800, height: 500))
        }
        for text in ["file:///etc/hosts", "ftp://example.com/banner.png", "data:image/png;base64,AAAA"] {
            let url = try #require(URL(string: text))
            #expect(await Self.importError { try await importer.importImage(from: url) } == .unsupportedScheme, "\(text)")
        }
        #expect(requests.value.isEmpty)
    }

    @Test func rejectsMalformedURL() async throws {
        let requests = StubLockedBox<[URLRequest]>([])
        let importer = Self.importer(requests: requests) { request in
            (StubURLProtocol.response(for: request, status: 200), try Self.png(width: 800, height: 500))
        }
        // macOS 15 percent-encodes this into a scheme-less relative URL instead of returning nil.
        for text in ["not a url", "http://", "https:///banner.png"] {
            guard let url = URL(string: text) else { continue }
            #expect(await Self.importError { try await importer.importImage(from: url) } == .invalidURL, "\(text)")
        }
        #expect(requests.value.isEmpty)
    }

    // MARK: - Content validation

    @Test func rejectsHTMLBody() async {
        let html = Data("<!doctype html><html><body><img src=\"banner.png\"></body></html>".utf8)
        let importer = Self.serving(html, headers: ["Content-Type": "text/html"])
        #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .notAnImage)
    }

    @Test func rejectsSVGAndPDFBytes() async {
        for body in [Self.svgData, Self.pdfData()] {
            let importer = Self.serving(body, headers: ["Content-Type": "image/png"])
            #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .notAnImage)
        }
    }

    @Test func ignoresLyingContentType() async throws {
        let importer = Self.serving(try Self.png(width: 800, height: 500), headers: ["Content-Type": "text/html"])
        let output = try await importer.importImage(from: Self.imageURL)
        #expect(try Self.decode(output).type == .jpeg)
    }

    @Test func rejectsTooSmall() async throws {
        for (width, height) in [(299, 400), (1, 1)] {
            let importer = Self.serving(try Self.png(width: width, height: height))
            #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .tooSmall)
        }
        let atLimit = try await Self.serving(try Self.png(width: 300, height: 200)).importImage(from: Self.imageURL)
        #expect(try Self.decode(atLimit).width == 300)
    }

    // MARK: - Size limit

    @Test func rejectsOversizeByContentLength() async throws {
        // The body is a small valid image: only the header can trigger the rejection.
        let importer = Self.serving(
            try Self.png(width: 800, height: 500),
            headers: ["Content-Type": "image/png", "Content-Length": "\(10 * 1024 * 1024 + 1)"]
        )
        #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .tooLarge)
    }

    @Test func rejectsOversizeByStreamedBytesWhenHeaderMissingOrLying() async throws {
        var body = try Self.png(width: 800, height: 500)
        body.append(Data(count: BannerImageImporter.maxBytes + 1 - body.count))
        #expect(body.count == BannerImageImporter.maxBytes + 1)

        for headers in [["Content-Type": "image/png"], ["Content-Type": "image/png", "Content-Length": "1000"]] {
            let importer = Self.serving(body, headers: headers)
            #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .tooLarge, "\(headers)")
        }
    }

    @Test func acceptsBodyOfExactlyMaxBytes() async throws {
        var body = try Self.png(width: 800, height: 500)
        body.append(Data(count: BannerImageImporter.maxBytes - body.count))
        let output = try await Self.serving(body).importImage(from: Self.imageURL)
        #expect(try Self.decode(output).width == 800)
    }

    // MARK: - Network failures

    @Test func mapsNon2xxAndConnectionFailureToUnreachable() async throws {
        let image = try Self.png(width: 800, height: 500)
        for status in [404, 500] {
            let importer = Self.serving(image, status: status)
            #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .unreachable, "\(status)")
        }
        let failing = Self.importer { _ in throw URLError(.cannotFindHost) }
        #expect(await Self.importError { try await failing.importImage(from: Self.imageURL) } == .unreachable)
    }

    @Test func mapsTimeout() async {
        let importer = Self.importer { _ in throw URLError(.timedOut) }
        #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .timedOut)
    }

    @Test func overallDeadlineTimesOutSlowServer() async throws {
        let image = try Self.png(width: 800, height: 500)
        let importer = Self.importer(overallTimeout: 0.2) { request in
            Thread.sleep(forTimeInterval: 1.5)
            return (StubURLProtocol.response(for: request, status: 200), image)
        }
        let start = Date()
        #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .timedOut)
        #expect(Date().timeIntervalSince(start) < 1.4)
    }

    @Test func defaultsMatchSpec() {
        #expect(BannerImageImporter.maxBytes == 10 * 1024 * 1024)
        #expect(BannerImageImporter.maxPixelWidth == 1600)
        #expect(BannerImageImporter.minPixelWidth == 300)
        #expect(BannerImageImporter.defaultOverallTimeout == 10)
    }

    @Test func requestIdentifiesClientAndAsksForImages() async throws {
        let requests = StubLockedBox<[URLRequest]>([])
        let image = try Self.png(width: 800, height: 500)
        let importer = Self.importer(requests: requests) { request in
            (StubURLProtocol.response(for: request, status: 200), image)
        }
        _ = try await importer.importImage(from: Self.imageURL)
        let request = try #require(requests.value.first)
        #expect(request.value(forHTTPHeaderField: "Accept") == "image/*")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == BookServiceHTTP.userAgent)
    }

    @Test func rejectsRedirectToNonHTTP() async throws {
        for location in ["file:///etc/hosts", "ftp://example.com/banner.png"] {
            let requests = StubLockedBox<[URLRequest]>([])
            let image = try Self.png(width: 800, height: 500)
            let importer = Self.importer(requests: requests) { request in
                if request.url?.host == "images.example.com" {
                    return (StubURLProtocol.response(for: request, status: 302, headers: ["Location": location]), Data())
                }
                return (StubURLProtocol.response(for: request, status: 200), image)
            }
            #expect(await Self.importError { try await importer.importImage(from: Self.imageURL) } == .unsupportedScheme, "\(location)")
            #expect(requests.value.map(\.url?.scheme) == ["https"], "\(location)")
        }
    }

    @Test func followsRedirectToHTTPS() async throws {
        let requests = StubLockedBox<[URLRequest]>([])
        let image = try Self.png(width: 800, height: 500)
        let importer = Self.importer(requests: requests) { request in
            if request.url?.host == "images.example.com" {
                return (StubURLProtocol.response(for: request, status: 302, headers: ["Location": "https://cdn.example.com/b.png"]), Data())
            }
            return (StubURLProtocol.response(for: request, status: 200), image)
        }
        let output = try await importer.importImage(from: Self.imageURL)
        #expect(try Self.decode(output).width == 800)
        #expect(requests.value.map(\.url?.host) == ["images.example.com", "cdn.example.com"])
    }

    // MARK: - Local files

    @Test func importsLocalFile() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("banner.png")
        try Self.png(width: 3200, height: 1000).write(to: file)

        let decoded = try Self.decode(try BannerImageImporter().importImage(fromFile: file))
        #expect(decoded.type == .jpeg)
        #expect(decoded.width == 1600)
    }

    @Test func localFileOver10MBRejectedBeforeDecoding() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A valid image padded past the limit: it would decode if the size were not checked first.
        var body = try Self.png(width: 800, height: 500)
        body.append(Data(count: BannerImageImporter.maxBytes + 1 - body.count))
        let file = directory.appendingPathComponent("huge.png")
        try body.write(to: file)

        #expect(throws: BannerImportError.tooLarge) {
            try BannerImageImporter().importImage(fromFile: file)
        }
    }

    @Test func localNonImageFileRejected() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = directory.appendingPathComponent("notes.png")
        try Data("just some text".utf8).write(to: text)
        let pdf = directory.appendingPathComponent("doc.pdf")
        try Self.pdfData().write(to: pdf)

        for file in [text, pdf, directory.appendingPathComponent("missing.png")] {
            #expect(throws: BannerImportError.notAnImage, "\(file.lastPathComponent)") {
                try BannerImageImporter().importImage(fromFile: file)
            }
        }
    }

    @Test func localSmallImageRejected() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tiny.png")
        try Self.png(width: 120, height: 80).write(to: file)
        #expect(throws: BannerImportError.tooSmall) {
            try BannerImageImporter().importImage(fromFile: file)
        }
    }

    // MARK: - Decoded pixel cap

    /// 8-bit grayscale solid image: 64 MB in memory but a few KB as PNG.
    private static func grayPNG(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func hugeDecodedImageSmallOnDiskIsRejected() throws {
        let data = try Self.grayPNG(width: 8000, height: 8000) // 64 MP > 50 MP cap
        #expect(data.count < BannerImageImporter.maxBytes)
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("huge.png")
        try data.write(to: file)
        #expect(throws: BannerImportError.tooLarge) {
            try BannerImageImporter().importImage(fromFile: file)
        }
    }

    @Test func largeButUnderCapImagePasses() throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("big.png")
        try Self.png(width: 4000, height: 2000).write(to: file)
        let output = try BannerImageImporter().importImage(fromFile: file)
        #expect(try Self.decode(output).width == 1600)
    }

    // MARK: - Messages

    @Test func userMessagesMatchSpec() {
        let scheme = "Enter a web address starting with http:// or https://."
        #expect(BannerImportError.invalidURL.userMessage == scheme)
        #expect(BannerImportError.unsupportedScheme.userMessage == scheme)
        #expect(BannerImportError.unreachable.userMessage == "Couldn't download that image. Check the address and your connection.")
        #expect(BannerImportError.timedOut.userMessage == "The server took too long to respond.")
        #expect(BannerImportError.notAnImage.userMessage == "That doesn't look like an image (PNG, JPEG or HEIC).")
        #expect(BannerImportError.tooLarge.userMessage == "That image is too large (over 10 MB or 50 megapixels).")
        #expect(BannerImportError.tooSmall.userMessage == "That image is too small to use as a banner (at least 300 px wide).")
    }
}
