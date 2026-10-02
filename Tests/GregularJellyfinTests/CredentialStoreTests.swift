import Foundation
import Testing
@testable import GregularJellyfin

/// What a sign-in holds. The rules every store must keep are
/// `CredentialStoreRules` (Tests/Shared), run on each store.
struct CredentialStoreTests {
    @Test func credentialsHoldNoPassword() throws {
        // Only the address, user ID, token and device ID are kept: the password is sent once, to sign in.
        let encoded = try JSONEncoder().encode(Credentials(serverURL: URL(string: "https://tv.example")!, userID: "u", accessToken: "t", deviceID: "d-t"))
        let keys = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any]).keys
        #expect(Set(keys) == ["serverURL", "userID", "accessToken", "deviceID"])
    }

    /// One saved before each sign-in had its own device ID still reads, with none.
    @Test func aSignInFromBeforeDeviceIDsReadsWithNone() throws {
        let old = Data(#"{ "serverURL": "https://tv.example", "userID": "u", "accessToken": "t" }"#.utf8)
        let credentials = try JSONDecoder().decode(Credentials.self, from: old)
        #expect(credentials.accessToken == "t" && credentials.deviceID.isEmpty)
        #expect(credentials.withDeviceID("shared").deviceID == "shared")
    }

    @Test func eachSignInGetsADeviceIDOfItsOwn() {
        let first = ClientIdentity.forSignIn(deviceName: "Apple TV"), second = ClientIdentity.forSignIn(deviceName: "Apple TV")
        #expect(first.deviceID != second.deviceID && !first.deviceID.isEmpty && first.deviceName == "Apple TV")
    }
}
