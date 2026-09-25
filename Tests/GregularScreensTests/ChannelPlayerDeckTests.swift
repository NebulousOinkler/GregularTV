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
        try await Fixture.settle(player)
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        let item = try #require(deck.queue.first)
        #expect(player.status == .playing && deck.state == .playing)
        #expect(item.start == 0 && item.end == 3600, "The whole film, stopping at its scheduled end")
        #expect(abs((deck.seeks.last ?? 0) - 600) < 2, "Joined live, 10 minutes in")
        player.stop()
        #expect(deck.queue.isEmpty && deck.state == .paused)
    }

    @Test func aFailedStreamIsRetriedNotTreatedAsFinished() async throws {
        let surfer = try Fixture.surfer()
        let player = surfer.player
        player.start()
        try await Fixture.settle(player)
        let deck = try #require(player.decks[player.activeIndex] as? FakeDeck)
        deck.queue.first?.hasFailed = true
        for _ in 0..<300 {
            if case .failed = player.status { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .failed = player.status else {
            Issue.record("Expected a failure and a retry, not \(player.status)")
            return
        }
        player.stop()
    }
}
