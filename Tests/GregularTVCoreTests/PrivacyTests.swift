import Foundation
import Testing
@testable import GregularTVCore

/// Guards the privacy rules in PLAN.md §3.
struct PrivacyTests {
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

    @Test func preferencesStoreOnlyClientSettings() throws {
        let suite = "GregularTVTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = AppPreferences(defaults: defaults)
        #expect(prefs.lastChannelNumber == nil)
        prefs.lastChannelNumber = 7
        #expect(AppPreferences(defaults: defaults).lastChannelNumber == 7)
        #expect(prefs.streamingQuality == .auto)
        prefs.streamingQuality = .hd720
        #expect(AppPreferences(defaults: defaults).streamingQuality == .hd720)
        #expect(prefs.scheduleCode == nil)
        prefs.scheduleCode = ScheduleCode("7KQM2-X9PDA")
        #expect(AppPreferences(defaults: defaults).scheduleCode == ScheduleCode("7KQM2-X9PDA"))
        #expect(prefs.showsDiagnostics == false)
        prefs.showsDiagnostics = true
        #expect(AppPreferences(defaults: defaults).showsDiagnostics)
        #expect(prefs.playsCommercials)
        prefs.playsCommercials = false
        #expect(AppPreferences(defaults: defaults).playsCommercials == false)
        #expect(defaults.persistentDomain(forName: suite)?.keys.sorted()
                == ["lastChannelNumber", "playsCommercials", "scheduleCode", "showsDiagnostics", "streamingQuality"])
    }

    #if os(macOS)
    /// Runs `scripts/privacy-check.sh`, the same check the app build runs,
    /// so `swift test` also fails if persistence APIs creep in.
    @Test func sourceUsesNoPersistenceOutsideAllowedFiles() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = repo.appendingPathComponent("scripts/privacy-check.sh")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(process.terminationStatus == 0, "\(log)")
    }
    #endif

    // The Keychain round-trip test lives in App/GregularTVTests, because it needs an app host.
}
