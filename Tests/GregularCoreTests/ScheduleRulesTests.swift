import Foundation
import Testing
@testable import GregularCore

struct ScheduleRulesTests {
    let epoch = Channel.defaultEpoch

    @Test func everyRuleIsRegisteredOnceWithASummary() {
        let ids = ScheduleRules.all.map { $0.id }
        #expect(Set(ids).count == ids.count)
        #expect(ScheduleRules.all.allSatisfy { !$0.summary.isEmpty })
        #expect(ScheduleRules.rules(of: (any SequenceRule).self).count == 2)
        #expect(ScheduleRules.rules(of: (any PinRule).self).count == 1)
        #expect(ScheduleRules.rules(of: (any ContentRule).self).count == 1)
        #expect(ScheduleRules.rules(of: (any ChannelRule).self).count == 1)
        #expect(ScheduleRules.rules(of: (any LineupRule).self).count == 1)
    }

    /// Two weeks of whole programmes, across many runs.
    private func fortnight(_ items: [MediaItem], strategy: String, padTo: Int? = 30) throws -> [Airing] {
        let s = try #require(ChannelSchedule(channel: Fixtures.channel(strategy: strategy, padTo: padTo), items: items))
        let start = epoch.addingTimeInterval(40 * 24 * 3600)
        return s.programmes(from: start, to: start.addingTimeInterval(14 * 24 * 3600))
    }

    @Test(arguments: [RandomShuffle.id, ShuffledShows.id, SeriesRoundRobin.id])
    func theSameMovieNeverAirsTwiceInARow(strategy: String) throws {
        // Three movies: new shuffles each pass would often repeat one where passes meet.
        let movies = ["One", "Two", "Three"].map { Fixtures.movie($0, minutes: 95) }
        let programmes = try fortnight(movies, strategy: strategy)
        #expect(programmes.count > 100)
        #expect(zip(programmes, programmes.dropFirst()).allSatisfy { $0.item.id != $1.item.id })
    }

    @Test func aShowMayFollowItselfWithAnotherEpisode() throws {
        let shows = Fixtures.series("A", seasons: 2, episodes: 10) + Fixtures.series("B", seasons: 2, episodes: 10)
        let programmes = try fortnight(shows, strategy: ShuffledShows.id)
        let pairs = Array(zip(programmes, programmes.dropFirst()))
        #expect(pairs.contains { $0.item.seriesKey == $1.item.seriesKey }, "Allowed, and it happens")
        #expect(pairs.allSatisfy { $0.item.id != $1.item.id }, "Never the same episode")
    }

    @Test func aChannelWithOneMovieStillPlaysIt() throws {
        let programmes = try fortnight([Fixtures.movie("Only")], strategy: ShuffledShows.id)
        #expect(programmes.count > 100 && programmes.allSatisfy { $0.item.name == "Only" })
    }

    @Test func aHeldBackItemAirsAsSoonAsItMay() {
        let items = ["A", "A", "B", "C"].map { Fixtures.movie($0) }
        var stream = RuledStream(AnyIterator(items.makeIterator()), for: .programmes)
        var aired: [String] = []
        while let item = stream.next() {
            stream.aired(item)
            aired.append(item.name)
        }
        #expect(aired == ["A", "B", "A", "C"], "Nothing dropped, and moved as little as possible")
    }

    @Test func itemsPutBackComeFirstInOrder() {
        let items = ["A", "B", "C", "D"].map { Fixtures.movie($0) }
        var stream = RuledStream(AnyIterator(items.makeIterator()), for: .programmes)
        let first = stream.next()!, second = stream.next()!
        stream.putBack([first, second])
        #expect((0..<4).compactMap { _ in stream.next()?.name } == ["A", "B", "C", "D"])
    }
}
