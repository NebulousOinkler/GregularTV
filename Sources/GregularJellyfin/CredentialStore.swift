import Foundation
import GregularCore

/// What we keep so we can reconnect after a relaunch. This, the device ID and
/// the last channel number are **all** the app persists (PLAN.md §3).
public struct Credentials: Codable, Sendable, Equatable {
    public let serverURL: URL
    /// Needed for Jellyfin's per-user item and playback queries.
    public let userID: String
    public let accessToken: String

    public init(serverURL: URL, userID: String, accessToken: String) {
        self.serverURL = serverURL
        self.userID = userID
        self.accessToken = accessToken
    }
}

extension Credentials {
    /// Which sign-in this is: the server and the user. Signing in again to
    /// the same server as the same user replaces it.
    public var signInID: String { "\(serverURL.absoluteString)|\(userID)" }
}

/// Where a platform keeps the sign-ins between launches, one per server
/// (and user). Each platform brings its own (on Apple's, `KeychainStore` in
/// `GregularKeychain`), and must:
/// - keep them on this device only: never in a backup or synced storage;
/// - keep them where other apps can't read them (the platform's secure
///   storage, not plain files or preferences);
/// - hold nothing but `Credentials` and the device ID (never the password);
/// - keep the device ID when sign-ins are deleted.
/// `CredentialStoreTests` shows the checks every store must pass.
public protocol CredentialStore: Sendable {
    /// Every sign-in, the most recently used first.
    func allCredentials() -> [Credentials]
    /// Adds a sign-in, or replaces the one for the same server and user, and
    /// makes it the most recently used.
    func saveCredentials(_ credentials: Credentials) throws
    /// Forgets one sign-in; the others stay.
    func deleteCredentials(_ credentials: Credentials) throws
    /// A random ID for this install, created on first use. Jellyfin requires
    /// one. It isn't cleared on sign-out, so signing back in doesn't add
    /// another entry to the server's device list.
    func deviceID() -> String
}

extension CredentialStore {
    /// The most recently used sign-in.
    public func loadCredentials() -> Credentials? { allCredentials().first }
}

extension [Credentials] {
    /// `credentials` at the front, in place of any sign-in to the same server as the same user.
    public func using(_ credentials: Credentials) -> [Credentials] {
        [credentials] + filter { $0.signInID != credentials.signInID }
    }

    /// Without `credentials`' sign-in.
    public func removing(_ credentials: Credentials) -> [Credentials] {
        filter { $0.signInID != credentials.signInID }
    }
}

/// For tests and SwiftUI previews. Nothing is written anywhere.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [Credentials]
    private let id = UUID().uuidString

    public init(credentials: Credentials? = nil) {
        self.credentials = credentials.map { [$0] } ?? []
    }

    public func allCredentials() -> [Credentials] { lock.withLock { credentials } }
    public func saveCredentials(_ credentials: Credentials) throws { lock.withLock { self.credentials = self.credentials.using(credentials) } }
    public func deleteCredentials(_ credentials: Credentials) throws { lock.withLock { self.credentials = self.credentials.removing(credentials) } }
    public func deviceID() -> String { id }
}
