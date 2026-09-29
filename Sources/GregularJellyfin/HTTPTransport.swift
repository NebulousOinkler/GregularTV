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
/// be passed on somewhere else.
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

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: RedirectGuard())
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        return (data, http)
    }
}

/// Follows a redirect only to the same server: the same scheme, host and
/// port, or from `http` to `https` on the same host. Anything else stops at
/// the redirect, which the caller sees as an error. The system already
/// drops the `Authorization` header on a redirect to another host, but it
/// sends the body again, so a sign-in's password would go with it.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url, Self.allows(from: from, to: to) else { return nil }
        return request
    }

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
