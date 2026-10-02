import Foundation
import GregularCore
import GregularJellyfin
import Observation

/// Sign-in steps: enter the server address, then use Quick Connect or a
/// password. Nothing here is stored. `AppModel` saves the credentials after
/// a successful sign-in. Each server tried gets a new random device ID
/// (`ClientIdentity.forSignIn`), so servers can't tell it's the same device.
@MainActor @Observable
public final class LoginModel {
    public enum Step {
        case enterAddress
        case connecting
        case signIn(server: JellyfinServer, serverName: String)
        /// Signed in as an account that can change the whole server: shows
        /// `administratorWarning`, then `continueAsAdministrator()` or
        /// `useAnotherAccount()`.
        case administrator(serverName: String)
    }

    /// The sign-in screen's words that depend on the server: what to type,
    /// with an example at the server's usual port, and where Quick Connect is.
    public static let addressPrompt = "Enter your \(AppModel.serverName) server address"
    public static let addressExample = "e.g. 192.168.1.10:8096"
    public static let quickConnectHint =
        "In another \(AppModel.serverName) app, open your profile \u{25B8} Quick Connect and enter this code."
    public static let administratorWarning =
        "This account is an administrator of the server. This TV keeps its sign-in, and sends it with every video it asks for, "
        + "so anyone who got hold of it could change the whole server. An account without admin rights is safer for a TV."
    /// Shown while signing in to a server at a plain `http` address.
    public static let unencryptedNote =
        "This connection isn't encrypted, so a password typed here crosses your home network as plain text, and so does "
        + "the sign-in it gets. Quick Connect keeps your password off the network; an https address encrypts everything."

    public var address = ""
    public var username = ""
    public var password = ""
    public private(set) var step: Step = .enterAddress
    public private(set) var quickConnectCode: String?
    public private(set) var quickConnectNote: String?
    public private(set) var isSigningIn = false
    public private(set) var errorMessage: String?

    /// `unencryptedNote` while signing in over plain `http`, else nil.
    public var connectionNote: String? {
        guard case .signIn(let server, _) = step, server.url.scheme?.lowercased() == "http" else { return nil }
        return Self.unencryptedNote
    }

    private let access: ServerAccess
    private let onSignedIn: (Credentials) async -> Void
    private var quickConnectTask: Task<Void, Never>?
    /// An administrator's sign-in, waiting on the warning.
    private var pending: (signIn: JellyfinServer.SignIn, server: JellyfinServer, serverName: String)?

    /// Made by `AppModel.makeLoginModel()`, which keeps the Jellyfin types to itself.
    init(access: ServerAccess, onSignedIn: @escaping (Credentials) async -> Void) {
        self.access = access
        self.onSignedIn = onSignedIn
    }

    isolated deinit {
        quickConnectTask?.cancel()
    }

    public func connect() async {
        let candidates = ServerAddress.candidates(for: address)
        guard !candidates.isEmpty else {
            errorMessage = ServerAddress.normalize(address) == nil
                ? "That doesn't look like a server address. Try something like 192.168.1.10:8096."
                : JellyfinError.insecureAddress.errorDescription
            return
        }
        errorMessage = nil
        step = .connecting
        var lastError: (any Error)?
        for url in candidates {
            let server = access.newServer(at: url)
            do {
                let info = try await server.publicInfo()
                step = .signIn(server: server, serverName: info.serverName)
                startQuickConnect(server, serverName: info.serverName)
                return
            } catch {
                lastError = error
            }
        }
        step = .enterAddress
        errorMessage = "Couldn't reach a \(AppModel.serverName) server at \(address). \(FriendlyError.message(for: lastError))"
    }

    public func signInWithPassword() async {
        guard case .signIn(let server, let serverName) = step else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let signIn = try await server.signIn(username: username, password: password)
            password = ""
            quickConnectTask?.cancel()
            await finish(signIn, server: server, serverName: serverName)
        } catch JellyfinError.unauthorized {
            errorMessage = "Wrong username or password."
        } catch {
            errorMessage = FriendlyError.message(for: error)
        }
    }

    /// After the administrator warning: signs in anyway.
    public func continueAsAdministrator() async {
        guard let pending else { return }
        self.pending = nil
        await onSignedIn(pending.signIn.credentials)
    }

    /// After the administrator warning: cancels that sign-in on the server,
    /// and goes back to sign in with another account.
    public func useAnotherAccount() async {
        guard let pending else { return }
        self.pending = nil
        await Self.revoke(pending.signIn, through: access)
        step = .signIn(server: pending.server, serverName: pending.serverName)
        startQuickConnect(pending.server, serverName: pending.serverName)
    }

    /// Back to the address, forgetting the password: it's never sent to another server.
    public func changeServer() {
        stop()
        step = .enterAddress
    }

    /// Stops signing in: no more waiting for Quick Connect, so a code
    /// approved later signs nothing in; the password is forgotten; and an
    /// administrator's sign-in still waiting on its warning is cancelled on
    /// the server. Call it when the sign-in screen closes.
    public func stop() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
        password = ""
        if let pending {
            self.pending = nil
            Task { await Self.revoke(pending.signIn, through: access) }
        }
    }

    /// Signs in, or first warns if the account is an administrator.
    private func finish(_ signIn: JellyfinServer.SignIn, server: JellyfinServer, serverName: String) async {
        guard signIn.isAdministrator else { return await onSignedIn(signIn.credentials) }
        pending = (signIn, server, serverName)
        step = .administrator(serverName: serverName)
    }

    private static func revoke(_ signIn: JellyfinServer.SignIn, through access: ServerAccess) async {
        await access.client(for: signIn.credentials).revoke()
    }

    /// Shows a code and waits for the user to approve it in another Jellyfin app.
    private func startQuickConnect(_ server: JellyfinServer, serverName: String) {
        quickConnectTask?.cancel()
        quickConnectCode = nil
        quickConnectNote = nil
        quickConnectTask = Task { [weak self] in
            do {
                let request = try await server.startQuickConnect()
                self?.quickConnectCode = request.code
                let signIn = try await server.waitForQuickConnect(request)
                try Task.checkCancellation()
                await self?.finish(signIn, server: server, serverName: serverName)
            } catch is CancellationError {
            } catch {
                self?.quickConnectNote = FriendlyError.message(for: error)
            }
        }
    }
}
