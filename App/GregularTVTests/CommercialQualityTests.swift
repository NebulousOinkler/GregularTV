import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Commercials never make the server re-encode video: the original file,
/// asked for with no bitrate cap (as-is or remuxed), else they're skipped.
/// They never run a speed test.
@MainActor @Suite(.serialized)
struct CommercialQualityTests {
    /// A channel tuned 30 seconds into a commercial break: a 20-minute
    /// episode in a 30-minute slot, the rest filled with one-minute ads.
    private func playerInABreak(server: FakeServer, playsCommercials: Bool = true) throws -> ChannelPlayer {
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 20 * 60)]
        let ads = (0..<5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad", duration: 60) }
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-(20 * 60 + 30)), padTo: 30,
                                                                items: items, ads: ads, playsCommercials: playsCommercials).first)
        #expect(schedule.tune(at: .now).isInPadding || schedule.tune(at: .now).airing.isFiller, "The test needs to start in the break")
        let client = JellyfinClient.testing(server)
        return ChannelPlayer(schedule: schedule, streams: client, quality: .auto)
    }

    private func settle(_ server: FakeServer) async throws {
        try await waitUntil(1) { !server.playbackInfos.isEmpty }
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func aPlayableCommercialUsesTheOriginalFile() async throws {
        ChannelPlayer.backgroundMeasurementDelay = .zero
        let server = FakeServer()
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate], "No cap, whatever the quality setting")
        #expect(server.speedTests == 0, "Even in Auto, commercials never run a speed test")
        player.stop()
    }

    @Test func aRemuxIsKeptBecauseItIsCheap() async throws {
        let server = FakeServer(reply: FakeServer.hls(reasons: "ContainerNotSupported,AudioCodecNotSupported"))
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate])
        player.stop()
    }

    @Test func withCommercialsOffABreakAsksJellyfinForNothing() async throws {
        let server = FakeServer()
        let player = try playerInABreak(server: server, playsCommercials: false)
        player.tune()
        try await Task.sleep(for: .milliseconds(500))
        #expect(server.playbackInfos.isEmpty, "No commercial is requested, so no stream is opened")
        #expect(player.airing?.isFiller == false, "The banner shows the programme, not a commercial")
        guard case .betweenProgrammes = player.status else {
            Issue.record("A break with commercials off is blank, not \(player.status)")
            return
        }
        player.stop()
    }

    @Test func aCommercialThatMustBeReencodedIsSkipped() async throws {
        let server = FakeServer(reply: FakeServer.hls(reasons: "VideoCodecNotSupported"))
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate], "Asked once; no lower-quality retry")
        guard case .betweenProgrammes = player.status else {
            Issue.record("A skipped commercial leaves the screen blank, not \(player.status)")
            return
        }
        // Tuning in again asks nothing more about the same clip this session.
        let asked = server.playbackInfos.count
        player.tune()
        try await Task.sleep(for: .milliseconds(300))
        #expect(server.playbackInfos.count == asked)
        player.stop()
    }
}
