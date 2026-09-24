import Foundation
import Testing
@testable import GregularTVCore

struct PrimesTests {
    @Test func knownPrimesAndComposites() {
        let primes: [UInt64] = [2, 3, 5, 7, 97, 7919, 1_000_003, 2_147_483_647, 18_446_744_073_709_551_557]
        let composites: [UInt64] = [0, 1, 4, 9, 91, 561, 1_000_001, 3_215_031_751, 18_446_744_073_709_551_615]
        #expect(primes.allSatisfy(Primes.isPrime))
        #expect(!composites.contains(where: Primes.isPrime))   // 561 and 3,215,031,751 fool weaker tests
    }

    @Test func nextPrimeIsAboveNAndWithinTwoN() {
        for n in [1, 2, 10, 100, 1000, 5555, 65_536] {
            let p = Primes.next(after: n)
            #expect(p > n && p <= 2 * n + 1 && Primes.isPrime(UInt64(p)))
        }
        #expect(Primes.next(after: 13) == 17)
    }
}

struct LazyDerangementTests {
    @Test(arguments: [1, 2, 3, 10, 115, 1000])
    func eachPassYieldsEveryNumberOnce(count: Int) {
        for key: UInt64 in [0, 1, 12345, .max] {
            let d = LazyDerangement(count: count, key: key)
            for pass in [-1, 0, 3] {
                let values = (pass * d.prime..<(pass + 1) * d.prime).compactMap(d.value(atStep:))
                #expect(values.sorted() == Array(0..<count))
            }
        }
    }

    @Test func parametersAreInRange() {
        for key: UInt64 in [0, 7, 1 << 40, .max] {
            let d = LazyDerangement(count: 115, key: key)
            #expect(d.prime == 127)
            #expect((1..<127).contains(d.a) && (1..<127).contains(d.b))
        }
    }

    @Test func matchesThePythonFormula() {
        // (a·x + b) mod p, keeping outputs below N: N = 5, p = 7, a = 3, b = 2.
        let d = LazyDerangement(count: 5, prime: 7, a: 3, b: 2)
        #expect((0..<7).map(d.value(atStep:)) == [2, nil, 1, 4, 0, 3, nil])
    }

    @Test func differentKeysGiveDifferentOrders() {
        let first = (0..<50).compactMap(LazyDerangement(count: 40, key: 1).value(atStep:))
        let second = (0..<50).compactMap(LazyDerangement(count: 40, key: 2).value(atStep:))
        #expect(first != second)
    }
}

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

struct DerangedShowsTests {
    let episodes = Fixtures.library.filter { $0.kind == .episode }   // Alpha 10, Bravo 3, Charlie 12

    private func pull(_ count: Int, from items: [MediaItem], position: Int = 0, key: UInt64 = 42) -> [MediaItem] {
        let stream = DerangedShows().programmes(from: ChannelContent(items: items, seed: key), startingAt: position,
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
        let schedule = try #require(ChannelSchedule(channel: Fixtures.channel(strategy: DerangedShows.id),
                                                    items: episodes, code: ScheduleCode("7KQM2-X9PDA")!))
        let epoch = Channel.defaultEpoch.timeIntervalSince1970
        let firstRun = floor((now.timeIntervalSince1970 - epoch) / schedule.runDuration)
        for k in 0..<5 {
            let runStart = Date(timeIntervalSince1970: epoch + (firstRun + Double(k)) * schedule.runDuration)
            let run = schedule.airings(from: runStart, to: runStart.addingTimeInterval(schedule.runDuration - 1))
                .filter { !$0.isFiller && $0.start >= runStart }
            for show in Set(run.map(\.item.seriesKey)) {
                let numbers = run.filter { $0.item.seriesKey == show }.map { ($0.item.seasonNumber!, $0.item.episodeNumber!) }
                #expect(DerangedShowsTests.forwardsOrBackToPilot(numbers))
            }
        }
    }

    @Test func oneCodeGivesEachChannelItsOwnParameters() {
        let code = ScheduleCode("7KQM2-X9PDA")!
        let derangements = lineup.channels.map {
            LazyDerangement(count: 10, key: code.key(forChannelSeed: $0.seed))
        }
        #expect(Set(derangements.map { [$0.a, $0.b] }).count > 1)
    }
}
