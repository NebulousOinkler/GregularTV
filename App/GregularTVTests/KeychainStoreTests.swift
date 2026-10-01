import Foundation
import GregularCore
import GregularJellyfin
import GregularKeychain
import Security
import Testing

/// The Keychain needs an app host, so this test lives here and not in the
/// package tests. It's the same checks as `CredentialStoreTests.checkRules`.
struct KeychainStoreTests {
    @Test func severalServersAndSigningOutOfOne() throws {
        let store = KeychainStore(service: "GregularTVTests-\(UUID().uuidString)")
        let home = Credentials(serverURL: URL(string: "http://192.168.1.5:8096")!, userID: "u", accessToken: "t1")
        let away = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t2")

        #expect(store.allCredentials().isEmpty)
        try store.saveCredentials(home)
        try store.saveCredentials(away)
        #expect(store.allCredentials() == [away, home])
        try store.saveCredentials(home)
        #expect(store.allCredentials() == [home, away], "Watching one moves it to the front")

        let deviceID = store.deviceID()
        #expect(store.deviceID() == deviceID)

        try store.deleteCredentials(home)
        #expect(store.allCredentials() == [away])
        try store.deleteCredentials(away)
        #expect(store.allCredentials().isEmpty)
        #expect(store.deviceID() == deviceID, "Device ID should survive sign-out")
    }

    /// The one sign-in an earlier version kept is still there after updating.
    @Test func anEarlierVersionsSignInCarriesOver() throws {
        let service = "GregularTVTests-\(UUID().uuidString)"
        let old = Credentials(serverURL: URL(string: "http://nas:8096")!, userID: "u", accessToken: "t")
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: "credentials",
                                      kSecValueData: try JSONEncoder().encode(old),
                                      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
        let store = KeychainStore(service: service)
        #expect(store.allCredentials() == [old])
        let another = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t2")
        try store.saveCredentials(another)
        #expect(store.allCredentials() == [another, old], "Kept when another is added")
        try store.deleteCredentials(another)
        try store.deleteCredentials(old)
        #expect(store.allCredentials().isEmpty)
    }
}
