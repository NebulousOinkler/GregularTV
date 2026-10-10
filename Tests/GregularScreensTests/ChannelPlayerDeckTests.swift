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

    /// A stream for the device's add-on player is queued for it.
    @Test func theDeckPlaysEachStreamOnThePlayerItSays() async throws {
        let player = try Fixture.surfer(streams: FakeStreams(players: [.builtIn, .addOn])).player
        player.tune()
        let deck = try await Fixture.playingDeck(player)
        #expect(deck.queue.first?.player == .addOn)
        player.stop()
    }

    /// A programme goes to the add-on player first. When that fails, it's
    /// tried again at once on the device's own player, with no failure
    /// shown; the next programme goes back to the add-on player.
    @Test func whatTheAddOnPlayerFailsOnPlaysOnTheBuiltInOne() async throws {
        let streams = FakeStreams(players: [.builtIn, .addOn])
        // The next programme is asked for 30 seconds before this one ends: a few seconds from now.
        let player = try Fixture.surfer(elapsed: 3600 - 38, streams: streams).player
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let failed = try #require(deck.queue.first)
        #expect(failed.player == .addOn)
        failed.hasFailed = true
        try await waitUntil(3) { deck.queue.first.map { $0 !== failed && $0.player == .builtIn } ?? false }
        #expect(!player.status.isFailed && streams.playersAsked == [[.addOn, .builtIn], [.builtIn]])
        #expect(player.streamDescription?.contains("second-choice player") == true)

        // The next programme, queued before this one ends, is the add-on player's again.
        try await waitUntil(15) { streams.playersAsked.count == 3 }
        #expect(streams.playersAsked.last == [.addOn, .builtIn])
        player.stop()
    }

    /// A commercial goes to the device's own player first, which goes from
    /// clip to clip by itself, so a break doesn't open an add-on player for
    /// each. When that fails, the add-on player has it at once.
    @Test func aCommercialTriesTheBuiltInPlayerFirst() async throws {
        let film = MediaItem(id: "m1", kind: .movie, name: "Film", duration: 50 * 60)
        let ads = (1...5).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 60) }
        // 10 seconds into the break after the film: the next clip is asked for 20 seconds from now.
        let channels = try ChannelSchedule.testing([1], epoch: Date.now.addingTimeInterval(-(50 * 60 + 10)), padTo: 60,
                                                   items: [film], ads: ads)
        let streams = FakeStreams(players: [.builtIn, .addOn])
        let surfer = ChannelSurfer(channels: channels, startingWith: channels[0], streams: streams,
                                   preferences: AppPreferences.testing(), decks: FakeDeck.pair())
        let player = surfer.player
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let failed = try #require(deck.queue.first)
        #expect(player.airing?.isFiller == true && failed.player == .builtIn)
        #expect(streams.playersAsked.first == [.builtIn, .addOn])
        failed.hasFailed = true
        try await waitUntil(3) { deck.queue.first.map { $0 !== failed && $0.player == .addOn } ?? false }
        #expect(!player.status.isFailed && streams.playersAsked.contains([.addOn]))
        player.stop()
    }

    /// With only its own player, there's nothing to switch to: a failure
    /// is a failure, retried after a pause.
    @Test func withOnePlayerAFailureIsRetriedAsBefore() async throws {
        let streams = FakeStreams()
        let player = try Fixture.surfer(streams: streams).player
        player.start()
        let deck = try await Fixture.playingDeck(player)
        deck.queue.first?.hasFailed = true
        try await waitUntil(3) { player.status.isFailed }
        #expect(streams.playersAsked == [[.builtIn]])
        player.stop()
    }

    /// The server hears the player still wants the stream it's converting,
    /// so it doesn't stop once the player has buffered enough; not while
    /// paused, which can last hours.
    @Test func theServerIsToldItsConversionIsStillWanted() async throws {
        let interval = ChannelPlayer.keepAliveInterval
        ChannelPlayer.keepAliveInterval = 0   // every heartbeat
        defer { ChannelPlayer.keepAliveInterval = interval }
        let streams = FakeStreams(streaming: true)
        let player = try Fixture.surfer(streams: streams).player
        player.start()
        try await Fixture.settle(player)
        try await waitUntil(3) { streams.keptAlive.count >= 2 }
        #expect(Set(streams.keptAlive).count == 1 && streams.keptAlive[0].hasPrefix("session-"), "The one stream it holds")

        player.togglePause()
        try await Task.sleep(for: .milliseconds(200))   // one already on its way
        let whilePaused = streams.keptAlive.count
        try await Task.sleep(for: .seconds(1.5))
        #expect(streams.keptAlive.count == whilePaused, "Not while paused")
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

    /// Over a minute behind live, the player jumps back. A programme the
    /// server re-encodes comes back asking for less work (720p): the server
    /// couldn't keep up. One sent as it is comes back the same.
    @Test func fallingBehindLiveAsksTheServerForLessOnlyWhenItReencodes() async throws {
        let headStart = ChannelPlayer.transcodeHeadStart
        ChannelPlayer.transcodeHeadStart = 0   // play a re-encode at once
        defer { ChannelPlayer.transcodeHeadStart = headStart }
        for reencodes in [true, false] {
            let streams = FakeStreams(converting: reencodes ? ["m1", "m2", "m3"] : [])   // whichever film is on
            let player = try Fixture.surfer(streams: streams).player
            player.start()
            let deck = try await Fixture.playingDeck(player)
            deck.position -= ChannelPlayer.maxDriftBehindLive + 30
            try await waitUntil(3) { streams.caps.count == 2 }
            #expect(streams.caps == [10_000_000, reencodes ? 4_000_000 : 10_000_000])
            #expect(player.programmeFix == (reencodes ? .hd720 : .standard))
            player.stop()
        }
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
