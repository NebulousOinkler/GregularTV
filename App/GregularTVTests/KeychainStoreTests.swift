import Foundation
import GregularCore
import GregularJellyfin
import Testing

/// The Keychain needs an app host, so this test lives here and not in the
/// `GregularTVCore` package tests.
struct KeychainStoreTests {
    @Test func roundTripAndSignOut() throws {
        let store = KeychainStore(service: "GregularTVTests-\(UUID().uuidString)")
        let credentials = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t")

        #expect(store.loadCredentials() == nil)
        try store.saveCredentials(credentials)
        #expect(store.loadCredentials() == credentials)

        let deviceID = store.deviceID()
        #expect(store.deviceID() == deviceID)

        try store.deleteCredentials()
        #expect(store.loadCredentials() == nil)
        #expect(store.deviceID() == deviceID, "Device ID should survive sign-out")
    }
}
