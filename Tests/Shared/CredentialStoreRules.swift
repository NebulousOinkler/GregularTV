import Foundation
import GregularJellyfin
import Testing

/// What every `CredentialStore` must do, on any platform: run on the
/// in-memory store in the package's tests, and on the Keychain store in the
/// app's (which needs an app host). A new platform's store should pass too.
enum CredentialStoreRules {
    /// The checks every store must pass: several servers, the one used last
    /// first, signing in again replacing (not adding), signing out of one
    /// leaving the rest, each keeping its own device ID, and forgetting all.
    static func check(_ store: some CredentialStore) throws {
        let home = Credentials(serverURL: URL(string: "http://192.168.1.5:8096")!, userID: "u", accessToken: "t1", deviceID: "d-t1")
        let away = Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t2", deviceID: "d-t2")

        #expect(store.allCredentials().isEmpty && store.loadCredentials() == nil)
        try store.saveCredentials(home)
        try store.saveCredentials(away)
        #expect(store.allCredentials() == [away, home], "The one used last first")
        let newToken = Credentials(serverURL: home.serverURL, userID: "u", accessToken: "t3", deviceID: "d-t3")
        try store.saveCredentials(newToken)
        #expect(store.allCredentials() == [newToken, away], "Signing in again replaces, and moves to the front")

        #expect(store.allCredentials().map(\.deviceID) == [newToken.deviceID, away.deviceID], "Each its own device ID")

        try store.deleteCredentials(away)
        #expect(store.allCredentials() == [newToken], "Signing out of one keeps the others")
        try store.deleteCredentials(newToken)
        #expect(store.loadCredentials() == nil)

        try store.saveCredentials(home)
        try store.saveCredentials(away)
        try store.deleteAll()
        #expect(store.allCredentials().isEmpty, "Everything forgotten")
    }
}
