import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// Commercials play as their programme does: at its cap (the quality
/// setting, its fix, or Auto's measurement) and with its stereo sound, but
/// not in the add-on player; their trouble asks for less within their break
/// only. On decks with no video.
@MainActor @Suite(.serialized)
struct CommercialCapTests {
    private let ads = (1...10).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 60) }

    /// A 50-minute film in an hour's slot, its break after it: `elapsed` seconds into the slot.
    private func filmAndBreak(_ streams: FakeStreams, elapsed: TimeInterval, quality: StreamingQuality = .auto) throws -> ChannelPlayer {
        let film = MediaItem(id: "m1", kind: .movie, name: "Film", duration: 50 * 60)
        let channels = try ChannelSchedule.testing([1], epoch: Date.now.addingTimeInterval(-elapsed), padTo: 60,
                                                   items: [film], ads: ads)
        return ChannelPlayer(schedule: channels[0], streams: streams, quality: quality, decks: FakeDeck.pair())
    }

    /// The events after the first that matches `first`.
    private func events(_ streams: FakeStreams, after first: String) -> ArraySlice<String> {
        streams.events.drop { $0 != first }.dropFirst()
    }

    @Test func aCommercialPlaysAtTheQualitySetting() async throws {
        let streams = FakeStreams()
        let player = try filmAndBreak(streams, elapsed: 50 * 60 + 30, quality: .hd720)
        player.start()
        try await Fixture.settle(player)
        #expect(player.airing?.isFiller == true, "The test needs to start in the break")
        #expect(streams.caps.first == 4_000_000, "\(streams.events)")
        #expect(player.streamDescription?.hasPrefix("Commercial · 720p") == true, "\(player.streamDescription ?? "nothing")")
        #expect(streams.speedTests == 0)
        player.stop()
    }

    /// The viewer's 720p for the film: its break, queued before it ends, plays at 720p too.
    @Test func aBreakPlaysAtItsProgrammesFix() async throws {
        let streams = FakeStreams()
        let player = try filmAndBreak(streams, elapsed: 50 * 60 - 10)
        player.start()
        _ = try await Fixture.playingDeck(player)
        player.setProgrammeFix(.hd720)
        let ad = { self.events(streams, after: "m1 at 4000000").first { $0.hasPrefix("ad") } }
        try await waitUntil(5) { ad() != nil }
        #expect(ad()?.hasSuffix(" at 4000000") == true, "\(streams.events)")
        player.stop()
    }

    /// Stereo sound for the film carries into its break; the add-on player doesn't.
    @Test func aBreakTakesItsProgrammesStereoSoundButNotItsPlayer() async throws {
        let streams = FakeStreams(players: [.builtIn, .addOn])
        let player = try filmAndBreak(streams, elapsed: 50 * 60 - 10)
        player.start()
        _ = try await Fixture.playingDeck(player)
        #expect(player.setStereoSound(true))
        _ = try await Fixture.playingDeck(player)
        #expect(player.setPrefersAddOn(true))
        let askedBefore = streams.events.count
        let adAfter = { streams.events.indices.dropFirst(askedBefore).last { streams.events[$0].hasPrefix("ad") } }
        try await waitUntil(5) { adAfter() != nil }
        let ad = try #require(adAfter(), "\(streams.events)")
        let film = try #require(streams.events.indices.dropFirst(askedBefore).first { streams.events[$0].hasPrefix("m1") })
        #expect(streams.playersAsked[film].first == .addOn, "The film asks for VLC first")
        #expect(streams.stereoAsked[ad], "Its break keeps stereo sound")
        #expect(streams.playersAsked[ad].first == .builtIn, "Its break doesn't ask for VLC first")
        player.stop()
    }

    /// A commercial the server re-encodes fails in a film's mid-roll: the
    /// break asks for less (720p), and the film after it still plays as it is.
    @Test func aCommercialsTroubleAsksLessOfItsBreakNotItsFilm() async throws {
        let film = MediaItem(id: "m1", kind: .movie, name: "Film", duration: 100 * 60)
        // Where the mid-roll starts, on a schedule starting now.
        let layout = try ChannelSchedule.testing([1], epoch: .now, padTo: 60, items: [film], ads: ads)[0]
        let airings = layout.airings(from: .now, to: Date.now.addingTimeInterval(2 * 3600))
        let firstPart = try #require(airings.first { !$0.isFiller }, "\(airings)")
        #expect(airings.contains { !$0.isFiller && $0.mediaOffset > 0 }, "The film needs a mid-roll")
        // 30 seconds into the mid-roll.
        let channels = try ChannelSchedule.testing([1], epoch: Date.now.addingTimeInterval(-(firstPart.end.timeIntervalSinceNow + 30)),
                                                   padTo: 60, items: [film], ads: ads)
        let streams = FakeStreams(converting: Set(ads.map(\.id)))
        let player = ChannelPlayer(schedule: channels[0], streams: streams, quality: .auto, decks: FakeDeck.pair())
        player.start()
        let deck = try await Fixture.playingDeck(player)
        #expect(player.airing?.isFiller == true, "The test needs to start in the mid-roll")
        let item = try #require(deck.queue.first)
        item.failure = URLError(.networkConnectionLost)
        item.hasFailed = true
        // The clip again at 720p, and the film's next part loading after it.
        let retried = { streams.events.first { $0.hasPrefix("ad") && $0.hasSuffix(" at 4000000") } }
        let filmAfter = { retried().map { self.events(streams, after: $0).contains { $0.hasPrefix("m1") } } ?? false }
        try await waitUntil(10) { filmAfter() }
        #expect(retried() != nil, "The break asks for less: \(streams.events)")
        #expect(filmAfter(), "The film's next part loads: \(streams.events)")
        #expect(streams.events.filter { $0.hasPrefix("m1") }.allSatisfy { $0.hasSuffix("at \(StreamingQuality.maximumBitrate)") },
                "The film isn't capped by its break's trouble: \(streams.events)")
        #expect(streams.speedTests == 0, "A converted clip's trouble is the server's, not the connection's")
        player.stop()
    }
}
