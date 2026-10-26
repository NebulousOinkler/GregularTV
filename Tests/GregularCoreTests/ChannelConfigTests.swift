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
    /// never need variety, are on. Every themed channel needs it, so one too
    /// thin for the library isn't shown.
    @Test func bundledLineupHidesChannelsWithoutEnoughVariety() throws {
        let lineup = try ChannelLineup.bundled()
        let schedules = lineup.schedules(for: Fixtures.library)
        #expect(schedules.map(\.channel.name) == ["Gregular", "Movies"])
        #expect(lineup.channels.filter { !$0.needsVariety }.map(\.number) == [1, 10])
        #expect(lineup.channels.contains { $0.filmShare == nil && $0.itemTypes == [.movie] }, "Some channels are films only")
    }

    /// Every themed channel keeps to its years: one unbroken run, from a
    /// first year no earlier than Silver Screen's talkies (1930), to a last
    /// year or to now.
    @Test func everyThemedChannelKeepsToItsYears() throws {
        let probes = [["Comedy"], ["Drama"], ["Animation", "Family"], ["Science Fiction"], ["Documentary"], ["Food"], []]
        for channel in try ChannelLineup.bundled().channels where channel.needsVariety {
            let kind: MediaItem.Kind = channel.itemTypes.contains(.episode) ? .episode : .movie
            let years = (1900...2026).filter { year in
                probes.contains { genres in
                    channel.accepts(MediaItem(id: "\(year)", kind: kind, name: "\(year)", duration: 1800, seriesID: "s", seriesName: "S",
                                              productionYear: year, genres: genres))
                }
            }
            let first = try #require(years.first, "\(channel.name) takes no year")
            #expect(years == Array(first...years.last!), "\(channel.name) takes years with a gap")
            #expect(first >= 1930, "\(channel.name) has no first year after 1930")
        }
    }

    /// The themed channels a programme airs on.
    private func channels(airing item: MediaItem) throws -> [String] {
        try ChannelLineup.bundled().channels.filter { $0.needsVariety && $0.accepts(item) }.map(\.name)
    }

    /// A long-running comedy airs on the channels of each episode's own era.
    @Test func anEpisodeAirsOnTheChannelsOfItsEra() throws {
        func comedy(_ year: Int) -> MediaItem { Fixtures.episode("Springfield", s: 1, e: 1, genres: ["Comedy"], year: year) }
        #expect(try channels(airing: comedy(1962)) == ["Rabbit Ears"])
        #expect(try channels(airing: comedy(1992)) == ["Primetime Gold", "Laugh Track"])
        #expect(try channels(airing: comedy(2015)) == ["Next Episode", "Punchline"])
    }

    /// The line-up is for every age: kids' channels take only what's tagged
    /// for kids or families, so a cartoon for grown-ups airs with the
    /// comedies; and horror airs only on the late, sci-fi and film channels.
    @Test func everyAgeHasItsChannels() throws {
        let adultCartoon = Fixtures.episode("Quahog", s: 1, e: 1, genres: ["Animation", "Comedy"], year: 2004)
        let cartoon = Fixtures.episode("Bedrock", s: 1, e: 1, genres: ["Animation", "Family"], year: 1985)
        let preschool = Fixtures.episode("Blocks", s: 1, e: 1, genres: ["Kids"], year: 2001)
        #expect(try channels(airing: adultCartoon) == ["Sweeps Week", "Punchline"])
        #expect(try channels(airing: cartoon) == ["Primetime Gold", "Saturday Morning", "Late Show"])
        #expect(try channels(airing: preschool) == ["After School"])
        #expect(try channels(airing: Fixtures.movie("Creature", year: 1975, genres: ["Horror"])) == ["Late Show"])
        #expect(try channels(airing: Fixtures.movie("Slasher", year: 1985, genres: ["Horror"])) == ["Late Show", "Video Store"])
        #expect(try channels(airing: Fixtures.movie("Alien", year: 1979, genres: ["Horror", "Science Fiction"])) == ["Late Show", "Sci-Fi Syndicate"])
    }

    /// The public-television channel has documentaries, and drama from
    /// British networks and film companies (its Masterpiece side), by studio.
    @Test func publicTelevisionHasBritishDramaByStudio() throws {
        func drama(_ studio: String) -> MediaItem {
            MediaItem(id: studio, kind: .episode, name: "E", duration: 3000, seriesID: studio, seriesName: studio,
                      productionYear: 2012, genres: ["Drama"], studios: [studio])
        }
        #expect(try channels(airing: drama("BBC One")) == ["Next Episode", "Viewers Like You"])
        #expect(try channels(airing: drama("bbc one")) == ["Next Episode", "Viewers Like You"], "Studios match ignoring case")
        #expect(try channels(airing: drama("NBC")) == ["Next Episode"])
        let costumeFilm = MediaItem(id: "f", kind: .movie, name: "F", duration: 7000, productionYear: 1995,
                                    genres: ["Drama", "Romance"], studios: ["Merchant Ivory Productions"])
        #expect(try channels(airing: costumeFilm).contains("Viewers Like You"))
        #expect(try channels(airing: Fixtures.movie("Wild Coasts", year: 2005, genres: ["Documentary"])).contains("Viewers Like You"))
        // How-to and cooking shows have Workshop, which plays no films.
        let cooking = Fixtures.episode("Kitchen", s: 1, e: 1, genres: ["Food"], year: 2005)
        #expect(try channels(airing: cooking).contains("Workshop"))
        #expect(try !channels(airing: Fixtures.movie("Chef", year: 2014, genres: ["Food"])).contains("Workshop"))
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
