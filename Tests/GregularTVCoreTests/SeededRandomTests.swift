import Testing
@testable import GregularTVCore

struct SeededRandomTests {
    /// Locks in the algorithm. If this fails, every channel's schedule has
    /// changed for every user, so only update these values on purpose.
    @Test func matchesReferenceSplitMix64Output() {
        var rng = SeededRandom(seed: 0)
        #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
        #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(rng.next() == 0x06C4_5D18_8009_454F)
    }

    @Test func sameSeedGivesSameSequence() {
        var a = SeededRandom(seed: 99, cycle: 3)
        var b = SeededRandom(seed: 99, cycle: 3)
        for _ in 0..<100 { #expect(a.next() == b.next()) }
    }

    @Test func differentCyclesGiveDifferentStreams() {
        var a = SeededRandom(seed: 99, cycle: 0)
        var b = SeededRandom(seed: 99, cycle: 1)
        #expect((0..<10).map { _ in a.next() } != (0..<10).map { _ in b.next() })
    }

    @Test func intBelowStaysInRangeAndHitsEveryValue() {
        var rng = SeededRandom(seed: 7)
        var seen = Set<Int>()
        for _ in 0..<1_000 {
            let v = rng.int(below: 6)
            #expect((0..<6).contains(v))
            seen.insert(v)
        }
        #expect(seen.count == 6)
    }

    @Test func doubleIsInUnitInterval() {
        var rng = SeededRandom(seed: 7)
        for _ in 0..<1_000 {
            let v = rng.double()
            #expect(v >= 0 && v < 1)
        }
    }

    @Test func shuffleIsAPermutation() {
        var rng = SeededRandom(seed: 1)
        let input = Array(0..<50)
        let output = rng.shuffled(input)
        #expect(output.sorted() == input)
        #expect(output != input)
    }
}
