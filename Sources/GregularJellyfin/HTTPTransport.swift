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
/// ever written to disk.
public struct URLSessionTransport: HTTPTransport {
    public static let shared = URLSessionTransport()

    private let session: URLSession

    public init() {
        session = URLSession(configuration: Self.makeConfiguration())
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        return (data, http)
    }
}
