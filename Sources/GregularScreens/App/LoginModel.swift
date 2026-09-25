import Foundation
import GregularCore
import GregularJellyfin
import Observation

/// Sign-in steps: enter the server address, then use Quick Connect or a
/// password. Nothing here is stored. `AppModel` saves the credentials after
/// a successful sign-in.
@MainActor @Observable
public final class LoginModel {
    public enum Step {
        case enterAddress
        case connecting
        case signIn(server: JellyfinServer, serverName: String)
    }

    public var address = ""
    public var username = ""
    public var password = ""
    public private(set) var step: Step = .enterAddress
    public private(set) var quickConnectCode: String?
    public private(set) var quickConnectNote: String?
    public private(set) var isSigningIn = false
    public private(set) var errorMessage: String?

    private let identity: ClientIdentity
    private let onSignedIn: (Credentials) async -> Void
    private var quickConnectTask: Task<Void, Never>?

    public init(identity: ClientIdentity, onSignedIn: @escaping (Credentials) async -> Void) {
        self.identity = identity
        self.onSignedIn = onSignedIn
    }

    public func connect() async {
        let candidates = ServerAddress.candidates(for: address)
        guard !candidates.isEmpty else {
            errorMessage = "That doesn't look like a server address. Try something like 192.168.1.10:8096."
            return
        }
        errorMessage = nil
        step = .connecting
        var lastError: (any Error)?
        for url in candidates {
            let server = JellyfinServer(url: url, identity: identity)
            do {
                let info = try await server.publicInfo()
                step = .signIn(server: server, serverName: info.serverName)
                startQuickConnect(server)
                return
            } catch {
                lastError = error
            }
        }
        step = .enterAddress
        errorMessage = "Couldn't reach a Jellyfin server at \(address). \(FriendlyError.message(for: lastError))"
    }

    public func signInWithPassword() async {
        guard case .signIn(let server, _) = step else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let credentials = try await server.signIn(username: username, password: password)
            password = ""
            quickConnectTask?.cancel()
            await onSignedIn(credentials)
        } catch JellyfinError.unauthorized {
            errorMessage = "Wrong username or password."
        } catch {
            errorMessage = FriendlyError.message(for: error)
        }
    }

    public func changeServer() {
        quickConnectTask?.cancel()
        quickConnectCode = nil
        step = .enterAddress
    }

    /// Shows a code and waits for the user to approve it in another Jellyfin app.
    private func startQuickConnect(_ server: JellyfinServer) {
        quickConnectTask?.cancel()
        quickConnectCode = nil
        quickConnectNote = nil
        quickConnectTask = Task {
            do {
                let request = try await server.startQuickConnect()
                quickConnectCode = request.code
                let credentials = try await server.waitForQuickConnect(request)
                await onSignedIn(credentials)
            } catch is CancellationError {
            } catch {
                quickConnectNote = FriendlyError.message(for: error)
            }
        }
    }
}
