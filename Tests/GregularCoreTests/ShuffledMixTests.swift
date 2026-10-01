import Foundation
import Testing
@testable import GregularCore

struct ShuffledMixTests {
    /// Six series of 22-minute episodes and 12 films of 100 minutes.
    let series = (0..<6).flatMap { Fixtures.series("S\($0)", seasons: 1, episodes: 8) }
    let films = (0..<12).map { Fixtures.movie("F\($0)") }

    private func pull(_ count: Int, share: Double?, position: Int = 0, seed: UInt64 = 42) -> [MediaItem] {
        let content = ChannelContent(items: series + films, seed: seed, filmSlotShare: share)
        let stream = ShuffledMix().programmes(from: content, startingAt: position, rng: SeededRandom(seed: seed))
        return (0..<count).map { _ in stream.next()! }
    }

    @Test func filmsTakeTheirShareOfSlotsInEveryBlock() {
        for share in [0.1, 0.25, 1.0 / 3, 0.5] {
            let stream = pull(400, share: share, position: 30)
            for block in stride(from: 0, to: 400, by: ShuffledMix.blockLength) {
                let filmsInBlock = stream[block..<block + ShuffledMix.blockLength].filter { $0.kind == .movie }.count
                let wanted = Double(ShuffledMix.blockLength) * share
                #expect(abs(Double(filmsInBlock) - wanted) < 1, "share \(share): \(filmsInBlock) films in a block")
            }
        }
    }

    @Test func filmSlotsMoveAboutFromBlockToBlock() {
        let places = (0..<20).map { block in
            (0..<10).filter { FilmSlots(share: 0.3, seed: 9).isFilm(block * 10 + $0) }
        }
        #expect(Set(places).count > 10, "Not a fixed beat")
        #expect((0..<200).filter { FilmSlots(share: 0.3, seed: 9).isFilm($0) }.count
                    == FilmSlots(share: 0.3, seed: 9).films(before: 200))
    }

    /// Each side keeps Shuffled Shows' order: every series once per pass of
    /// the series, advancing one episode per pass, and every film once per
    /// pass of the films.
    @Test func eachSideIsAShuffledShowsOrder() {
        let stream = pull(600, share: 0.3)
        let seriesSide = stream.filter { $0.kind == .episode }, filmSide = stream.filter { $0.kind == .movie }
        for pass in 0..<(seriesSide.count / 6) {
            let names = seriesSide[pass * 6..<(pass + 1) * 6].map(\.seriesName!)
            #expect(Set(names).count == 6, "Every series once in a pass")
            #expect(seriesSide[pass * 6..<(pass + 1) * 6].allSatisfy { $0.episodeNumber == pass % 8 + 1 })
        }
        for pass in 0..<(filmSide.count / 12) {
            #expect(Set(filmSide[pass * 12..<(pass + 1) * 12].map(\.id)).count == 12, "Every film once in a pass")
        }
    }

    @Test func readsTheSameFromAnyStartingPosition() {
        let whole = pull(300, share: 0.3)
        #expect(pull(100, share: 0.3, position: 137) == Array(whole[137..<237]))
    }

    @Test func withoutAShareItIsShuffledShows() {
        let content = ChannelContent(items: series + films, seed: 7)
        let shows = ShuffledShows().programmes(from: content, startingAt: 0, rng: SeededRandom(seed: 7))
        #expect(pull(40, share: nil, seed: 7) == (0..<40).map { _ in shows.next()! })
    }
}

struct ChannelVarietyTests {
    let slot: (MediaItem) -> Int64 = { ChannelSchedule.slotLength(of: $0, padToMinutes: 30) }

    private func variety(series: Int, films: Int) -> ChannelVariety {
        let items = (0..<series).flatMap { Fixtures.series("S\($0)", seasons: 1, episodes: 5) }
            + (0..<films).map { Fixtures.movie("F\($0)", minutes: 100) }   // 30-minute and 2-hour slots
        return ChannelVariety(shows: ChannelContent(items: items, seed: 1).series, slotLength: slot)
    }

    @Test func aChannelFillsADayWithoutRepeatingTooSoon() {
        // 48 series once a day fill one; so do 36 films once every three days.
        #expect(variety(series: 48, films: 0).fillsADay)
        #expect(!variety(series: 47, films: 0).fillsADay)
        #expect(variety(series: 0, films: 36).fillsADay)
        #expect(!variety(series: 0, films: 35).fillsADay)
        #expect(variety(series: 24, films: 18).fillsADay, "Half a day of each")
    }

    @Test func theFilmShareMovesToWhatTheLibraryCanCarry() {
        // Plenty of both: as asked.
        #expect(abs(variety(series: 100, films: 100).filmShare(wanted: 0.35) - 0.35) < 1e-9)
        // 12 series fill 6 hours a day: films take the rest.
        #expect(abs(variety(series: 12, films: 100).filmShare(wanted: 0.35) - 0.75) < 1e-9)
        // 9 films fill 6 hours a day: series take the rest.
        #expect(abs(variety(series: 100, films: 9).filmShare(wanted: 0.35) - 0.25) < 1e-9)
        #expect(variety(series: 0, films: 50).filmShare(wanted: 0.35) == 1)
        #expect(variety(series: 50, films: 0).filmShare(wanted: 0.35) == 0)
    }

    @Test func filmsTakeFewerSlotsThanTheirAirtime() {
        // 2-hour films with a third of the airtime: one slot in 9 (1:8 against 30-minute slots).
        #expect(abs(variety(series: 100, films: 100).filmSlotShare(forAirtime: 1.0 / 3) - 1.0 / 9) < 1e-9)
    }

    @Test func aThemedChannelWithoutEnoughVarietyIsHidden() {
        let items = (0..<10).flatMap { Fixtures.series("S\($0)", seasons: 1, episodes: 5) }
        let themed = Channel(number: 2, name: "T", source: AllItemsSource(), strategyID: ShuffledMix.id, seed: 1,
                             padToMinutes: 30, filmShare: 0.4, needsVariety: true)
        let catchAll = Channel(number: 1, name: "All", source: AllItemsSource(), strategyID: ShuffledMix.id, seed: 1,
                               padToMinutes: 30, filmShare: 0.4)
        #expect(ChannelSchedule(channel: themed, items: items) == nil)
        #expect(ChannelSchedule(channel: catchAll, items: items) != nil)
    }

    @Test func aFilmShareOutsideZeroToOneIsRejected() {
        let json = #"[{ "number": 1, "name": "X", "source": { "type": "all" }, "strategy": "shuffled-mix", "films": 1.5, "seed": 1 }]"#
        #expect(throws: DecodingError.self) { try ChannelLineup.load(from: Data(json.utf8)) }
    }
}
