import Foundation
import Testing
@testable import GregularCore

struct ScheduleCodeTests {
    @Test func formatsAsTwoGroupsOfFive() {
        #expect(ScheduleCode.standard.description == "00000-00000")
        #expect(ScheduleCode(value: (1 << 50) - 1)!.description == "ZZZZZ-ZZZZZ")
    }

    @Test func codeAndValueAreOneToOne() {
        var rng = SeededRandom(seed: 5)
        for _ in 0..<1000 {
            let value = rng.next() >> 14   // 50 bits
            let code = ScheduleCode(value: value)!
            #expect(ScheduleCode(code.description)?.value == value)
        }
    }

    @Test func typingIsForgiving() {
        let code = ScheduleCode("7KQM2-X9PDA")!
        #expect(ScheduleCode("7kqm2x9pda") == code)
        #expect(ScheduleCode(" 7KQM2 X9PDA ") == code)
        #expect(ScheduleCode("O0000-00000") == ScheduleCode("00000-00000"))
        #expect(ScheduleCode("I0000-L0000") == ScheduleCode("10000-10000"))
    }

    @Test(arguments: ["", "12345", "7KQM2-X9PDAX", "7KQM2-X9PD!", "UUUUU-UUUUU"])
    func rejectsInvalidCodes(text: String) {
        #expect(ScheduleCode(text) == nil)
    }

    @Test func valuesOutsideFiftyBitsAreRejected() {
        #expect(ScheduleCode(value: 1 << 50) == nil)
    }

    @Test func eachChannelGetsItsOwnKey() {
        let code = ScheduleCode("7KQM2-X9PDA")!
        let keys = (1...14).map { code.key(forChannelSeed: UInt64($0)) }
        #expect(Set(keys).count == keys.count)
        #expect(code.key(forChannelSeed: 3) == ScheduleCode("7KQM2-X9PDA")!.key(forChannelSeed: 3))
        #expect(code.key(forChannelSeed: 3) != ScheduleCode("7KQM2-X9PDB")!.key(forChannelSeed: 3))
    }
}

struct ShuffledShowsTests {
    let episodes = Fixtures.library.filter { $0.kind == .episode }   // Alpha 10, Bravo 3, Charlie 12

    private func pull(_ count: Int, from items: [MediaItem], position: Int = 0, key: UInt64 = 42) -> [MediaItem] {
        let stream = ShuffledShows().programmes(from: ChannelContent(items: items, seed: key), startingAt: position,
                                                rng: SeededRandom(seed: key))
        return (0..<count).compactMap { _ in stream.next() }
    }

    @Test func firstPassPlaysEachShowOnce() {
        let shows = Set(Fixtures.library.map(\.seriesKey))
        #expect(Set(pull(shows.count, from: Fixtures.library).map(\.seriesKey)) == shows)
    }

    @Test func episodesOnlyIncreaseWithinARun() {
        // Pull many programmes, from several keys and positions.
        for key: UInt64 in [1, 2, 3, 99] {
            for position in [0, 7, 40] {
                let stream = pull(60, from: episodes, position: position, key: key)
                for show in Set(stream.map(\.seriesKey)) {
                    let numbers = stream.filter { $0.seriesKey == show }
                        .map { ($0.seasonNumber!, $0.episodeNumber!) }
                    #expect(Self.forwardsOrBackToPilot(numbers), "\(show) went backwards")
                }
            }
        }
    }

    @Test func showsAdvanceOneEpisodePerPass() {
        let alpha = pull(15, from: episodes).filter { $0.seriesName == "Alpha" }
        #expect(alpha.prefix(3).map(\.id) == ["Alpha-s1e1", "Alpha-s1e2", "Alpha-s1e3"])
    }

    @Test func afterTheFinalEpisodeItCyclesBackToThePilot() {
        let show = Fixtures.series("Tiny", seasons: 1, episodes: 3)
        #expect(pull(7, from: show).map(\.episodeNumber) == [1, 2, 3, 1, 2, 3, 1])
    }

    /// Each step goes forwards, except a jump back to the pilot (S1E1 in these fixtures).
    static func forwardsOrBackToPilot(_ numbers: [(Int, Int)]) -> Bool {
        zip(numbers, numbers.dropFirst()).allSatisfy { $0 < $1 || $1 == (1, 1) }
    }

    @Test func eachPassIsANewOrder() {
        let movies = (0..<6).map { Fixtures.movie("M\($0)") }
        let stream = pull(6 * 30, from: movies).map(\.id)
        let passes = stride(from: 0, to: stream.count, by: 6).map { Array(stream[$0..<$0 + 6]) }
        #expect(passes.allSatisfy { Set($0).count == 6 }, "Every show once per pass")
        #expect(Set(passes).count > 10, "The order changes from pass to pass")
    }

    @Test func moviesCanRepeat() {
        let movies = [Fixtures.movie("One"), Fixtures.movie("Two")]
        #expect(pull(6, from: movies).count == 6)
    }
}

struct UniversalScheduleTests {
    let lineup = try! ChannelLineup.bundled()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func lineUps(_ code: ScheduleCode) -> [[String]] {
        lineup.schedules(for: Fixtures.library, code: code).map { schedule in
            schedule.airings(from: now, to: now.addingTimeInterval(6 * 3600)).map(\.item.id)
        }
    }

    @Test func sameCodeGivesTheSameScheduleOnEveryChannel() {
        let code = ScheduleCode("7KQM2-X9PDA")!
        #expect(lineUps(code) == lineUps(ScheduleCode("7kqm2-x9pda")!))
    }

    @Test func differentCodesGiveDifferentSchedules() {
        #expect(lineUps(ScheduleCode("7KQM2-X9PDA")!) != lineUps(ScheduleCode("00000-00001")!))
    }

    @Test func withinEveryRunEpisodesOnlyIncrease() throws {
        let episodes = Fixtures.library.filter { $0.kind == .episode }
        let schedule = try #require(ChannelSchedule(channel: Fixtures.channel(strategy: ShuffledShows.id),
                                                    items: episodes, code: ScheduleCode("7KQM2-X9PDA")!))
        var day = schedule.run(containing: now)
        for _ in 0..<5 {
            let run = schedule.airings(from: day.start, to: day.end.addingTimeInterval(-1))
                .filter { !$0.isFiller && $0.start >= day.start }
            defer { day = schedule.run(containing: day.end) }
            for show in Set(run.map(\.item.seriesKey)) {
                let numbers = run.filter { $0.item.seriesKey == show }.map { ($0.item.seasonNumber!, $0.item.episodeNumber!) }
                #expect(ShuffledShowsTests.forwardsOrBackToPilot(numbers))
            }
        }
    }

    @Test func oneCodeGivesEachChannelItsOwnOrder() {
        let code = ScheduleCode("7KQM2-X9PDA")!
        let orders = lineup.channels.map { channel in
            let order = ShuffledOrder.Passes(count: 40, seed: code.key(forChannelSeed: channel.seed))
            return (0..<40).map(order.index(at:))
        }
        #expect(Set(orders).count == orders.count)
    }
}

struct ShuffledOrderTests {
    static let counts = [1, 2, 3, 7, 10, 11, 12, 40, 115, 1_000]

    @Test(arguments: counts)
    func coversEveryIndexExactlyOnce(count: Int) {
        let order = ShuffledOrder(count: count, seed: 9)
        #expect((0..<count).map(order.index(at:)).sorted() == Array(0..<count))
    }

    @Test func upToTenIsAFisherYatesShuffle() {
        for count in 1...ShuffledOrder.fisherYatesLimit {
            var rng = SeededRandom(seed: 4)
            let expected = rng.shuffled(Array(0..<count))
            #expect((0..<count).map(ShuffledOrder(count: count, seed: 4).index(at:)) == expected)
        }
    }

    @Test func aboveTenIsTheFeistelShuffle() {
        let order = ShuffledOrder(count: 11, seed: 4), feistel = LazyPermutation(count: 11, seed: 4)
        #expect((0..<11).map(order.index(at:)) == (0..<11).map(feistel.index(at:)))
    }

    @Test func isDeterministicAndSeedDependentAndWraps() {
        for count in [8, 50] {
            let a = (0..<count).map(ShuffledOrder(count: count, seed: 1).index(at:))
            #expect(a == (0..<count).map(ShuffledOrder(count: count, seed: 1).index(at:)))
            #expect(a != (0..<count).map(ShuffledOrder(count: count, seed: 2).index(at:)))
            let order = ShuffledOrder(count: count, seed: 1)
            #expect(order.index(at: count + 2) == order.index(at: 2))
            #expect(order.index(at: -1) == order.index(at: count - 1))
        }
    }

    @Test func everyOrderOfSixIsEquallyLikely() {
        // 72,000 seeds over 720 orders: about 100 each. A fair shuffle stays
        // well inside 50...160; the old 4-round Feistel went from 20 to 600.
        var counts: [[Int]: Int] = [:]
        for seed in 0..<72_000 {
            let order = ShuffledOrder(count: 6, seed: SeededRandom.mix(UInt64(seed)))
            counts[(0..<6).map(order.index(at:)), default: 0] += 1
        }
        #expect(counts.count == 720)
        #expect(counts.values.allSatisfy { (50...160).contains($0) }, "\(counts.values.min()!)...\(counts.values.max()!)")
    }

    @Test func twelveItemsLandEvenlyAcrossPositions() {
        // Just above the Fisher–Yates limit, the Feistel shuffle's weakest size.
        // How often each item lands at each position, over 60,000 seeds, as a
        // chi-square score per degree of freedom: about 1 if even. 4 rounds scored about 160.
        var table = [[Int]](repeating: [Int](repeating: 0, count: 12), count: 12)
        for seed in 0..<60_000 {
            let order = ShuffledOrder(count: 12, seed: SeededRandom.mix(UInt64(seed)))
            for position in 0..<12 { table[position][order.index(at: position)] += 1 }
        }
        let expected = 60_000.0 / 12
        let chiSquare = table.joined().map { pow(Double($0) - expected, 2) / expected }.reduce(0, +)
        #expect(chiSquare / Double(12 * 11) < 1.5, "\(chiSquare / Double(12 * 11))")
    }
}

struct ShuffledOrderPassesTests {
    @Test(arguments: ShuffledOrderTests.counts)
    func everyPassYieldsEveryIndexOnce(count: Int) {
        let passes = ShuffledOrder.Passes(count: count, seed: 3)
        for pass in [-2, 0, 1, 5] {
            let indices = (pass * count..<(pass + 1) * count).map(passes.index(at:))
            #expect(indices.sorted() == Array(0..<count))
            #expect(passes.pass(of: pass * count) == pass)
        }
    }

    @Test func eachPassIsShuffledAfresh() {
        let passes = ShuffledOrder.Passes(count: 12, seed: 3)
        let orders = (0..<10).map { pass in (0..<12).map { passes.index(at: pass * 12 + $0) } }
        #expect(Set(orders).count == 10)
    }

    /// What closes one pass never opens the next: every index comes round
    /// again at least half a pass after it last did, across many passes.
    @Test(arguments: ShuffledOrderTests.counts)
    func everyIndexWaitsAtLeastHalfAPass(count: Int) {
        let passes = ShuffledOrder.Passes(count: count, seed: 3)
        var last: [Int: Int] = [:]
        var shortest = Int.max
        for position in (-2 * count)..<(6 * count) {
            let index = passes.index(at: position)
            if let before = last[index] { shortest = min(shortest, position - before) }
            last[index] = position
        }
        #expect(shortest >= max(1, count / 2), "came round again after \(shortest) of \(count)")
    }

    @Test func oneItemJustRepeats() {
        let passes = ShuffledOrder.Passes(count: 1, seed: 3)
        #expect((-2..<5).map(passes.index(at:)).allSatisfy { $0 == 0 })
    }
}

struct LazyPermutationTests {
    @Test(arguments: [1, 2, 3, 5, 16, 17, 100, 1_000])
    func coversEveryIndexExactlyOnce(count: Int) {
        let permutation = LazyPermutation(count: count, seed: 9)
        let indices = (0..<count).map { permutation.index(at: $0) }
        #expect(indices.sorted() == Array(0..<count))
    }

    @Test func isDeterministicAndSeedDependent() {
        let a = (0..<50).map { LazyPermutation(count: 50, seed: 1).index(at: $0) }
        #expect(a == (0..<50).map { LazyPermutation(count: 50, seed: 1).index(at: $0) })
        #expect(a != (0..<50).map { LazyPermutation(count: 50, seed: 2).index(at: $0) })
        #expect(a != Array(0..<50), "Actually shuffled")
    }

    @Test func positionsWrap() {
        let p = LazyPermutation(count: 7, seed: 3)
        #expect(p.index(at: 9) == p.index(at: 2))
        #expect(p.index(at: -1) == p.index(at: 6))
    }
}
