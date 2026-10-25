import Foundation
import Testing
@testable import VoiceInk

/// Closure-backed `BannerImporting` stub.
private struct StubBannerImporter: BannerImporting {
    var remote: @Sendable (URL) async throws -> Data = { _ in Data([1]) }
    var file: @Sendable (URL) throws -> Data = { _ in Data([2]) }

    func importImage(from url: URL) async throws -> Data { try await remote(url) }
    func importImage(fromFile url: URL) throws -> Data { try file(url) }
}

/// Records the URLs passed to the stub importer.
private final class URLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    func append(_ url: URL) { lock.withLock { stored.append(url) } }
    var urls: [URL] { lock.withLock { stored } }
}

@MainActor
struct BookBannerEditorModelTests {
    private let fileURL = URL(fileURLWithPath: "/tmp/banner.png")

    @Test func useURLReturnsDataOnSuccess() async {
        let recorder = URLRecorder()
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { url in
            recorder.append(url)
            return Data([7, 7])
        }))

        let data = await model.useURL("  https://example.com/banner.jpg \n")

        #expect(data == Data([7, 7]))
        #expect(recorder.urls == [URL(string: "https://example.com/banner.jpg")!])
        #expect(model.errorMessage == nil)
        #expect(model.isWorking == false)
    }

    @Test func useURLReportsImporterError() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { _ in
            throw BannerImportError.notAnImage
        }))

        let data = await model.useURL("https://example.com/page.html")

        #expect(data == nil)
        #expect(model.errorMessage == BannerImportError.notAnImage.userMessage)
        #expect(model.isWorking == false)
    }

    @Test func unparseableURLMapsToInvalidURL() async {
        let recorder = URLRecorder()
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { url in
            recorder.append(url)
            return Data([1])
        }))

        let data = await model.useURL("   ")

        #expect(data == nil)
        #expect(model.errorMessage == BannerImportError.invalidURL.userMessage)
        #expect(recorder.urls.isEmpty)
    }

    @Test func unexpectedErrorMapsToUnreachable() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { _ in
            throw URLError(.badServerResponse)
        }))

        let data = await model.useURL("https://example.com/a.jpg")

        #expect(data == nil)
        #expect(model.errorMessage == BannerImportError.unreachable.userMessage)
    }

    @Test func useFileReturnsDataOnSuccess() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(file: { _ in Data([9]) }))

        let data = await model.useFile(fileURL)

        #expect(data == Data([9]))
        #expect(model.errorMessage == nil)
        #expect(model.isWorking == false)
    }

    @Test func useFileReportsImporterError() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(file: { _ in
            throw BannerImportError.notAnImage
        }))

        let data = await model.useFile(fileURL)

        #expect(data == nil)
        #expect(model.errorMessage == BannerImportError.notAnImage.userMessage)
        #expect(model.isWorking == false)
    }

    @Test func errorClearsOnClearError() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { _ in
            throw BannerImportError.tooSmall
        }))
        _ = await model.useURL("https://example.com/a.jpg")
        #expect(model.errorMessage != nil)

        model.clearError()

        #expect(model.errorMessage == nil)
    }

    @Test func errorClearsOnNewInput() async {
        let model = BookBannerEditorModel(importer: StubBannerImporter(
            remote: { url in
                if url.lastPathComponent == "bad.jpg" { throw BannerImportError.tooLarge }
                return Data([3])
            },
            file: { _ in Data([4]) }
        ))

        _ = await model.useURL("https://example.com/bad.jpg")
        #expect(model.errorMessage == BannerImportError.tooLarge.userMessage)
        let data = await model.useURL("https://example.com/good.jpg")
        #expect(data == Data([3]))
        #expect(model.errorMessage == nil)

        _ = await model.useURL("https://example.com/bad.jpg")
        #expect(model.errorMessage != nil)
        _ = await model.useFile(fileURL)
        #expect(model.errorMessage == nil)
    }

    @Test func cancelStopsInFlightUseURL() async throws {
        let model = BookBannerEditorModel(importer: StubBannerImporter(remote: { _ in
            try await Task.sleep(for: .seconds(30))
            return Data([1])
        }))

        let pending = Task { await model.useURL("https://example.com/slow.jpg") }
        while !model.isWorking {
            await Task.yield()
        }

        model.cancel()
        #expect(model.isWorking == false)

        let data = await pending.value
        #expect(data == nil)
        #expect(model.isWorking == false)
        #expect(model.errorMessage == nil)
    }
}
