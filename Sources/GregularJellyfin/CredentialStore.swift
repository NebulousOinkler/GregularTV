import Foundation
import GregularCore

/// What we keep so we can reconnect after a relaunch, one per sign-in.
/// Never the password (PLAN.md §3).
public struct Credentials: Codable, Sendable, Equatable {
    public let serverURL: URL
    /// Needed for Jellyfin's per-user item and playback queries.
    public let userID: String
    public let accessToken: String
    /// The random device ID this sign-in was made with, which its token goes
    /// with. Each sign-in has its own (`ClientIdentity.forSignIn`), so two
    /// servers can't tell they're talking to the same device. Empty for one
    /// saved before they had their own: its store fills it in.
    public let deviceID: String

    public init(serverURL: URL, userID: String, accessToken: String, deviceID: String) {
        self.serverURL = serverURL
        self.userID = userID
        self.accessToken = accessToken
        self.deviceID = deviceID
    }

    /// One saved before sign-ins had their own device IDs reads with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decode(URL.self, forKey: .serverURL)
        userID = try container.decode(String.self, forKey: .userID)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
    }

    /// The same sign-in with `deviceID` in place of none.
    public func withDeviceID(_ deviceID: String) -> Credentials {
        Credentials(serverURL: serverURL, userID: userID, accessToken: accessToken, deviceID: deviceID)
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
/// - hold nothing but `Credentials` (never the password);
/// - forget everything with `deleteAll()`, which the app calls on its first
///   launch after installing, since secure storage can outlive the app (the
///   Keychain does).
/// `CredentialStoreTests` shows the checks every store must pass.
public protocol CredentialStore: Sendable {
    /// Every sign-in, the most recently used first.
    func allCredentials() -> [Credentials]
    /// Adds a sign-in, or replaces the one for the same server and user, and
    /// makes it the most recently used.
    func saveCredentials(_ credentials: Credentials) throws
    /// Forgets one sign-in; the others stay.
    func deleteCredentials(_ credentials: Credentials) throws
    /// Forgets every sign-in, and anything else the store keeps.
    func deleteAll() throws
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

/// Sign-ins held in memory only, for tests: nothing is written anywhere.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: [Credentials]

    public init(credentials: Credentials? = nil) {
        self.credentials = credentials.map { [$0] } ?? []
    }

    public func allCredentials() -> [Credentials] { lock.withLock { credentials } }
    public func saveCredentials(_ credentials: Credentials) throws { lock.withLock { self.credentials = self.credentials.using(credentials) } }
    public func deleteCredentials(_ credentials: Credentials) throws { lock.withLock { self.credentials = self.credentials.removing(credentials) } }
    public func deleteAll() throws { lock.withLock { credentials = [] } }
}
