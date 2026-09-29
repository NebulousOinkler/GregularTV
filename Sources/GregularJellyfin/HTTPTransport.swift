import Foundation
import GregularCore

/// Sends one HTTP request. Tests replace this with a fake server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The app's only real network path.
///
/// It uses an ephemeral session with no URL cache and no cookies, so no
/// responses from the server (library listings, artwork, anything else) are
/// ever written to disk. It follows a redirect only on the same server (see
/// `RedirectGuard`), so nothing sent to the server, a password included, can
/// be passed on somewhere else, and it stops any reply larger than
/// `largestResponse` as it arrives (see `BoundedLoad`).
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

    /// The most one reply may be (bytes). Far more than any real one (a
    /// page of 500 programmes is about 300 KB, the speed test 3 MB), so only
    /// a server sending far too much hits it, and the transfer stops there.
    static let largestResponse = 16 * 1024 * 1024

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let task = session.dataTask(with: request)
        let load = BoundedLoad(limit: Self.largestResponse)
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
/// size is known. It also follows redirects only on the same server (see
/// `RedirectGuard`).
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
        guard let from = task.originalRequest?.url, let to = request.url, RedirectGuard.allows(from: from, to: to) else { return nil }
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

/// Follows a redirect only to the same server: the same scheme, host and
/// port, or from `http` to `https` on the same host. Anything else stops at
/// the redirect, which the caller sees as an error. The system already
/// drops the `Authorization` header on a redirect to another host, but it
/// sends the body again, so a sign-in's password would go with it.
enum RedirectGuard {
    static func allows(from: URL, to: URL) -> Bool {
        guard let host = from.host()?.lowercased(), host == to.host()?.lowercased(),
              let fromScheme = from.scheme?.lowercased(), let toScheme = to.scheme?.lowercased() else { return false }
        if fromScheme == "http" && toScheme == "https" { return true }
        return fromScheme == toScheme && port(of: from) == port(of: to)
    }

    private static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
    }
}
