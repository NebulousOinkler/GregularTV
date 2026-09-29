import Foundation
import Testing
@testable import GregularJellyfin

/// What every `CredentialStore` must do, on any platform. The Keychain store
/// needs an app host, so the same checks for it are in the app's tests
/// (`KeychainStoreTests`); a new platform's store should pass them too.
struct CredentialStoreTests {
    @Test func inMemoryStoreKeepsTheRules() throws {
        let store = InMemoryCredentialStore()
        let credentials = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t")

        #expect(store.loadCredentials() == nil)
        try store.saveCredentials(credentials)
        #expect(store.loadCredentials() == credentials)

        let deviceID = store.deviceID()
        #expect(!deviceID.isEmpty && store.deviceID() == deviceID)

        try store.deleteCredentials()
        #expect(store.loadCredentials() == nil)
        #expect(store.deviceID() == deviceID, "The device ID survives sign-out")
    }

    @Test func credentialsHoldNoPassword() throws {
        // Only the address, user ID and token are kept: the password is sent once, to sign in.
        let encoded = try JSONEncoder().encode(Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t"))
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
        #expect(Set(keys) == ["serverURL", "userID", "accessToken"])
    }
}
