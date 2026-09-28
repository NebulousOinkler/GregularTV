import Foundation
import Testing
@testable import GregularCore

// `LazyDerangement` isn't used by the schedule any more; kept for reference, with its tests.

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
