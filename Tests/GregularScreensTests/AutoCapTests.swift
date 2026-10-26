import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// Auto quality, on decks with no video: the original until a programme
/// has trouble on the connection, then a cap for that programme from a
/// speed test made with nothing playing.
@MainActor @Suite(.serialized)
struct AutoCapTests {
    /// Auto, `elapsed` seconds into the first of two hour-long films.
    private func player(_ streams: FakeStreams, elapsed: TimeInterval = 600) throws -> ChannelPlayer {
        let items = (1...2).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-elapsed), items: items).first)
        return ChannelPlayer(schedule: schedule, streams: streams, quality: .auto, decks: FakeDeck.pair())
    }

    @Test func autoAsksForTheOriginalWithNoSpeedTest() async throws {
        let streams = FakeStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        try await Fixture.settle(player)
        #expect(streams.caps == [StreamingQuality.maximumBitrate],
                "No cap: a lower one would make the server re-encode")
        #expect(streams.speedTests == 0)
        player.stop()
    }

    @Test func fallingBehindLiveMeasuresThenCaps() async throws {
        let streams = FakeStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.seek(to: 300)   // as if buffering had left it 5 minutes behind live
        try await waitUntil(3) { streams.caps.count == 2 }
        #expect(streams.speedTests == 1, "Measured before loading again")
        #expect(streams.caps.last == 7_000_000, "70% of the measurement")
        try await Fixture.settle(player)
        player.stop()
    }

    /// The cap is for the programme that had trouble: the next one starts
    /// again with the original, with no speed test.
    @Test func theNextProgrammeStartsAgainWithTheOriginal() async throws {
        let streams = FakeStreams(measured: 10_000_000)
        // The next programme is asked for 30 seconds before this one ends: a few seconds from now.
        let player = try player(streams, elapsed: 3600 - 40)
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.seek(to: 300)   // as if buffering had left it far behind live
        try await waitUntil(3) { streams.caps.count == 2 }
        #expect(streams.caps.last == 7_000_000 && streams.speedTests == 1)
        try await waitUntil(15) { streams.caps.count == 3 }
        #expect(streams.caps.last == StreamingQuality.maximumBitrate && streams.speedTests == 1)
        player.stop()
    }

    /// Changing channel starts again with the original too.
    @Test func anotherChannelStartsAgainWithTheOriginal() async throws {
        let streams = FakeStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.seek(to: 0)
        try await waitUntil(3) { streams.caps.count == 2 }
        #expect(streams.caps.last == 7_000_000)
        player.switchTo(player.schedule)
        try await waitUntil(3) { streams.caps.count == 3 }
        #expect(streams.caps.last == StreamingQuality.maximumBitrate && streams.speedTests == 1)
        player.stop()
    }

    /// Asking the server for the stream and waiting too long is a busy
    /// server, not a connection that can't carry the stream: no speed test.
    @Test func aTimeoutAskingForTheStreamDoesntMeasure() async throws {
        let streams = FakeStreams(measured: 10_000_000, failingFirst: URLError(.timedOut))
        let player = try player(streams)
        player.start()
        try await waitUntil(8) { streams.caps.count == 2 && player.status == .playing }   // retried after the first backoff
        #expect(streams.speedTests == 0 && streams.caps.last == StreamingQuality.maximumBitrate)
        player.stop()
    }

    /// Only the connection's failures measure: a lower quality wouldn't
    /// help a file the player can't show, or the server's own error.
    @Test(arguments: [(URLError(.timedOut) as any Error, true), (UnplayableFile() as any Error, false)])
    func onlyAConnectionFailureMeasures(failure: any Error, measures: Bool) async throws {
        let streams = FakeStreams(measured: 10_000_000)
        let player = try player(streams)
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let item = try #require(deck.queue.first)
        item.failure = failure
        item.hasFailed = true
        try await waitUntil(8) { streams.caps.count == 2 }   // retried after the first backoff
        #expect(streams.speedTests == (measures ? 1 : 0))
        #expect(streams.caps.last == (measures ? 7_000_000 : StreamingQuality.maximumBitrate))
        player.stop()
    }
}

extension AutoCapTests {
    /// A retry that lands in a break measures as it starts, with nothing
    /// loaded, not once a commercial is downloading; the commercial, and the
    /// next showing after the break, aren't capped.
    @Test func aRetryInABreakMeasuresBeforeTheCommercialLoads() async throws {
        let film = MediaItem(id: "m1", kind: .movie, name: "Film", duration: 50 * 60)
        let ads = (1...5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 60) }
        // 2 seconds before the film ends, and its break.
        let channels = try ChannelSchedule.testing([1], epoch: Date.now.addingTimeInterval(-(50 * 60 - 2)), padTo: 60,
                                                   items: [film], ads: ads)
        let streams = FakeStreams(measured: 10_000_000)
        let player = ChannelPlayer(schedule: channels[0], streams: streams, quality: .auto, decks: FakeDeck.pair())
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let item = try #require(deck.queue.first)
        item.failure = URLError(.networkConnectionLost)
        item.hasFailed = true
        try await waitUntil(8) { streams.speedTests == 1 && streams.events.last != "speed test" }
        let events = streams.events
        let measured = try #require(events.firstIndex(of: "speed test"))
        #expect(events[measured + 1].hasPrefix("ad"), "Measured before the commercial loaded: \(events)")
        #expect(events[(measured + 1)...].allSatisfy { $0.hasSuffix("at \(StreamingQuality.maximumBitrate)") }, "\(events)")
        player.stop()
    }
}

/// A file a player can't show.
private struct UnplayableFile: Error {}
