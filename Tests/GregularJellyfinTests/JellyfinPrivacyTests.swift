import Foundation
import GregularCore
import Testing
@testable import GregularJellyfin

/// Guards the privacy rules in PLAN.md §3 for everything that talks to Jellyfin.
struct JellyfinPrivacyTests {
    /// Endpoints that would tell Jellyfin what's being watched, or change
    /// watched state. The app must never call any of them.
    static let forbiddenPathFragments = [
        "/Sessions/Playing", "/PlayingItems", "/PlayedItems", "/UserPlayedItems", "/UserData",
    ]

    @Test func noClientCallReportsPlayback() async throws {
        let mock = MockJellyfin()
        mock.on("POST", "/Sessions/Capabilities/Full", status: 204)
        mock.on("GET", "/Items", json: #"{ "Items": [], "TotalRecordCount": 0 }"#)
        mock.on("POST", "/Items/abc/PlaybackInfo",
                json: #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#)
        mock.on("DELETE", "/Videos/ActiveEncodings", status: 204)
        mock.on("POST", "/Sessions/Logout", status: 204)
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v", "Name": "Commercials", "Type": "CollectionFolder" }], "TotalRecordCount": 1 }"#)

        let client = JellyfinFixtures.client(mock)
        try await client.registerCapabilities()
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

    @Test func capabilitiesRefuseRemoteControl() async throws {
        let mock = MockJellyfin()
        mock.on("POST", "/Sessions/Capabilities/Full", status: 204)
        try await JellyfinFixtures.client(mock).registerCapabilities()
        let body = try #require(mock.requests.first).jsonBody
        #expect(body["SupportsMediaControl"] as? Bool == false)
        #expect((body["SupportedCommands"] as? [String])?.isEmpty == true)
    }

    @Test func networkSessionNeverCachesToDisk() {
        let config = URLSessionTransport.makeConfiguration()
        #expect(config.urlCache == nil)
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCredentialStorage == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func signOutClearsLocalCredentialsEvenIfServerUnreachable() async {
        let mock = MockJellyfin()   // every route returns 404
        let store = InMemoryCredentialStore(credentials: JellyfinFixtures.credentials)
        await JellyfinFixtures.client(mock).signOut(clearing: store)
        #expect(store.loadCredentials() == nil)
        #expect(mock.requests.map(\.url!.path) == ["/Sessions/Logout"])
    }
}
