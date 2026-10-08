import Foundation
import GregularCore

/// Sends one HTTP request. Each platform brings one (`URLSessionTransport`
/// on Apple's, `FetchTransport` in a browser); tests replace it with a fake
/// server.
///
/// **A transport must follow `TransportRules`:** follow a redirect only when
/// `allowsRedirect(from:to:)` says so, stop a reply as it arrives once it's
/// larger than the request's `largestResponse`, and store nothing (no disk cache, cookies
/// or saved logins). `TransportConformanceTests` checks all three; add a new
/// transport there. `JellyfinAPI` checks the first two again on every reply,
/// so a transport that gets them wrong still can't pass a reply on.
public protocol HTTPTransport: Sendable {
    func send(_ request: ServerRequest) async throws -> ServerReply
}

/// One request to a server. The app's own type rather than URLSession's
/// `URLRequest`, which not every platform has (a browser doesn't).
public struct ServerRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    /// The most the reply may be (bytes): `TransportRules.largestResponse`,
    /// unless it's a whole file (`JellyfinClient.download(_:mostBytes:)`).
    public var largestResponse: Int

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil,
                largestResponse: Int = TransportRules.largestResponse) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.largestResponse = largestResponse
    }

    /// The value of header `name`, whatever its case.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A server's reply to a `ServerRequest`.
public struct ServerReply: Sendable {
    /// Where the reply came from, after any redirect the transport followed.
    public let url: URL
    public let status: Int
    public let body: Data

    public init(url: URL, status: Int, body: Data) {
        self.url = url
        self.status = status
        self.body = body
    }
}

/// What every transport must do, whatever the platform (see `HTTPTransport`).
public enum TransportRules {
    /// The most one reply may be (bytes), unless a request says otherwise.
    /// Far more than any real one (a page of 500 programmes is about 300 KB,
    /// the speed test 3 MB), so only a server sending far too much hits it.
    public static let largestResponse = 16 * 1024 * 1024

    /// Whether a redirect from `from` to `to` may be followed: only to the
    /// same server, with the same scheme, host and port, or from `http` to
    /// `https` on the same host, at the standard port or Jellyfin's
    /// (`upgradePorts`). Anything else stops at the redirect, which
    /// the caller sees as an error. (URLSession drops `Authorization` on a
    /// redirect to another host by itself, but it sends the body again, so a
    /// sign-in's password would go with it; other HTTP stacks may not even
    /// drop the header.)
    public static func allowsRedirect(from: URL, to: URL) -> Bool {
        guard let host = from.host()?.lowercased(), host == to.host()?.lowercased(),
              let fromScheme = from.scheme?.lowercased(), let toScheme = to.scheme?.lowercased() else { return false }
        if fromScheme == "http" && toScheme == "https" { return port(of: to).map(upgradePorts.contains) ?? false }
        return fromScheme == toScheme && port(of: from) == port(of: to)
    }

    /// The ports an upgrade from http to https may go to: the standard one,
    /// and Jellyfin's own (its "Require HTTPS" sends plain http there).
    static let upgradePorts: Set<Int> = [443, 8920]

    private static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}

#if canImport(Darwin)
/// The app's own network path on Apple platforms: every request it makes. (Video is fetched by
/// the platform's player, from stream URLs that point back at the server.)
///
/// It uses an ephemeral session with no URL cache and no cookies, so no
/// responses from the server (library listings, artwork, anything else) are
/// ever written to disk. It follows `TransportRules` through `BoundedLoad`.
public struct URLSessionTransport: HTTPTransport {
    public static let shared = URLSessionTransport()

    private let session: URLSession

    public init() {
        self.init(configuration: Self.makeConfiguration())
    }

    /// Tests pass a configuration with a stand-in server (`protocolClasses`).
    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        return config
    }

    public func send(_ request: ServerRequest) async throws -> ServerReply {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.allHTTPHeaderFields = request.headers
        urlRequest.httpBody = request.body
        let (data, response) = try await send(urlRequest, largest: request.largestResponse)
        return ServerReply(url: response.url ?? request.url, status: response.statusCode, body: data)
    }

    private func send(_ request: URLRequest, largest: Int) async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        let load = BoundedLoad(limit: largest)
        task.delegate = load
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                load.start(task, reportingTo: continuation)
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// One request's reply, gathered as it arrives and stopped as soon as it's
/// larger than `limit`, so a server can't fill the app's memory before the
/// size is known. It follows redirects only as `TransportRules` allows.
final class BoundedLoad: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func start(_ task: URLSessionDataTask, reportingTo continuation: CheckedContinuation<(Data, HTTPURLResponse), any Error>) {
        lock.withLock { self.continuation = continuation }
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url, TransportRules.allowsRedirect(from: from, to: to) else { return nil }
        return request
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        // A size the server announces up front is turned down before anything arrives.
        guard response.expectedContentLength <= Int64(limit) else {
            finish(.failure(JellyfinError.responseTooLarge))
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let tooLarge = lock.withLock {
            data.append(chunk)
            return data.count > limit
        }
        if tooLarge {
            finish(.failure(JellyfinError.responseTooLarge))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(.failure(error))
        } else if let response = task.response as? HTTPURLResponse {
            finish(.success((lock.withLock { data }, response)))
        } else {
            finish(.failure(JellyfinError.invalidResponse))
        }
    }

    /// Reports the outcome once; anything after (a cancelled task completing) is ignored.
    private func finish(_ result: Result<(Data, HTTPURLResponse), any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            if case .failure = result { data = Data() }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}
#endif
