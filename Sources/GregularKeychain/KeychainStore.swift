// Apple platforms only: other platforms bring their own CredentialStore.
#if canImport(Security)
import Foundation
import GregularJellyfin
import Security

// The sign-in on Apple platforms (see `CredentialStore`): the Keychain's
// own secure storage, kept apart from the shared code so that code runs anywhere.

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Keeps the sign-ins in the Keychain, on this device only. Items are marked
/// `ThisDeviceOnly`, so they're excluded from backups and iCloud Keychain.
/// The sign-ins are one item, a list with the most recently used first, so
/// adding, using or removing one is a single write, made in place: a failed
/// write leaves what was there.
public struct KeychainStore: CredentialStore {
    private enum Account {
        static let signIns = "sign-ins"
        /// Before several servers: one sign-in. Read once, then moved to `signIns`.
        static let credentials = "credentials"
        /// Before each sign-in had its own: one device ID for them all. The
        /// sign-ins saved then keep it (their tokens go with it), and it's
        /// deleted once they're saved with it.
        static let sharedDeviceID = "device-id"
        static let all = [signIns, credentials, sharedDeviceID]
    }

    private let service: String

    /// Changing the service name loses the saved sign-ins: keep it fixed
    /// once the app ships.
    public init(service: String = "GregularTV") {
        self.service = service
    }

    public func allCredentials() -> [Credentials] {
        let saved = if let data = read(Account.signIns) {
            Credentials.list(from: data)
        } else {
            // The one sign-in an earlier version kept, if any.
            read(Account.credentials).flatMap { try? JSONDecoder().decode(Credentials.self, from: $0) }.map { [$0] } ?? []
        }
        guard saved.contains(where: { $0.deviceID.isEmpty }) else { return saved }
        let shared = sharedDeviceID()
        return saved.map { $0.deviceID.isEmpty ? $0.withDeviceID(shared) : $0 }
    }

    public func saveCredentials(_ credentials: Credentials) throws {
        try save(allCredentials().using(credentials))
    }

    public func deleteCredentials(_ credentials: Credentials) throws {
        try save(allCredentials().removing(credentials))
    }

    public func deleteAll() throws {
        for account in Account.all { try delete(account: account) }
    }

    private func save(_ list: [Credentials]) throws {
        if list.isEmpty {
            try delete(account: Account.signIns)
        } else {
            try write(JSONEncoder().encode(list), account: Account.signIns)
        }
        // Moved into the list, each sign-in with its device ID.
        try delete(account: Account.credentials)
        try delete(account: Account.sharedDeviceID)
    }

    /// The device ID sign-ins shared before each had its own.
    private func sharedDeviceID() -> String {
        if let data = read(Account.sharedDeviceID), let id = String(data: data, encoding: .utf8) { return id }
        let id = UUID().uuidString
        try? write(Data(id.utf8), account: Account.sharedDeviceID)
        return id
    }

    // MARK: - Keychain calls

    private func baseQuery(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    private func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Replaces the item in place, or adds it if there's none.
    private func write(_ data: Data, account: String) throws {
        let values: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(baseQuery(account) as CFDictionary, values as CFDictionary)
        guard updated == errSecItemNotFound else {
            guard updated == errSecSuccess else { throw KeychainError(status: updated) }
            return
        }
        let added = SecItemAdd(baseQuery(account).merging(values) { $1 } as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
