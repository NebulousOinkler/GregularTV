import Foundation
import Testing
@testable import GregularCore

struct ChannelConfigTests {
    /// Catches typos in hand edits of the shipped `channels.json`.
    @Test func bundledLineupLoadsAndIsValid() throws {
        let lineup = try ChannelLineup.bundled()
        #expect(lineup.channels.count >= 10)
        #expect(lineup.channels.map(\.number) == lineup.channels.map(\.number).sorted())
        for channel in lineup.channels {
            #expect(StrategyRegistry.contains(id: channel.strategyID))
            #expect(!channel.name.isEmpty)
            #expect(!channel.itemTypes.isEmpty)
        }
    }

    /// The fixture library is tiny: only the two catch-all channels, which
    /// never need variety, are on. Every themed channel needs it.
    @Test func bundledLineupHidesChannelsWithoutEnoughVariety() throws {
        let lineup = try ChannelLineup.bundled()
        let schedules = lineup.schedules(for: Fixtures.library)
        #expect(schedules.map(\.channel.name) == ["Gregular", "Movies"])
        #expect(lineup.channels.filter { !$0.needsVariety }.map(\.number) == [1, 10])
        #expect(lineup.channels.contains { $0.filmShare == nil && $0.itemTypes == [.movie] }, "Some channels are films only")
    }

    /// "Comedy or the series Bravo, but nothing tagged Christmas", nested.
    @Test func sourcesCombineWithAllOfAnyOfAndNot() throws {
        let json = #"""
        [{ "number": 9, "name": "Mix", "strategy": "shuffled-shows", "seed": 1,
           "source": { "type": "all-of", "sources": [
             { "type": "any-of", "sources": [
               { "type": "genre", "anyOf": ["Comedy"] },
               { "type": "series", "anyOf": ["Bravo"] } ] },
             { "type": "not", "source": { "type": "tag", "anyOf": ["Christmas"] } } ] } }]
        """#
        let channel = try #require(try ChannelLineup.load(from: Data(json.utf8)).channels.first)
        let names = Fixtures.library.filter(channel.accepts).map { $0.seriesName ?? $0.name }
        #expect(Set(names) == ["Alpha", "Bravo"], "Laughs is a comedy, but tagged Christmas")
        let bad = #"[{ "number": 9, "name": "X", "strategy": "shuffled-shows", "seed": 1, "source": { "type": "not", "source": { "type": "nope" } } }]"#
        #expect(throws: DecodingError.self) { try ChannelLineup.load(from: Data(bad.utf8)) }
    }

    @Test func decodesAllFields() throws {
        let json = """
        [{ "number": 9, "name": "Trek", "itemTypes": ["Episode"],
           "source": { "type": "series", "anyOf": ["alpha"] },
           "strategy": "sequential-by-series", "seed": -1, "padTo": 15,
           "epoch": "2025-06-01T00:00:00Z" }]
        """
        let channel = try #require(ChannelLineup.load(from: Data(json.utf8)).channels.first)
        #expect(channel.number == 9)
        #expect(channel.itemTypes == [.episode])
        #expect(channel.strategyID == SequentialBySeries.id)
        #expect(channel.seed == UInt64.max)
        #expect(channel.padToMinutes == 15)
        #expect(channel.epoch == ISO8601DateFormatter().date(from: "2025-06-01T00:00:00Z"))
        #expect(Fixtures.library.filter(channel.accepts).count == 10)
    }

    @Test func unknownStrategyIsRejected() {
        let json = #"[{ "number": 1, "name": "X", "source": { "type": "all" }, "strategy": "nope", "seed": 1 }]"#
        #expect(throws: DecodingError.self) { try ChannelLineup.load(from: Data(json.utf8)) }
    }

    @Test func unknownSourceTypeIsRejected() {
        let json = #"[{ "number": 1, "name": "X", "source": { "type": "nope" }, "strategy": "random-shuffle", "seed": 1 }]"#
        #expect(throws: DecodingError.self) { try ChannelLineup.load(from: Data(json.utf8)) }
    }

    @Test func duplicateNumbersAreRejected() {
        let json = """
        [{ "number": 1, "name": "A", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 1 },
         { "number": 1, "name": "B", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 2 }]
        """
        #expect(throws: ChannelLineup.LoadError.duplicateChannelNumber(1)) {
            try ChannelLineup.load(from: Data(json.utf8))
        }
    }

    // MARK: Sources

    @Test func genreMatchIsCaseInsensitive() {
        let source = GenreSource(anyOf: ["Comedy"])
        #expect(Fixtures.library.filter(source.matches).map(\.name).contains("Laughs"))
    }

    @Test func yearRangeIsInclusiveAndSkipsUnknownYears() {
        let source = YearRangeSource(from: 1962, to: 2005)
        #expect(Set(Fixtures.library.filter(source.matches).map(\.name)) == ["Old Classic", "Laughs"])
    }

    @Test func tagSourceMatches() {
        #expect(Fixtures.library.filter(TagSource(anyOf: ["christmas"]).matches).map(\.name) == ["Laughs"])
    }

    @Test func itemTypesNarrowTheSource() {
        let channel = Fixtures.channel(itemTypes: [.movie])
        #expect(Fixtures.library.filter(channel.accepts).count == 4)
    }
}
