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

    @Test func bundledLineupHidesChannelsWithNoContent() throws {
        let schedules = try ChannelLineup.bundled().schedules(for: Fixtures.library)
        let names = Set(schedules.map(\.channel.name))
        #expect(names.contains("All TV"))
        #expect(names.contains("Sci-Fi"))
        #expect(names.contains("Classics"))
        #expect(!names.contains("Reality"))
        #expect(!names.contains("Documentary"))
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
