import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Speed tests: Auto never delays playback for one, and they never run
/// unless Auto is selected.
/// Serialized: the tests change the shared background-measurement delay.
@MainActor @Suite(.serialized)
struct AutoQualityTests {
    /// A fake server that records every request. Speed tests answer slowly,
    /// like the real one over a slow link.
    final class RecordingServer: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var log: [URLRequest] = []

        var requests: [URLRequest] { lock.withLock { log } }
        var speedTests: Int { requests.filter { $0.url!.path.hasSuffix("/Playback/BitrateTest") }.count }
        var playbackInfos: [URLRequest] { requests.filter { $0.url!.path.hasSuffix("/PlaybackInfo") } }

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            lock.withLock { log.append(request) }
            var body = Data()
            if request.url!.path.hasSuffix("/Playback/BitrateTest") {
                try await Task.sleep(for: .seconds(2))
                body = Data(count: 1000)
            } else if request.url!.path.hasSuffix("/PlaybackInfo") {
                body = Data(#"{ "MediaSources": [{ "Id": "s", "SupportsDirectPlay": true }], "PlaySessionId": "p" }"#.utf8)
            }
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    private func makePlayer(quality: StreamingQuality, server: RecordingServer) throws -> ChannelPlayer {
        let items = [MediaItem(id: "m", kind: .movie, name: "M", duration: 3600)]
        let schedule = try #require(try ChannelSchedule.testing(items: items).first)
        let client = JellyfinClient.testing(server)
        return ChannelPlayer(schedule: schedule, streams: client, quality: quality)
    }

    private func waitForPlaybackInfo(_ server: RecordingServer) async throws {
        try await waitUntil(1) { !server.playbackInfos.isEmpty }
    }

    @Test func fixedQualityNeverRunsASpeedTest() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = RecordingServer()
        let player = try makePlayer(quality: .hd10, server: server)
        player.tune()
        try await waitForPlaybackInfo(server)
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.playbackInfos.first?.url?.query?.contains("maxStreamingBitrate=10000000") == true)
        #expect(server.speedTests == 0)
        player.stop()
    }

    @Test func autoStartsPlayingWithoutWaitingForTheSpeedTest() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = RecordingServer()
        let player = try makePlayer(quality: .auto, server: server)
        let start = ContinuousClock.now
        player.tune()
        try await waitForPlaybackInfo(server)
        #expect(ContinuousClock.now - start < .seconds(1), "The speed test takes 2 s; playback mustn't wait for it")
        #expect(server.playbackInfos.first?.url?.query?.contains("maxStreamingBitrate=8000000") == true,
                "Before any measurement, Auto starts at 8 Mbps")
        player.stop()
    }

    @Test func switchingAwayFromAutoStopsSpeedTests() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .milliseconds(200)
        let server = RecordingServer()
        let player = try makePlayer(quality: .auto, server: server)
        player.tune()
        try await waitForPlaybackInfo(server)
        player.setQuality(.hd720)   // before the delayed speed test starts
        try await Task.sleep(for: .milliseconds(600))
        #expect(server.speedTests == 0)
        #expect(server.playbackInfos.last?.url?.query?.contains("maxStreamingBitrate=4000000") == true)
        player.stop()
    }
}
