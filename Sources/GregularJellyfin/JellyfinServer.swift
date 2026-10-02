import Foundation
import GregularCore

/// A Jellyfin server before sign-in. Checks the address and gets a token.
///
/// Make one per sign-in attempt, with a new random device ID
/// (`ClientIdentity.forSignIn`): the ID goes with the sign-in into
/// `Credentials`, so no two servers ever see the same one.
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

    /// A successful sign-in.
    public struct SignIn: Sendable, Equatable {
        public let credentials: Credentials
        /// The account can change the whole server. Its token is kept on the
        /// device and sent with every video request, so a separate account
        /// without admin rights is safer for a TV.
        public let isAdministrator: Bool
    }

    public struct QuickConnectRequest: Decodable, Sendable, Equatable {
        /// The short code to show the user.
        public let code: String
        let secret: String
    }

    public let url: URL
    public let identity: ClientIdentity
    private let api: JellyfinAPI

    public init(url: URL, identity: ClientIdentity, transport: any HTTPTransport) {
        self.url = url
        self.identity = identity
        api = JellyfinAPI(server: url, identity: identity, token: nil, transport: transport)
    }

    /// Confirms there's a Jellyfin server at this address. Shown during setup
    /// and never stored. Asked anonymously: a server only probed, or only
    /// asked its name for the main page, learns nothing about this device.
    public func publicInfo() async throws -> PublicInfo {
        try await api.get("/System/Info/Public", anonymous: true)
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
    ) async throws -> SignIn {
        while try await !isQuickConnectApproved(request) {
            try await Task.sleep(for: pollInterval)
        }
        let result: AuthenticationResult = try await api.post(
            "/Users/AuthenticateWithQuickConnect", body: ["Secret": request.secret])
        return result.signIn(server: url, deviceID: identity.deviceID)
    }

    // MARK: - Password

    /// The password goes straight into this one request. It's never stored.
    public func signIn(username: String, password: String) async throws -> SignIn {
        let result: AuthenticationResult = try await api.post(
            "/Users/AuthenticateByName", body: PasswordLogin(username: username, pw: password))
        return result.signIn(server: url, deviceID: identity.deviceID)
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
    struct User: Decodable {
        struct Policy: Decodable { let isAdministrator: Bool? }
        let id: String
        let policy: Policy?
    }
    let accessToken: String
    let user: User

    func signIn(server: URL, deviceID: String) -> JellyfinServer.SignIn {
        JellyfinServer.SignIn(credentials: Credentials(serverURL: server, userID: user.id, accessToken: accessToken, deviceID: deviceID),
                              isAdministrator: user.policy?.isAdministrator ?? false)
    }
}
