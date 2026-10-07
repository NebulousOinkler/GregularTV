import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// The player's decisions, on decks with no video: what it asks a deck to do.
@MainActor @Suite(.serialized)
struct ChannelPlayerDeckTests {
    @Test func tuningInQueuesTheProgrammeAndSeeksToLive() async throws {
        let surfer = try Fixture.surfer(elapsed: 600)
        let player = surfer.player
        player.tune()
        let deck = try await Fixture.playingDeck(player)
        let item = try #require(deck.queue.first)
        #expect(player.status == .playing && deck.state == .playing)
        #expect(item.start == 0 && item.end == 3600, "The whole film, stopping at its scheduled end")
        #expect(abs((deck.seeks.last ?? 0) - 600) < 2, "Joined live, 10 minutes in")
        player.stop()
        #expect(deck.queue.isEmpty && deck.state == .paused)
    }

    /// A commercial the device can't play as it is plays all the same,
    /// converted by the server as a programme would be, still with no cap.
    @Test func aCommercialTheServerConvertsStillPlays() async throws {
        let film = MediaItem(id: "m1", kind: .movie, name: "Film", duration: 50 * 60)
        let ads = (1...5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 60) }
        // 30 seconds into the break after the film.
        let channels = try ChannelSchedule.testing([1], epoch: Date.now.addingTimeInterval(-(50 * 60 + 30)), padTo: 60,
                                                   items: [film], ads: ads)
        let streams = FakeStreams(converting: Set(ads.map(\.id)))
        let surfer = ChannelSurfer(channels: channels, startingWith: channels[0], streams: streams,
                                   preferences: AppPreferences.testing(), decks: FakeDeck.pair())
        let player = surfer.player
        player.tune()
        let deck = try await Fixture.playingDeck(player)
        #expect(player.airing?.isFiller == true && deck.queue.first?.url.lastPathComponent.hasPrefix("ad") == true,
                "The converted clip plays, not a blank break")
        #expect(streams.caps.first == StreamingQuality.maximumBitrate, "Commercials keep their own cap")
        player.stop()
    }

    /// With "Show playback diagnostics" on, the player writes the line
    /// itself, from what the deck says it's doing.
    @Test func theDiagnosticsLineSaysWhatTheDeckIsDoing() async throws {
        let player = try Fixture.surfer(elapsed: 600).player
        player.diagnosticsEnabled = true
        player.start()
        try await Fixture.settle(player)
        try await waitUntil(2) { player.diagnostics != nil }
        let line = try #require(player.diagnostics)
        #expect(line.hasPrefix("Playing · ") && line.contains("s behind live · at 0:10:0") && line.hasSuffix("no transcoding"),
                "\(line)")
        player.diagnosticsEnabled = false
        #expect(player.diagnostics == nil)
        player.stop()
    }

    @Test func resumingSeeksToLiveWithoutLoadingAgain() async throws {
        let surfer = try Fixture.surfer(elapsed: 600)
        let player = surfer.player
        player.tune()
        let deck = try await Fixture.playingDeck(player)
        let item = try #require(deck.queue.first)
        player.togglePause()
        #expect(deck.state == .paused)
        deck.seek(to: 540)   // as if paused a minute ago
        let tunes = player.tuneCount
        player.togglePause()
        #expect(player.status == .playing && deck.state == .playing)
        #expect(player.tuneCount == tunes, "Not loaded again")
        #expect(deck.queue.first === item, "The same stream carries on")
        #expect(abs(deck.position - 600) < 2, "Back at live")
        player.stop()
    }

    /// Rebuilt channels (set times or a custom channel changed elsewhere)
    /// leave the channel playing alone; only a change to what's on it re-tunes.
    @Test func rebuiltChannelsOnlyRetuneWhatChanged() async throws {
        // Whole seconds, as channels.json keeps it, so every rebuild below has the same epoch.
        let epoch = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 600).rounded(.down))
        let items = (1...3).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let channels = try ChannelSchedule.testing([1, 2], epoch: epoch, items: items)
        let surfer = ChannelSurfer(channels: channels, startingWith: channels[0], streams: FakeStreams(),
                                   preferences: AppPreferences.testing(), decks: FakeDeck.pair())
        let player = surfer.player
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let item = try #require(deck.queue.first)
        let tunes = player.tuneCount

        // The same channels again: nothing on channel 1 changed.
        #expect(surfer.replaceChannels(try ChannelSchedule.testing([1, 2], epoch: epoch, items: items)))
        #expect(player.tuneCount == tunes && deck.queue.first === item && player.status == .playing,
                "Carried on without re-buffering")

        // Channel 2 only: a different schedule there.
        let changedTwo = try ChannelSchedule.testing([1], epoch: epoch, items: items)
            + ChannelSchedule.testing([2], epoch: epoch.addingTimeInterval(-1234), items: items)
        #expect(surfer.replaceChannels(changedTwo))
        #expect(player.tuneCount == tunes && deck.queue.first === item, "Another channel's change doesn't re-buffer this one")

        // Channel 1 itself now shows something else: it re-tunes.
        #expect(surfer.replaceChannels(try ChannelSchedule.testing([1, 2], epoch: epoch.addingTimeInterval(-1800), items: items)))
        #expect(player.tuneCount == tunes + 1)

        // Channel 1 gone: the lowest-numbered channel plays.
        #expect(surfer.replaceChannels(try ChannelSchedule.testing([2, 3], epoch: epoch, items: items)))
        #expect(player.schedule.channel.number == 2 && surfer.channels.map(\.channel.number) == [2, 3])
        #expect(!surfer.replaceChannels([]), "Nothing to watch changes nothing")
        player.stop()
    }

    @Test func aFailedStreamIsRetriedNotTreatedAsFinished() async throws {
        let surfer = try Fixture.surfer()
        let player = surfer.player
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.queue.first?.hasFailed = true
        try await waitUntil(3) { player.status.isFailed }
        guard case .failed = player.status else {
            Issue.record("Expected a failure and a retry, not \(player.status)")
            return
        }
        player.stop()
    }
}
