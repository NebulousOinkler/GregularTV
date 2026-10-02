import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Speed tests: Auto asks for the original with no speed test until
/// playback has trouble, and they never run unless Auto is selected.
/// Serialized: the tests change the shared background-measurement delay.
@MainActor @Suite(.serialized)
struct AutoQualityTests {
    private func makePlayer(quality: StreamingQuality, server: FakeServer) throws -> ChannelPlayer {
        let items = [MediaItem(id: "m", kind: .movie, name: "M", duration: 3600)]
        let schedule = try #require(try ChannelSchedule.testing(items: items).first)
        let client = JellyfinClient.testing(server)
        return ChannelPlayer(schedule: schedule, streams: client, quality: quality)
    }

    private func waitForPlaybackInfo(_ server: FakeServer) async throws {
        try await waitUntil(1) { !server.playbackInfos.isEmpty }
    }

    @Test func fixedQualityNeverRunsASpeedTest() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = FakeServer(speedTestDelay: .seconds(2))   // like a slow link
        let player = try makePlayer(quality: .hd10, server: server)
        player.tune()
        try await waitForPlaybackInfo(server)
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.playbackInfos.first?.url?.query?.contains("maxStreamingBitrate=10000000") == true)
        #expect(server.speedTests == 0)
        player.stop()
    }

    @Test func autoAsksForTheOriginalWithoutASpeedTest() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = FakeServer(speedTestDelay: .seconds(2))   // like a slow link
        let player = try makePlayer(quality: .auto, server: server)
        let start = ContinuousClock.now
        player.tune()
        try await waitForPlaybackInfo(server)
        #expect(ContinuousClock.now - start < .seconds(1), "Playback doesn't wait for a speed test")
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate],
                "No cap until playback has trouble: a lower one would make the server re-encode")
        #expect(server.speedTests == 0)
        player.stop()
    }

    @Test func switchingAwayFromAutoUsesTheFixedCapWithNoSpeedTest() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .milliseconds(200)
        let server = FakeServer(speedTestDelay: .seconds(2))   // like a slow link
        let player = try makePlayer(quality: .auto, server: server)
        player.tune()
        try await waitForPlaybackInfo(server)
        player.setQuality(.hd720)
        try await Task.sleep(for: .milliseconds(600))
        #expect(server.speedTests == 0)
        #expect(server.playbackInfos.last?.url?.query?.contains("maxStreamingBitrate=4000000") == true)
        player.stop()
    }
}
