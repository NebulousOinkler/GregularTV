import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// The end of a commercial break, on fake decks: the last clip ends, the Up
/// next card shows (the curtain opens for it), and the programme follows.
@MainActor @Suite(.serialized)
struct BreakEndTests {
    /// A 22-minute episode padded to 30 minutes, with 30-second clips.
    private func channel(epoch: Date) throws -> ChannelSchedule {
        let items = (1...3).map { MediaItem(id: "e\($0)", kind: .episode, name: "E\($0)", duration: 22 * 60, seriesName: "Show") }
        let ads = (0..<6).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad", duration: 30) }
        return try #require(try ChannelSchedule.testing(epoch: epoch, padTo: 30, items: items, ads: ads).first)
    }

    /// Watching that channel, tuned in `seconds` before the first break's last
    /// clip is scheduled to end (the Up next card follows it).
    private func watching(secondsBeforeTheLastClipEnds seconds: TimeInterval) async throws -> WatchModel {
        let probe = try channel(epoch: Date(timeIntervalSince1970: 0))
        let firstSlot = probe.airings(from: probe.channel.epoch, to: probe.channel.epoch.addingTimeInterval(30 * 60 - 1))
        let lastClipEnd = try #require(firstSlot.last { $0.isFiller }).end.timeIntervalSince(probe.channel.epoch)
        let schedule = try channel(epoch: Date.now.addingTimeInterval(-(lastClipEnd - seconds)))
        let surfer = ChannelSurfer(channels: [schedule], startingWith: schedule, streams: FakeStreams(),
                                   preferences: Fixture.preferences(), decks: FakeDeck.pair())
        let model = WatchModel(surfer: surfer)
        model.player.start()
        try await Fixture.settle(model.player)
        return model
    }

    @Test func theLastClipEndsIntoTheUpNextCard() async throws {
        let model = try await watching(secondsBeforeTheLastClipEnds: 3)
        let player = model.player
        #expect(player.airing?.isFiller == true, "Tuned in to the last clip")

        // The programme after the break is preloaded on standby, and the deck holds at the clip's end.
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        try await waitUntil(3) { deck.pausesAtItemEnd }
        #expect(deck.pausesAtItemEnd)

        deck.finishCurrentItem()
        try await waitUntil(4) { player.status.isBetweenProgrammes }
        guard case .betweenProgrammes = player.status else {
            Issue.record("Expected the Up next gap after the last clip, not \(player.status)")
            return player.stop()
        }
        #expect(model.statusCard != nil, "The Up next card")

        // The curtain, closed as the clip faded out, opens for the card.
        let curtain = Task { await model.runCurtain() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!model.curtain.closed)
        curtain.cancel()
        player.stop()
    }

    @Test func aLastClipRunningLateStopsAtItsScheduledEndForTheCard() async throws {
        // Join 2 s before the last clip's scheduled end. The fake deck never
        // finishes it by itself: it's running late, still playing at its end.
        let model = try await watching(secondsBeforeTheLastClipEnds: 2)
        let player = model.player
        #expect(player.airing?.isFiller == true)

        try await waitUntil(4) { player.status.isBetweenProgrammes }
        guard case .betweenProgrammes(let until) = player.status else {
            Issue.record("Expected the clip stopped for the Up next card, not \(player.status)")
            return player.stop()
        }
        #expect(until.timeIntervalSinceNow > 10, "Most of the card's 15 s is still to come")
        #expect(model.statusCard != nil, "The Up next card")
        #expect(player.decks[player.activeIndex].state == .paused, "The clip has stopped")
        player.stop()
    }

    @Test func theSoundFadesOutWithThePictureAtTheEndOfTheLastClip() async throws {
        // Join 2 s before the last clip's scheduled end; the clip itself runs on (it started late).
        let model = try await watching(secondsBeforeTheLastClipEnds: 2)
        let player = model.player
        #expect(player.volume == 1)

        let curtain = Task { await model.runCurtain() }
        try await Task.sleep(for: .seconds(2 + 0.2))
        #expect(model.curtain.closed, "The picture has faded out at the clip's scheduled end")
        #expect(player.volume == 0, "and the sound with it, though the clip is still playing")
        #expect(player.decks.allSatisfy { $0.volume == 0 })
        curtain.cancel()
        player.stop()
    }

    @Test func aClipEndingEarlyDoesntCloseTheCurtainOverTheCard() async throws {
        // Join 6 s before the last clip's scheduled end.
        let model = try await watching(secondsBeforeTheLastClipEnds: 6)
        let player = model.player
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        try await waitUntil(3) { deck.pausesAtItemEnd }

        // The fade planned for the clip's end, still waiting (as if never cancelled).
        let stale = Task { await model.runCurtain() }
        // The clip ends early, and the Up next card takes over.
        deck.finishCurrentItem()
        try await waitUntil(4) { player.status.isBetweenProgrammes }
        let card = Task { await model.runCurtain() }
        // Past the clip's scheduled end: the stale fade has had its chance.
        try await Task.sleep(for: .seconds(6.5))
        #expect(!model.curtain.closed, "The Up next card stays visible")
        stale.cancel()
        card.cancel()
        player.stop()
    }
}
