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
/// adding, using or removing one is a single write.
public struct KeychainStore: CredentialStore {
    private enum Account {
        static let signIns = "sign-ins"
        /// Before several servers: one sign-in. Read once, then moved to `signIns`.
        static let credentials = "credentials"
        static let deviceID = "device-id"
    }

    private let service: String

    /// Changing the service name loses the saved sign-in and the device ID,
    /// so Jellyfin would see a new device: keep it fixed once the app ships.
    public init(service: String = "GregularTV") {
        self.service = service
    }

    public func allCredentials() -> [Credentials] {
        if let data = read(Account.signIns) {
            return (try? JSONDecoder().decode([Credentials].self, from: data)) ?? []
        }
        // The one sign-in an earlier version kept, if any.
        return read(Account.credentials).flatMap { try? JSONDecoder().decode(Credentials.self, from: $0) }.map { [$0] } ?? []
    }

    public func saveCredentials(_ credentials: Credentials) throws {
        try save(allCredentials().using(credentials))
    }

    public func deleteCredentials(_ credentials: Credentials) throws {
        try save(allCredentials().removing(credentials))
    }

    private func save(_ list: [Credentials]) throws {
        if list.isEmpty {
            try delete(account: Account.signIns)
        } else {
            try write(JSONEncoder().encode(list), account: Account.signIns)
        }
        try delete(account: Account.credentials)   // moved into the list
    }

    public func deviceID() -> String {
        if let data = read(Account.deviceID), let id = String(data: data, encoding: .utf8) { return id }
        let id = UUID().uuidString
        try? write(Data(id.utf8), account: Account.deviceID)
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

    private func write(_ data: Data, account: String) throws {
        try delete(account: account)
        var query = baseQuery(account)
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
