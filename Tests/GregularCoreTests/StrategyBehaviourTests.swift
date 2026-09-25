import Foundation
import Testing
@testable import GregularCore

/// Each strategy's own promise, on top of the shared conformance rules.
struct StrategyBehaviourTests {
    let episodes = Fixtures.library.filter { $0.kind == .episode }   // Alpha 10, Bravo 3, Charlie 12

    private func pull<S: ScheduleStrategy>(_ type: S.Type, _ count: Int, from items: [MediaItem],
                                           position: Int = 0, seed: UInt64 = 42) -> [MediaItem] {
        let stream = S().programmes(from: ChannelContent(items: items, seed: seed), startingAt: position,
                                    rng: SeededRandom(seed: seed, cycle: 0))
        return (0..<count).compactMap { _ in stream.next() }
    }

    /// Every series' episodes appear in aired order within the output.
    private func expectEpisodesInAiredOrder(_ output: [MediaItem]) {
        for group in MediaItem.groupedBySeries(output) {
            let asPlayed = output.filter { $0.seriesKey == group[0].seriesKey }
            #expect(asPlayed == group)
        }
    }

    @Test func randomShufflePlaysEverythingOnceBeforeRepeating() {
        let n = Fixtures.library.count
        let firstPass = pull(RandomShuffle.self, n, from: Fixtures.library)
        #expect(Set(firstPass.map(\.id)).count == n)

        let twoPasses = pull(RandomShuffle.self, 2 * n, from: Fixtures.library)
        #expect(Array(twoPasses.suffix(n)) != firstPass, "Each pass is shuffled differently")
    }

    @Test func randomShuffleCanStartAnywhere() {
        let fromZero = pull(RandomShuffle.self, 20, from: Fixtures.library)
        let fromFive = pull(RandomShuffle.self, 15, from: Fixtures.library, position: 5)
        #expect(Array(fromZero.dropFirst(5)) == fromFive, "Position 5 continues the same stream")
    }

    @Test func sequentialPlaysEachSeriesStartToFinishAlphabetically() {
        let output = pull(SequentialBySeries.self, episodes.count, from: episodes)
        #expect(output.map(\.seriesName!) == Array(repeating: "Alpha", count: 10)
                + Array(repeating: "Bravo", count: 3) + Array(repeating: "Charlie", count: 12))
        expectEpisodesInAiredOrder(output)
    }

    @Test func sequentialContinuesFromPosition() {
        let output = pull(SequentialBySeries.self, 2, from: episodes, position: 10)
        #expect(output.map(\.id) == ["Bravo-s1e1", "Bravo-s1e2"])
    }

    @Test func roundRobinAlternatesSeriesInOrder() {
        let output = pull(SeriesRoundRobin.self, 9, from: episodes)
        #expect(Set(output.map(\.seriesName!)) == ["Alpha", "Bravo", "Charlie"])
        #expect(zip(output, output.dropFirst()).allSatisfy { $0.seriesKey != $1.seriesKey })
        expectEpisodesInAiredOrder(output)
    }

    @Test func roundRobinLoopsShortSeriesOnTheirOwn() {
        // Bravo has 3 episodes; by its 4th turn it's back to episode 1.
        let bravo = pull(SeriesRoundRobin.self, 12, from: episodes).filter { $0.seriesName == "Bravo" }
        #expect(bravo.map(\.episodeNumber) == [1, 2, 3, 1])
    }

    @Test func shuffledSeriesKeepsEpisodesInOrderButMixesShows() {
        let output = pull(ShuffledSeriesInOrder.self, 12, from: episodes)
        expectEpisodesInAiredOrder(output)
        #expect(Set(output.map(\.seriesName!)).count > 1)
    }

    @Test func shuffledSeriesStartsEachShowAtItsShare() {
        // At position 12 of 25, Charlie (12 episodes) has had about 12 × 12/25 ≈ 5.76 → 5 episodes.
        let charlie = pull(ShuffledSeriesInOrder.self, 30, from: episodes, position: 12)
            .first { $0.seriesName == "Charlie" }
        #expect(charlie?.id == "Charlie-s2e2")   // its 6th episode (index 5)
    }

    @Test func unnumberedEpisodesSortByAirDate() {
        func ep(_ id: String, day: Double?) -> MediaItem {
            MediaItem(id: id, kind: .episode, name: "Show", duration: 60, seriesID: "s", seriesName: "Show",
                      seasonNumber: 1975, premiereDate: day.map { Date(timeIntervalSince1970: $0 * 86_400) })
        }
        let items = [ep("c", day: 30), ep("none", day: nil), ep("a", day: 10), ep("b", day: 20)]
        #expect(items.sorted(by: MediaItem.airedOrder).map(\.id) == ["a", "b", "c", "none"])
    }

    @Test func specialsSortAfterRegularSeasons() {
        let items = [
            Fixtures.episode("Show", s: 0, e: 1),
            Fixtures.episode("Show", s: 2, e: 1),
            Fixtures.episode("Show", s: 1, e: 2),
            Fixtures.episode("Show", s: 1, e: 1),
        ]
        #expect(items.sorted(by: MediaItem.airedOrder).map(\.id)
                == ["Show-s1e1", "Show-s1e2", "Show-s2e1", "Show-s0e1"])
    }
}
