import Foundation
import GregularCore
import GregularJellyfin
import GregularKeychain
import Security
import Testing

/// The Keychain needs an app host, so these tests live here and not in the
/// package tests. The first is `CredentialStoreRules`, as every store passes.
struct KeychainStoreTests {
    private func store() -> (KeychainStore, String) {
        let service = "GregularTVTests-\(UUID().uuidString)"
        return (KeychainStore(service: service), service)
    }

    /// Puts `data` in the Keychain as an earlier version would have.
    private func add(_ data: Data, account: String, service: String) {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                                      kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
    }

    @Test func keepsTheRules() throws {
        try CredentialStoreRules.check(store().0)
    }

    /// The one sign-in an earlier version kept is still there after
    /// updating, with the device ID every sign-in shared then (its token
    /// goes with it).
    @Test func anEarlierVersionsSignInCarriesOverWithItsDeviceID() throws {
        let (store, service) = store()
        let old = Data(#"{ "serverURL": "http://nas:8096", "userID": "u", "accessToken": "t" }"#.utf8)
        add(old, account: "credentials", service: service)
        add(Data("shared-id".utf8), account: "device-id", service: service)
        let expected = Credentials(serverURL: URL(string: "http://nas:8096")!, userID: "u", accessToken: "t", deviceID: "shared-id")
        #expect(store.allCredentials() == [expected])

        let another = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t2", deviceID: "new-id")
        try store.saveCredentials(another)
        #expect(store.allCredentials() == [another, expected], "Kept, with its device ID, when another is added")
        try store.deleteAll()
        #expect(store.allCredentials().isEmpty)
    }

    /// One sign-in the list can't read doesn't lose the others.
    @Test func anUnreadableSignInLosesOnlyItself() throws {
        let (store, service) = store()
        let list = Data(#"[{ "serverURL": "https://tv.example", "userID": "u", "accessToken": "t", "deviceID": "d" }, { "broken": true }]"#.utf8)
        add(list, account: "sign-ins", service: service)
        #expect(store.allCredentials().map(\.accessToken) == ["t"])
        try store.deleteAll()
    }
}
