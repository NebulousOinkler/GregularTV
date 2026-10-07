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
    /// The one exception: the transcode keep-alive, which names only the
    /// play session (`JellyfinClient.keepTranscoding`).
    static let allowedPaths = [JellyfinClient.keepAlivePath.lowercased()]

    @Test func noClientCallReportsPlayback() async throws {
        let mock = MockJellyfin()
        mock.on("GET", "/Items", json: #"{ "Items": [], "TotalRecordCount": 0 }"#)
        mock.on("POST", "/Items/abc/PlaybackInfo",
                json: #"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#)
        mock.on("DELETE", "/Videos/ActiveEncodings", status: 204)
        mock.on("POST", "/Sessions/Playing/Ping", status: 204)
        mock.on("POST", "/Sessions/Logout", status: 204)
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v", "Name": "Commercials", "Type": "CollectionFolder" }], "TotalRecordCount": 1 }"#)

        let client = JellyfinFixtures.client(mock)
        _ = try await client.fetchLibrary()
        _ = try await client.fetchLibrary(named: "Commercials", kinds: Set(MediaItem.Kind.allCases))
        _ = try await client.playbackSource(for: "abc")
        _ = try await client.lyrics(for: "abc")
        _ = try await client.originalFile(of: MediaItem(id: "abc", kind: .song, name: "Song", duration: 200))
        try await client.stopTranscoding(playSessionID: "p")
        await client.keepAlive(MediaStream(url: URL(string: "https://tv.invalid/s")!, delivery: .converted, sessionID: "p"))
        await client.signOut(clearing: InMemoryCredentialStore())

        #expect(mock.requests.count >= 6)
        for request in mock.requests {
            let path = request.url.path.lowercased()
            guard !Self.allowedPaths.contains(path) else { continue }
            for fragment in Self.forbiddenPathFragments {
                #expect(!path.contains(fragment.lowercased()), "Forbidden request: \(request.url)")
            }
        }
    }

    /// The keep-alive tells the server only which play session is still
    /// wanted: no item, no position, no body.
    @Test func keepAliveNamesOnlyThePlaySession() async throws {
        let mock = MockJellyfin()
        mock.on("POST", "/Sessions/Playing/Ping", status: 204)
        let client = JellyfinFixtures.client(mock)
        await client.keepAlive(MediaStream(url: URL(string: "https://tv.invalid/s")!, delivery: .converted, sessionID: "p"))
        await client.keepAlive(MediaStream(url: URL(string: "https://tv.invalid/f")!, delivery: .original))

        let request = try #require(mock.requests.first)
        #expect(mock.requests.count == 1, "A stream with no session has nothing to keep going")
        #expect(request.url.path == "/Sessions/Playing/Ping")
        #expect(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "playSessionId", value: "p")])
        #expect(request.body?.isEmpty ?? true)
    }

    @Test func signOutClearsLocalCredentialsEvenIfServerUnreachable() async throws {
        let mock = MockJellyfin()   // every route returns 404
        let other = Credentials(serverURL: URL(string: "https://other.example")!, userID: "u", accessToken: "t", deviceID: "d-t")
        let store = InMemoryCredentialStore(credentials: other)
        try store.saveCredentials(JellyfinFixtures.credentials)
        #expect(await JellyfinFixtures.client(mock).signOut(clearing: store) == false, "Says the server wasn't told")
        #expect(store.allCredentials() == [other], "Only this server's sign-in goes")
        #expect(mock.requests.map(\.url.path) == ["/Sessions/Logout"])
    }
}
