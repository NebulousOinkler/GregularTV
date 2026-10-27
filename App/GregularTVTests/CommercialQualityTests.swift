import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Commercials play at their programme's cap, the quality setting's when
/// they're tuned into, through the real Jellyfin client: in Auto with no
/// trouble, the original file, as it is or remuxed; under a fixed quality,
/// re-encoded down to it, and still played. They never run a speed test.
@MainActor @Suite(.serialized)
struct CommercialQualityTests {
    /// A channel tuned 30 seconds into a commercial break: a 20-minute
    /// episode in a 30-minute slot, the rest filled with one-minute ads. Any
    /// background speed test would start at once, so one shows if it runs.
    private func playerInABreak(server: FakeServer, playsCommercials: Bool = true,
                                quality: StreamingQuality = .auto) throws -> ChannelPlayer {
        let items = [MediaItem(id: "ep", kind: .episode, name: "E", duration: 20 * 60)]
        let ads = (0..<5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad", duration: 60) }
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-(20 * 60 + 30)), padTo: 30,
                                                                items: items, ads: ads, playsCommercials: playsCommercials).first)
        #expect(schedule.tune(at: .now).isInPadding || schedule.tune(at: .now).airing.isFiller, "The test needs to start in the break")
        let client = JellyfinClient.testing(server)
        var timings = ChannelPlayer.Timings()
        timings.backgroundMeasurementDelay = .zero
        return ChannelPlayer(schedule: schedule, streams: client, quality: quality, timings: timings)
    }

    private func settle(_ server: FakeServer) async throws {
        try await waitUntil(1) { !server.playbackInfos.isEmpty }
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test func aPlayableCommercialUsesTheOriginalFile() async throws {
        let server = FakeServer()
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate], "Auto, with no trouble: no cap")
        #expect(server.speedTests == 0, "Even in Auto, commercials never run a speed test")
        #expect(player.streamDescription == "Commercial · Auto · no cap · direct play",
                "Diagnostics say it's a commercial, and its cap: \(player.streamDescription ?? "nothing")")
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

    @Test func aCommercialThatMustBeReencodedIsConverted() async throws {
        let server = FakeServer(reply: FakeServer.hls(reasons: "VideoCodecNotSupported"))
        let player = try playerInABreak(server: server)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [StreamingQuality.maximumBitrate], "Asked once, with Auto's (no) cap")
        #expect(player.airing?.isFiller == true, "The clip is on, converted as a programme would be")
        if case .betweenProgrammes = player.status {
            Issue.record("A commercial the server converts plays; the break isn't left blank")
        }
        player.stop()
    }

    /// Under a fixed quality, a clip above it is asked for at its cap, and
    /// played re-encoded, as a programme would be: the break isn't left blank.
    @Test func underAFixedQualityACommercialIsReencodedToIt() async throws {
        let server = FakeServer(reply: FakeServer.hls(reasons: "ContainerBitrateExceedsLimit"))
        let player = try playerInABreak(server: server, quality: .hd720)
        player.tune()
        try await settle(server)
        #expect(server.requestedCaps == [4_000_000], "At the quality setting's cap: \(server.requestedCaps)")
        #expect(player.airing?.isFiller == true)
        #expect(player.streamDescription == "Commercial · 720p · 4 Mbps · up to 4 Mbps · re-encoded by the server",
                "\(player.streamDescription ?? "nothing")")
        if case .betweenProgrammes = player.status {
            Issue.record("A re-encoded commercial plays; the break isn't left blank")
        }
        player.stop()
    }
}
