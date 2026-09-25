import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularTV

/// Remote-input logic: up/down with preview and settle, wrapping, and number
/// entry. The player has no server (every request fails straight away), so
/// these tests only check which channel it's told to play.
@MainActor
struct ChannelSurferTests {
    private struct OfflineTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }

    private let preferences = AppPreferences(defaults: UserDefaults(suiteName: "ChannelSurferTests-\(UUID())")!)

    /// Channels 1, 2, 5 and 10 (note the gaps), each with a few movies.
    private func makeSurfer() throws -> ChannelSurfer {
        let json = [1, 2, 5, 10].map {
            #"{ "number": \#($0), "name": "C\#($0)", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": \#($0) }"#
        }.joined(separator: ",")
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "M\($0)", duration: 3600) }
        let channels = try ChannelLineup.load(from: Data("[\(json)]".utf8)).schedules(for: items)
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: OfflineTransport())
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: client, preferences: preferences)
    }

    private func settle() async throws {
        try await Task.sleep(for: ChannelSurfer.settleDelay + .milliseconds(300))
    }

    @Test func channelUpPreviewsThenTunes() async throws {
        let surfer = try makeSurfer()
        surfer.channelUp()
        #expect(surfer.preview?.channel.number == 2)
        #expect(surfer.player.schedule.channel.number == 1, "Shouldn't tune until presses stop")

        try await settle()
        #expect(surfer.player.schedule.channel.number == 2)
        #expect(surfer.preview == nil)
        #expect(preferences.lastChannelNumber == 2)
    }

    @Test func rapidPressesTuneOnceToTheFinalChannel() async throws {
        let surfer = try makeSurfer()
        let tunesBefore = surfer.player.tuneCount
        surfer.channelUp()
        surfer.channelUp()
        surfer.channelUp()
        #expect(surfer.preview?.channel.number == 10)

        try await settle()
        #expect(surfer.player.schedule.channel.number == 10)
        #expect(surfer.player.tuneCount == tunesBefore + 1)
    }

    @Test func channelDownWrapsToHighest() async throws {
        let surfer = try makeSurfer()
        surfer.channelDown()
        try await settle()
        #expect(surfer.player.schedule.channel.number == 10)
    }

    @Test func typingMaxDigitsTunesImmediately() throws {
        let surfer = try makeSurfer()
        surfer.type(digit: "1")
        #expect(surfer.typedDigits == "1")
        surfer.type(digit: "0")
        #expect(surfer.typedDigits.isEmpty)
        #expect(surfer.player.schedule.channel.number == 10)
    }

    @Test func singleDigitTunesAfterAPause() async throws {
        let surfer = try makeSurfer()
        surfer.type(digit: "5")
        #expect(surfer.player.schedule.channel.number == 1)
        try await Task.sleep(for: ChannelSurfer.digitTimeout + .milliseconds(300))
        #expect(surfer.player.schedule.channel.number == 5)
    }

    @Test func unknownChannelShowsNotice() throws {
        let surfer = try makeSurfer()
        surfer.tune(to: 9)
        #expect(surfer.notice == "No channel 9")
        #expect(surfer.player.schedule.channel.number == 1)
    }
}

/// If the server rejects the token mid-session, the player stops retrying and
/// hands off to sign-in.
@MainActor
struct ChannelPlayerAuthTests {
    private struct RevokedTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test func revokedTokenCallsOnUnauthorizedInsteadOfRetrying() async throws {
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 1 }]"#
        let items = [MediaItem(id: "m", kind: .movie, name: "M", duration: 3600)]
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items).first)
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: RevokedTransport())
        let player = ChannelPlayer(schedule: schedule, streams: client, quality: .maximum)

        var called = false
        player.onUnauthorized = { called = true }
        player.tune()
        for _ in 0..<50 where !called { try await Task.sleep(for: .milliseconds(20)) }

        #expect(called)
        #expect(player.status == .tuning, "Stopped, not scheduled for retry")
    }
}
