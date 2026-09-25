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
        let json = [1, 2].map {
            #"{ "number": \#($0), "name": "C\#($0)", "source": { "type": "all" }, "strategy": "derangement", "seed": \#($0) }"#
        }.joined(separator: ",")
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "M\($0)", duration: 3600) }
        let channels = try ChannelLineup.load(from: Data("[\(json)]".utf8)).schedules(for: items)
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "StreamStabilityTests-\(UUID())")!)
        preferences.streamingQuality = quality
        let client = JellyfinClient(
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: OfflineTransport())
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
            for _ in 0..<100 {
                if case .failed(_, let retryAt) = player.status { return retryAt.timeIntervalSinceNow }
                try await Task.sleep(for: .milliseconds(10))
            }
            return nil
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
        let epoch = ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-600))
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "epoch": "\#(epoch)" }]"#
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 3600)]
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items).first)
        let client = JellyfinClient(   // plays directly from a server that doesn't exist
            credentials: Credentials(serverURL: URL(string: "https://tv.invalid")!, userID: "u", accessToken: "t"),
            identity: ClientIdentity(deviceID: "test"), transport: HeadStartTests.Server(reply: HeadStartTests.directPlay))
        let player = ChannelPlayer(schedule: schedule, streams: client, quality: .hd10)
        player.start()
        for _ in 0..<150 {
            if case .failed = player.status { break }
            if case .betweenProgrammes = player.status { break }
            try await Task.sleep(for: .milliseconds(100))
        }
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
