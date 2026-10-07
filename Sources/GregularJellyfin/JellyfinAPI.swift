import Foundation
import GregularCore

public enum JellyfinError: Error, Equatable, Sendable {
    /// The token was rejected (HTTP 401). The user needs to sign in again.
    case unauthorized
    /// The server refused this request (HTTP 403): the account isn't allowed
    /// it. Not a sign-out: the sign-in still works for everything else.
    case forbidden
    case httpStatus(Int)
    case invalidResponse
    /// Plain http to an address outside the local network (see `ServerAddress.isAllowed(_:)`).
    case insecureAddress
    /// The server sent far more than any reply should be (see `TransportRules.largestResponse`).
    case responseTooLarge
    case quickConnectDisabled
    /// Jellyfin returned no media source this device can play.
    case noPlayableSource(itemID: String)
}

extension JellyfinError {
    /// Throws what an HTTP `status` means, unless it's a success: every
    /// reply from a server is read this way, whoever fetched it.
    public static func check(status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw JellyfinError.unauthorized
        case 403: throw JellyfinError.forbidden
        default: throw JellyfinError.httpStatus(status)
        }
    }
}

extension JellyfinError: MediaServiceFailure {
    public var isSessionExpired: Bool { self == .unauthorized }

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your Jellyfin sign-in has expired or was revoked. Please sign in again."
        case .forbidden: "Your Jellyfin account isn't allowed to do this. It may be disabled, or limited by its parental controls."
        case .httpStatus(let code): "The Jellyfin server returned an error (HTTP \(code))."
        case .invalidResponse: "The server didn't respond like a Jellyfin server."
        case .insecureAddress: "Plain http only works on your home network. For an address on the internet, use https."
        case .responseTooLarge: "The server sent far more than expected, so the app stopped it."
        case .quickConnectDisabled: "Quick Connect is turned off on this server. Sign in with a password instead."
        case .noPlayableSource: "Jellyfin couldn't provide a playable stream for this programme."
        }
    }
}

/// Builds and sends requests to one Jellyfin server. `JellyfinServer` and
/// `JellyfinClient` both use it, so every request gets the same headers
/// and error handling.
struct JellyfinAPI: Sendable {
    let server: URL
    let identity: ClientIdentity
    let token: String?
    let transport: any HTTPTransport

    /// - Parameter anonymous: send no `Authorization` header at all, so the
    ///   server learns nothing about this device (for its public endpoints).
    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = [], anonymous: Bool = false) async throws -> Response {
        try decode(await send("GET", path, query: query, anonymous: anonymous))
    }

    func post<Response: Decodable>(
        _ path: String, query: [URLQueryItem] = [], body: some Encodable
    ) async throws -> Response {
        try decode(await send("POST", path, query: query, body: JellyfinJSON.encoder().encode(body)))
    }

    /// For endpoints that return no content.
    func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (some Encodable)? = nil as String?) async throws {
        _ = try await send(method, path, query: query, body: body.map { try JellyfinJSON.encoder().encode($0) })
    }

    /// `server` + `path`, keeping any reverse-proxy sub-path on the server URL.
    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: server, resolvingAgainstBaseURL: false)!
        components.path += path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    /// A whole file from this server, such as a song's (`url` must be one
    /// of its own, as `url(_:query:)` makes), of at most `largest` bytes.
    func file(_ url: URL, largest: Int) async throws -> Data {
        guard isOnThisServer(url) else { throw JellyfinError.invalidResponse }
        return try await send(ServerRequest(url: url, largestResponse: largest), anonymous: false)
    }

    /// Same scheme, host and port, under any reverse-proxy sub-path.
    private func isOnThisServer(_ url: URL) -> Bool {
        url.scheme?.lowercased() == server.scheme?.lowercased() && url.host()?.lowercased() == server.host()?.lowercased()
            && url.port == server.port && url.path().hasPrefix(server.path().hasSuffix("/") ? server.path() : server.path() + "/")
    }

    // MARK: - Internals

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data? = nil,
                      anonymous: Bool = false) async throws -> Data {
        var request = ServerRequest(method: method, url: url(path, query: query), headers: ["Accept": "application/json"], body: body)
        if body != nil {
            request.headers["Content-Type"] = "application/json"
        }
        return try await send(request, anonymous: anonymous)
    }

    private func send(_ request: ServerRequest, anonymous: Bool) async throws -> Data {
        // Nothing, a password or token least of all, goes over plain http beyond the local network.
        guard ServerAddress.isAllowed(server) else { throw JellyfinError.insecureAddress }
        var request = request
        if !anonymous {
            request.headers["Authorization"] = identity.authorizationHeader(token: token)
        }

        let reply = try await transport.send(request)
        // Checked here too, whatever the transport: a reply from somewhere a
        // redirect shouldn't have gone, or too large, is never used.
        guard reply.url == request.url || TransportRules.allowsRedirect(from: request.url, to: reply.url)
        else { throw JellyfinError.invalidResponse }
        guard reply.body.count <= request.largestResponse else { throw JellyfinError.responseTooLarge }
        try JellyfinError.check(status: reply.status)
        return reply.body
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        try JellyfinJSON.decoder().decode(Response.self, from: data)
    }
}
