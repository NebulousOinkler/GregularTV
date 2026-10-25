import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// A programme whose sound the server converts, on decks with no video: when
/// the server can't keep up, the retry asks for less sound work, never a
/// lower bitrate, and Auto doesn't measure.
@MainActor @Suite(.serialized)
struct SoundTroubleTests {
    /// Auto, 10 minutes into an hour-long film.
    private func player(_ streams: FakeStreams) throws -> ChannelPlayer {
        let items = (1...2).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-600), items: items).first)
        return ChannelPlayer(schedule: schedule, streams: streams, quality: .auto, decks: FakeDeck.pair())
    }

    /// Falling a minute behind live, as if buffering had held it up.
    private func fallBehind(_ player: ChannelPlayer) async throws {
        let deck = try await Fixture.playingDeck(player)
        deck.seek(to: 0)
    }

    /// Stereo first; after that, it may be the connection: Auto measures.
    @Test func thenStereoThenTheConnection() async throws {
        let streams = FakeStreams(soundConverting: ["m1", "m2"])
        let player = try player(streams)
        player.start()
        try await fallBehind(player)
        try await waitUntil(3) { streams.stereoAsked.count == 2 }
        #expect(streams.stereoAsked == [false, true] && streams.speedTests == 0)
        #expect(player.stereoSound, "Settings shows it on")
        try await fallBehind(player)
        try await waitUntil(3) { streams.stereoAsked.count == 3 }
        #expect(streams.stereoAsked.last == true && streams.speedTests == 1)
        player.stop()
    }

    /// A failure asks for less sound work too, rather than measuring.
    @Test func aFailureAsksForStereo() async throws {
        let streams = FakeStreams(soundConverting: ["m1", "m2"])
        let player = try player(streams)
        player.start()
        let item = try #require(try await Fixture.playingDeck(player).queue.first)
        item.failure = URLError(.networkConnectionLost)
        item.hasFailed = true
        try await waitUntil(8) { streams.stereoAsked.count == 2 }   // retried after the first backoff
        #expect(streams.stereoAsked.last == true && streams.speedTests == 0)
        player.stop()
    }

    /// The viewer's switch, offered where there's surround to mix down.
    @Test func theViewerCanAskForStereo() async throws {
        let streams = FakeStreams()
        let player = try player(streams)
        player.start()
        _ = try await Fixture.playingDeck(player)
        #expect(player.offersStereoSound && !player.stereoSound)
        #expect(player.setStereoSound(true) && !player.setStereoSound(true))
        try await waitUntil(3) { streams.stereoAsked.count == 2 }
        #expect(streams.stereoAsked.last == true)
        player.setQuality(.hd10)
        #expect(player.stereoSound, "A quality change keeps it")
        player.switchTo(player.schedule)
        #expect(!player.stereoSound, "Another channel doesn't")
        player.stop()

        let stereoOnly = try self.player(FakeStreams(mostSoundChannels: 2))
        stereoOnly.tune()
        _ = try await Fixture.playingDeck(stereoOnly)
        #expect(!stereoOnly.offersStereoSound && !stereoOnly.setStereoSound(true))
        stereoOnly.stop()
    }
}
