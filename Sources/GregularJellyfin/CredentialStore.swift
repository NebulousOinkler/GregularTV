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

/// Where a platform keeps the sign-in between launches. Each platform brings
/// its own (on Apple's, `KeychainStore` in `GregularKeychain`), and must:
/// - keep it on this device only: never in a backup or synced storage;
/// - keep it where other apps can't read it (the platform's secure storage,
///   not plain files or preferences);
/// - hold nothing but `Credentials` and the device ID (never the password);
/// - keep the device ID across sign-outs (`deleteCredentials()`).
/// `CredentialStoreTests` shows the checks every store must pass.
public protocol CredentialStore: Sendable {
    func loadCredentials() -> Credentials?
    func saveCredentials(_ credentials: Credentials) throws
    func deleteCredentials() throws
    /// A random ID for this install, created on first use. Jellyfin requires
    /// one. It isn't cleared on sign-out, so signing back in doesn't add
    /// another entry to the server's device list.
    func deviceID() -> String
}

/// For tests and SwiftUI previews. Nothing is written anywhere.
public final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var credentials: Credentials?
    private let id = UUID().uuidString

    public init(credentials: Credentials? = nil) {
        self.credentials = credentials
    }

    public func loadCredentials() -> Credentials? { lock.withLock { credentials } }
    public func saveCredentials(_ credentials: Credentials) throws { lock.withLock { self.credentials = credentials } }
    public func deleteCredentials() throws { lock.withLock { credentials = nil } }
    public func deviceID() -> String { id }
}
