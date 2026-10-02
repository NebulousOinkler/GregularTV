import Foundation
import GregularCore
import Testing
@testable import GregularJellyfin

/// Guards the privacy rules in PLAN.md §3 for everything that talks to Jellyfin.
struct JellyfinPrivacyTests {
    /// Endpoints that would tell Jellyfin what's being watched, change
    /// watched state, or register the device for remote control. The app
    /// must never call any of them.
    static let forbiddenPathFragments = [
        "/Sessions/Playing", "/PlayingItems", "/PlayedItems", "/UserPlayedItems", "/UserData", "/Sessions/Capabilities",
    ]

    @Test func noClientCallReportsPlayback() async throws {
        let mock = MockJellyfin()
        mock.on("GET", "/Items", json: #"{ "Items": [], "TotalRecordCount": 0 }"#)
        mock.on("POST", "/Items/abc/PlaybackInfo",
                json: #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#)
        mock.on("DELETE", "/Videos/ActiveEncodings", status: 204)
        mock.on("POST", "/Sessions/Logout", status: 204)
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v", "Name": "Commercials", "Type": "CollectionFolder" }], "TotalRecordCount": 1 }"#)

        let client = JellyfinFixtures.client(mock)
        _ = try await client.fetchLibrary()
        _ = try await client.fetchLibrary(named: "Commercials")
        _ = try await client.playbackSource(for: "abc")
        try await client.stopTranscoding(playSessionID: "p")
        await client.signOut(clearing: InMemoryCredentialStore())

        #expect(mock.requests.count >= 5)
        for request in mock.requests {
            let path = request.url!.path.lowercased()
            for fragment in Self.forbiddenPathFragments {
                #expect(!path.contains(fragment.lowercased()), "Forbidden request: \(request.url!)")
            }
        }
    }

    @Test func signOutClearsLocalCredentialsEvenIfServerUnreachable() async throws {
        let mock = MockJellyfin()   // every route returns 404
        let other = Credentials(serverURL: URL(string: "https://other.example")!, userID: "u", accessToken: "t", deviceID: "d-t")
        let store = InMemoryCredentialStore(credentials: other)
        try store.saveCredentials(JellyfinFixtures.credentials)
        #expect(await JellyfinFixtures.client(mock).signOut(clearing: store) == false, "Says the server wasn't told")
        #expect(store.allCredentials() == [other], "Only this server's sign-in goes")
        #expect(mock.requests.map(\.url!.path) == ["/Sessions/Logout"])
    }
}
