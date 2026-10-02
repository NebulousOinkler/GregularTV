import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Tuning into a programme Jellyfin has to re-encode starts a little ahead of
/// live, so the transcode can get ahead before playback reaches it.
@MainActor @Suite(.serialized)
struct HeadStartTests {
    /// A player `elapsed` seconds into an hour-long programme.
    private func player(reply: String, elapsed: TimeInterval = 600) throws -> ChannelPlayer {
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 3600)]
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-elapsed), items: items).first)
        let client = JellyfinClient.testing(FakeServer(reply: reply))
        return ChannelPlayer(schedule: schedule, streams: client, quality: .hd10)
    }

    private func settledStatus(_ player: ChannelPlayer) async throws -> ChannelPlayer.Status {
        try await waitUntil(1) { player.status != .tuning }
        return player.status
    }

    @Test func aReencodedProgrammeStartsAheadOfLive() async throws {
        let player = try player(reply: FakeServer.hls(reasons: "VideoCodecNotSupported"))
        player.tune()
        guard case .startingSoon(let at) = try await settledStatus(player) else {
            Issue.record("Expected a head start, not \(player.status)")
            return
        }
        #expect(abs(at.timeIntervalSinceNow - ChannelPlayer.transcodeHeadStart) < 2)
        player.stop()
    }

    @Test(arguments: [FakeServer.directPlay, FakeServer.hls(reasons: "ContainerNotSupported,AudioCodecNotSupported")])
    func aFileThatIsntReencodedStartsAtOnce(reply: String) async throws {
        let player = try player(reply: reply)
        player.tune()
        #expect(try await settledStatus(player) == .playing)
        player.stop()
    }

    @Test func aReencodedProgrammeWithTooLittleLeftIsntStarted() async throws {
        let player = try player(reply: FakeServer.hls(reasons: "VideoCodecNotSupported"), elapsed: 3600 - 120)
        player.tune()
        guard case .betweenProgrammes(let until) = try await settledStatus(player) else {
            Issue.record("Expected Up next, not \(player.status)")
            return
        }
        #expect(abs(until.timeIntervalSinceNow - 120) < 2, "Up next until the programme's slot ends")
        player.stop()
    }

    @Test func aRemuxedProgrammeWithLittleLeftStillPlays() async throws {
        let player = try player(reply: FakeServer.hls(reasons: "ContainerNotSupported"), elapsed: 3600 - 120)
        player.tune()
        #expect(try await settledStatus(player) == .playing)
        player.stop()
    }
}
