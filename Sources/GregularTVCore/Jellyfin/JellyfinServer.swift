import Foundation

/// A Jellyfin server before sign-in. Checks the address and gets a token.
///
/// Quick Connect is the main sign-in method, because typing a password with a
/// TV remote is painful:
/// 1. `startQuickConnect()` gets a short code to show on screen.
/// 2. The user approves the code in another Jellyfin app (phone or web).
/// 3. `waitForQuickConnect(_:)` returns credentials once they approve.
public struct JellyfinServer: Sendable {
    public struct PublicInfo: Decodable, Sendable, Equatable {
        public let serverName: String
        public let version: String
    }

    public struct QuickConnectRequest: Decodable, Sendable, Equatable {
        /// The short code to show the user.
        public let code: String
        let secret: String
    }

    public let url: URL
    private let api: JellyfinAPI

    public init(url: URL, identity: ClientIdentity, transport: any HTTPTransport = URLSessionTransport.shared) {
        self.url = url
        api = JellyfinAPI(server: url, identity: identity, token: nil, transport: transport)
    }

    /// Confirms there's a Jellyfin server at this address. Shown during setup
    /// and never stored.
    public func publicInfo() async throws -> PublicInfo {
        try await api.get("/System/Info/Public")
    }

    // MARK: - Quick Connect

    public func startQuickConnect() async throws -> QuickConnectRequest {
        let enabled: Bool = try await api.get("/QuickConnect/Enabled")
        guard enabled else { throw JellyfinError.quickConnectDisabled }
        return try await api.post("/QuickConnect/Initiate", body: [String: String]())
    }

    /// True once the user has approved the code.
    public func isQuickConnectApproved(_ request: QuickConnectRequest) async throws -> Bool {
        let state: QuickConnectState = try await api.get(
            "/QuickConnect/Connect", query: [URLQueryItem(name: "secret", value: request.secret)])
        return state.authenticated
    }

    /// Polls until the user approves the code, then signs in. Cancel the
    /// calling task to stop waiting.
    public func waitForQuickConnect(
        _ request: QuickConnectRequest, pollInterval: Duration = .seconds(3)
    ) async throws -> Credentials {
        while try await !isQuickConnectApproved(request) {
            try await Task.sleep(for: pollInterval)
        }
        let result: AuthenticationResult = try await api.post(
            "/Users/AuthenticateWithQuickConnect", body: ["Secret": request.secret])
        return result.credentials(server: url)
    }

    // MARK: - Password

    /// The password goes straight into this one request. It's never stored.
    public func signIn(username: String, password: String) async throws -> Credentials {
        let result: AuthenticationResult = try await api.post(
            "/Users/AuthenticateByName", body: PasswordLogin(username: username, pw: password))
        return result.credentials(server: url)
    }
}

// MARK: - DTOs

private struct QuickConnectState: Decodable {
    let authenticated: Bool
}

private struct PasswordLogin: Encodable {
    let username: String
    let pw: String
}

private struct AuthenticationResult: Decodable {
    struct User: Decodable { let id: String }
    let accessToken: String
    let user: User

    func credentials(server: URL) -> Credentials {
        Credentials(serverURL: server, userID: user.id, accessToken: accessToken)
    }
}
