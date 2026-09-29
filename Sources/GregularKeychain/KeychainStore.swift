import Foundation
import GregularJellyfin
import Security

// The sign-in on Apple platforms (see `CredentialStore`): the Keychain's
// own secure storage, kept apart from the shared code so that code runs anywhere.

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// Keeps credentials in the Keychain, on this device only. Items are marked
/// `ThisDeviceOnly`, so they're excluded from backups and iCloud Keychain.
public struct KeychainStore: CredentialStore {
    private enum Account {
        static let credentials = "credentials"
        static let deviceID = "device-id"
    }

    private let service: String

    /// Changing the service name loses the saved sign-in and the device ID,
    /// so Jellyfin would see a new device: keep it fixed once the app ships.
    public init(service: String = "GregularTV") {
        self.service = service
    }

    public func loadCredentials() -> Credentials? {
        read(Account.credentials).flatMap { try? JSONDecoder().decode(Credentials.self, from: $0) }
    }

    public func saveCredentials(_ credentials: Credentials) throws {
        try write(JSONEncoder().encode(credentials), account: Account.credentials)
    }

    public func deleteCredentials() throws {
        try delete(account: Account.credentials)
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
