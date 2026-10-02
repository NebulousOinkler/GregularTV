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

    // MARK: - Internals

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data? = nil,
                      anonymous: Bool = false) async throws -> Data {
        // Nothing, a password or token least of all, goes over plain http beyond the local network.
        guard ServerAddress.isAllowed(server) else { throw JellyfinError.insecureAddress }
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        if !anonymous {
            request.setValue(identity.authorizationHeader(token: token), forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await transport.send(request)
        // Checked here too, whatever the transport: a reply from somewhere a
        // redirect shouldn't have gone, or too large, is never used.
        guard let answered = response.url, let asked = request.url,
              asked == answered || TransportRules.allowsRedirect(from: asked, to: answered)
        else { throw JellyfinError.invalidResponse }
        guard data.count <= TransportRules.largestResponse else { throw JellyfinError.responseTooLarge }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw JellyfinError.unauthorized
        case 403: throw JellyfinError.forbidden
        default: throw JellyfinError.httpStatus(response.statusCode)
        }
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        try JellyfinJSON.decoder().decode(Response.self, from: data)
    }
}
