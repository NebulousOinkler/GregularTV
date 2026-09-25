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
        let iso = ISO8601DateFormatter().string(from: epoch)
        let json = #"[{ "number": 1, "name": "C", "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "padTo": 30, "filler": "derangement", "epoch": "\#(iso)" }]"#
        let items = (1...3).map { MediaItem(id: "e\($0)", kind: .episode, name: "E\($0)", duration: 22 * 60, seriesName: "Show") }
        let ads = (0..<6).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad", duration: 30) }
        return try #require(try ChannelLineup.load(from: Data(json.utf8)).schedules(for: items, fillerPool: ads).first)
    }

    @Test func theLastClipEndsIntoTheUpNextCard() async throws {
        // Where the first break's last clip ends, then join 3 s before that.
        let probe = try channel(epoch: Date(timeIntervalSince1970: 0))
        let firstSlot = probe.airings(from: probe.channel.epoch, to: probe.channel.epoch.addingTimeInterval(30 * 60 - 1))
        let lastClip = try #require(firstSlot.last { $0.isFiller })
        let lastClipEnd = lastClip.end.timeIntervalSince(probe.channel.epoch)
        let schedule = try channel(epoch: Date.now.addingTimeInterval(-(lastClipEnd - 3)))

        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "BreakEndTests-\(UUID())")!)
        let surfer = ChannelSurfer(channels: [schedule], startingWith: schedule, streams: FakeStreams(),
                                   preferences: preferences, decks: FakeDeck.pair())
        let model = WatchModel(surfer: surfer)
        let player = model.player
        player.start()
        try await Fixture.settle(player)
        #expect(player.airing?.isFiller == true, "Tuned in to the last clip")

        // The programme after the break is preloaded on standby, and the deck holds at the clip's end.
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        for _ in 0..<300 where !deck.pausesAtItemEnd { try await Task.sleep(for: .milliseconds(10)) }
        #expect(deck.pausesAtItemEnd)

        deck.finishCurrentItem()
        for _ in 0..<300 {
            if case .betweenProgrammes = player.status { break }
            try await Task.sleep(for: .milliseconds(10))
        }
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

    @Test func aClipEndingEarlyDoesntCloseTheCurtainOverTheCard() async throws {
        let probe = try channel(epoch: Date(timeIntervalSince1970: 0))
        let firstSlot = probe.airings(from: probe.channel.epoch, to: probe.channel.epoch.addingTimeInterval(30 * 60 - 1))
        let lastClip = try #require(firstSlot.last { $0.isFiller })
        let lastClipEnd = lastClip.end.timeIntervalSince(probe.channel.epoch)
        // Join 6 s before the last clip's scheduled end.
        let schedule = try channel(epoch: Date.now.addingTimeInterval(-(lastClipEnd - 6)))
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: "BreakEndTests-\(UUID())")!)
        let surfer = ChannelSurfer(channels: [schedule], startingWith: schedule, streams: FakeStreams(),
                                   preferences: preferences, decks: FakeDeck.pair())
        let model = WatchModel(surfer: surfer)
        let player = model.player
        player.start()
        try await Fixture.settle(player)
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        for _ in 0..<300 where !deck.pausesAtItemEnd { try await Task.sleep(for: .milliseconds(10)) }

        // The fade planned for the clip's end, still waiting (as if never cancelled).
        let stale = Task { await model.runCurtain() }
        // The clip ends early, and the Up next card takes over.
        deck.finishCurrentItem()
        for _ in 0..<300 {
            if case .betweenProgrammes = player.status { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let card = Task { await model.runCurtain() }
        // Past the clip's scheduled end: the stale fade has had its chance.
        try await Task.sleep(for: .seconds(6.5))
        #expect(!model.curtain.closed, "The Up next card stays visible")
        stale.cancel()
        card.cancel()
        player.stop()
    }
}
