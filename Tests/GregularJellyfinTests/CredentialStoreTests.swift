import Foundation
import Testing
@testable import GregularJellyfin

/// What every `CredentialStore` must do, on any platform. The Keychain store
/// needs an app host, so the same checks for it are in the app's tests
/// (`KeychainStoreTests`); a new platform's store should pass them too.
struct CredentialStoreTests {
    @Test func inMemoryStoreKeepsTheRules() throws {
        try Self.checkRules(InMemoryCredentialStore())
    }

    /// The checks every store must pass: several servers, the one used last
    /// first, signing in again replacing (not adding), signing out of one
    /// leaving the rest, and the device ID surviving it all.
    static func checkRules(_ store: some CredentialStore) throws {
        let home = Credentials(serverURL: URL(string: "http://192.168.1.5:8096")!, userID: "u", accessToken: "t1")
        let away = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t2")

        #expect(store.allCredentials().isEmpty && store.loadCredentials() == nil)
        try store.saveCredentials(home)
        try store.saveCredentials(away)
        #expect(store.allCredentials() == [away, home], "The one used last first")
        let newToken = Credentials(serverURL: home.serverURL, userID: "u", accessToken: "t3")
        try store.saveCredentials(newToken)
        #expect(store.allCredentials() == [newToken, away], "Signing in again replaces, and moves to the front")

        let deviceID = store.deviceID()
        #expect(!deviceID.isEmpty && store.deviceID() == deviceID)

        try store.deleteCredentials(away)
        #expect(store.allCredentials() == [newToken], "Signing out of one keeps the others")
        try store.deleteCredentials(newToken)
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
