import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// The stream only restarts on an explicit change. `tuneCount` goes up on
/// every re-tune, so these tests count re-tunes directly.
@MainActor
struct StreamStabilityTests {
    private struct OfflineTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }

    private func makeSurfer(quality: StreamingQuality = .auto) throws -> ChannelSurfer {
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "M\($0)", duration: 3600) }
        let channels = try ChannelSchedule.testing([1, 2], items: items)
        let preferences = AppPreferences.testing()
        preferences.streamingQuality = quality
        let client = JellyfinClient.testing(OfflineTransport())
        return ChannelSurfer(channels: channels, startingWith: channels[0], streams: client, preferences: preferences)
    }

    @Test func startingAgainDoesNotRetune() throws {
        let player = try makeSurfer().player
        player.start()
        let tunes = player.tuneCount
        player.start()   // e.g. the view appearing again, or the app becoming active after Control Center
        player.start()
        #expect(player.tuneCount == tunes)
        player.stop()
    }

    @Test func startAfterStopResumesLive() throws {
        let player = try makeSurfer().player
        player.start()
        let tunes = player.tuneCount
        player.stop()    // a real trip to the background
        player.start()
        #expect(player.tuneCount == tunes + 1)
        player.stop()
    }

    @Test func changingChannelStartsWithTheShortestRetryWait() async throws {
        let surfer = try makeSurfer()
        let player = surfer.player
        func waitForFailure() async throws -> TimeInterval? {
            try await waitUntil(1) { player.status.isFailed }
            guard case .failed(_, let retryAt) = player.status else { return nil }
            return retryAt.timeIntervalSinceNow
        }
        player.tune()
        _ = try await waitForFailure()
        player.tune()   // a retry that fails again waits longer
        #expect(try #require(await waitForFailure()) > 8)
        player.switchTo(surfer.channels[1])
        #expect(try #require(await waitForFailure()) <= 5, "Not the old channel's longer wait")
        player.stop()
    }

    /// AVQueuePlayer drops an item that fails from its queue. That mustn't
    /// look like the programme finishing (blank until the slot ends): it
    /// should fail, and so retry.
    @Test func aStreamThatFailsIsRetriedNotTreatedAsFinished() async throws {
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 3600)]
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-600), items: items).first)
        // Plays directly from a server that doesn't exist.
        let client = JellyfinClient.testing(HeadStartTests.Server(reply: HeadStartTests.directPlay))
        let player = ChannelPlayer(schedule: schedule, streams: client, quality: .hd10)
        player.start()
        try await waitUntil(15) { player.status.isFailed || player.status.isBetweenProgrammes }
        guard case .failed = player.status else {
            Issue.record("Expected a failure and retry, not \(player.status)")
            return player.stop()
        }
        player.stop()
    }

    @Test func choosingTheCurrentQualityDoesNotRetune() throws {
        let player = try makeSurfer(quality: .auto).player
        player.start()
        let tunes = player.tuneCount
        player.setQuality(.auto)
        #expect(player.tuneCount == tunes)
        player.setQuality(.hd10)   // an explicit change does re-tune
        #expect(player.tuneCount == tunes + 1)
        player.stop()
    }

    @Test func choosingTheCurrentChannelDoesNotRetune() throws {
        let surfer = try makeSurfer()
        surfer.player.start()
        let tunes = surfer.player.tuneCount
        surfer.tune(to: 1)   // from the list, the guide, or typing its number
        #expect(surfer.player.tuneCount == tunes)
        surfer.tune(to: 2)
        #expect(surfer.player.tuneCount == tunes + 1)
        surfer.player.stop()
    }
}
