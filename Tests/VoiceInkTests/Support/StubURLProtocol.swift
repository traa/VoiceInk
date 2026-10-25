import Foundation

/// Test-only `URLProtocol` that answers requests from a per-session handler.
///
/// Swift Testing runs tests in parallel, so handlers are never shared: each
/// `makeSession(handler:)` call registers its handler under a fresh UUID and tags
/// every request of that session with the UUID in `sessionHeader`.
///
/// Behaviour relied on by the dashboard service tests:
/// - A 3xx response carrying a `Location` header is delivered as a real redirect
///   (`wasRedirectedTo`), so the session (and its delegate) decides whether to follow it.
///   The redirected request keeps the session tag, so the same handler answers it.
/// - Response headers are passed through untouched. No `Content-Length` is injected,
///   so a handler can omit it or send one that lies about the body size.
/// - The body is delivered in chunks, so streaming consumers see several reads.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    static let sessionHeader = "X-Stub-URL-Protocol-Session"
    static let chunkSize = 64 * 1024

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    /// Returns an ephemeral session whose requests are answered by `handler`.
    static func makeSession(
        handler: @escaping Handler,
        configure: (URLSessionConfiguration) -> Void = { _ in }
    ) -> URLSession {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = handler }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [sessionHeader: id]
        configure(configuration)
        return URLSession(configuration: configuration)
    }

    /// Convenience for building a stub response.
    static func response(
        for request: URLRequest,
        status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.invalid")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let id = request.value(forHTTPHeaderField: sessionHeader) else { return nil }
        return lock.withLock { handlers[id] }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: sessionHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        guard let handler = Self.handler(for: request) else {
            client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let response: HTTPURLResponse
        let body: Data
        do {
            (response, body) = try handler(request)
        } catch {
            client.urlProtocol(self, didFailWithError: error)
            return
        }

        if (300..<400).contains(response.statusCode),
           let location = response.value(forHTTPHeaderField: "Location"),
           let target = URL(string: location, relativeTo: request.url)?.absoluteURL {
            var redirected = request
            redirected.url = target
            client.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            // If the session refuses the redirect, the 3xx response itself completes the task.
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
            return
        }

        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < body.count {
            let end = min(offset + Self.chunkSize, body.count)
            client.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
            offset = end
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Thread-safe box for capturing values inside stub handlers.
final class StubLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
