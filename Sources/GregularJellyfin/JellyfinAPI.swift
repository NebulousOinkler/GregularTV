import Foundation
import GregularCore

public enum JellyfinError: Error, Equatable, Sendable {
    /// The token was rejected. The user needs to sign in again.
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    case quickConnectDisabled
    /// Jellyfin returned no media source this device can play.
    case noPlayableSource(itemID: String)
}

extension JellyfinError: MediaServiceFailure {
    public var isSessionExpired: Bool { self == .unauthorized }

    public var errorDescription: String? {
        switch self {
        case .unauthorized: "Your Jellyfin sign-in has expired or was revoked. Please sign in again."
        case .httpStatus(let code): "The Jellyfin server returned an error (HTTP \(code))."
        case .invalidResponse: "The server didn't respond like a Jellyfin server."
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

    func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try decode(await send("GET", path, query: query))
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

    private func send(_ method: String, _ path: String, query: [URLQueryItem], body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue(identity.authorizationHeader(token: token), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300: return data
        case 401, 403: throw JellyfinError.unauthorized
        default: throw JellyfinError.httpStatus(response.statusCode)
        }
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        try JellyfinJSON.decoder().decode(Response.self, from: data)
    }
}
