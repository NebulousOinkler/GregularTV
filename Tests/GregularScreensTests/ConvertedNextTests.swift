import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// A programme straight after this one that the server converts starts
/// buffering on the spare deck well before it airs, so the server gets
/// ahead of it; one it sends as it is waits for the usual 30 s.
@MainActor @Suite(.serialized)
struct ConvertedNextTests {
    /// 80 s before the end of the first of two hour-long films, back to back
    /// (inside `convertedNextLead`, outside `prepareNextLead`), with the
    /// server's streams made by `streams` from this film's and the next one's IDs.
    private func player(_ streams: (_ now: String, _ next: String) -> FakeStreams) throws -> (ChannelPlayer, FakeStreams, next: String) {
        let items = (1...2).map { MediaItem(id: "m\($0)", kind: .movie, name: "Film \($0)", duration: 3600) }
        let schedule = try #require(try ChannelSchedule.testing(epoch: Date.now.addingTimeInterval(-(3600 - 80)), items: items).first)
        let now = try #require(schedule.tune(at: .now).airing)
        let next = try #require(schedule.airings(from: now.slotEnd, to: now.slotEnd.addingTimeInterval(1)).first)
        let fake = streams(now.item.id, next.item.id)
        return (ChannelPlayer(schedule: schedule, streams: fake, quality: .maximum, decks: FakeDeck.pair()), fake, next.item.id)
    }

    private func asked(_ streams: FakeStreams, for id: String) -> Int {
        streams.events.filter { $0.hasPrefix(id + " at") }.count
    }

    @Test func aConvertedNextProgrammeBuffersEarlyOnTheSpareDeck() async throws {
        let (player, streams, next) = try player { _, next in FakeStreams(converting: [next]) }
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let spare = try #require(player.decks.first { $0 !== deck } as? FakeDeck)
        try await waitUntil(3) { !spare.queue.isEmpty }
        #expect(spare.queue.map(\.url.lastPathComponent) == [next], "Buffering, 80 s before it airs")
        #expect(deck.queue.count == 1 && asked(streams, for: next) == 1)
        player.stop()
    }

    @Test func oneSentAsItIsWaitsForTheUsualLead() async throws {
        let (player, streams, next) = try player { _, _ in FakeStreams() }
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let spare = try #require(player.decks.first { $0 !== deck } as? FakeDeck)
        try await waitUntil(3) { asked(streams, for: next) == 1 }
        #expect(asked(streams, for: next) == 1, "Asked early, to know it's sent as it is")
        try await Task.sleep(for: .seconds(1))
        #expect(spare.queue.isEmpty && deck.queue.count == 1, "Not buffering yet: it would take this one's bandwidth")
        player.stop()
    }

    /// Not while the server converts this one: a small server would be
    /// making two conversions for longer.
    @Test func notWhileThisOneIsConverted() async throws {
        let (player, streams, next) = try player { now, next in FakeStreams(converting: [next], soundConverting: [now]) }
        player.start()
        let deck = try await Fixture.playingDeck(player)
        let spare = try #require(player.decks.first { $0 !== deck } as? FakeDeck)
        try await Task.sleep(for: .seconds(2))
        #expect(asked(streams, for: next) == 0 && spare.queue.isEmpty)
        player.stop()
    }
}
