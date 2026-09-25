/// A lazy shuffle of `0..<count`, ported from `random_derangement.py`.
///
/// Steps x = 0, 1, 2… through `(a·x + b) mod p` for a prime `p > count`, and
/// keeps only the results below `count`. Because `a` isn't a multiple of `p`,
/// `x ↦ (a·x + b) mod p` is a bijection on `0..<p`. So every run of `p` steps
/// (a "pass") yields each number below `count` exactly once. Each step is O(1),
/// and `p < 2·count` (Bertrand's postulate), so it takes fewer than two steps
/// per number on average.
///
/// Changes from the Python original, so a schedule is reproducible from its code:
/// - `p` is the smallest prime above `count`, not a random prime in `(count, 2·count]`.
/// - `a` and `b` come from a key (see `ScheduleCode`), not from `random`.
/// - Miller–Rabin uses fixed bases that are exact for every 64-bit number, not random ones.
public struct LazyDerangement: Sendable, Equatable {
    public let count: Int
    public let prime: Int
    public let a: Int
    public let b: Int

    /// Derives `a` and `b`, both in `1..<p`, from `key`: `a` from its
    /// remainder and `b` from its quotient.
    public init(count: Int, key: UInt64) {
        let prime = Primes.next(after: count)
        let span = UInt64(prime - 1)
        self.init(count: count, prime: prime,
                  a: 1 + Int(key % span),
                  b: 1 + Int((key / span) % span))
    }

    public init(count: Int, prime: Int, a: Int, b: Int) {
        precondition(count > 0 && prime > count && Primes.isPrime(UInt64(prime)), "need a prime above count")
        precondition((1..<prime).contains(a) && (1..<prime).contains(b), "a and b must be in 1..<p")
        self.count = count
        self.prime = prime
        self.a = a
        self.b = b
    }

    /// The number at raw step `step`, or nil when `(a·x + b) mod p ≥ count`
    /// (that step is skipped). Steps can be any integer, including negative ones.
    public func value(atStep step: Int) -> Int? {
        let x = UInt64(ChannelContent.wrap(step, prime))
        let out = Int((Primes.mulmod(UInt64(a), x, UInt64(prime)) + UInt64(b)) % UInt64(prime))
        return out < count ? out : nil
    }

    /// Which pass step `step` belongs to. Each pass yields every number once.
    public func pass(ofStep step: Int) -> Int {
        ChannelContent.pass(step, prime)
    }
}

/// Prime search for `LazyDerangement`.
public enum Primes {
    /// Deterministic Miller–Rabin. These bases are exact for every 64-bit number.
    static let witnesses: [UInt64] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]

    public static func isPrime(_ n: UInt64) -> Bool {
        if n < 2 { return false }
        for p in witnesses {
            if n == p { return true }
            if n % p == 0 { return false }
        }
        // n - 1 = d · 2^s with d odd
        var d = n - 1
        var s = 0
        while d % 2 == 0 { d /= 2; s += 1 }

        witnessLoop: for a in witnesses {
            var x = powmod(a, d, n)
            if x == 1 || x == n - 1 { continue }
            for _ in 0..<max(0, s - 1) {
                x = mulmod(x, x, n)
                if x == n - 1 { continue witnessLoop }
            }
            return false
        }
        return true
    }

    /// The smallest prime greater than `n`.
    public static func next(after n: Int) -> Int {
        var candidate = max(2, n + 1)
        while !isPrime(UInt64(candidate)) { candidate += 1 }
        return candidate
    }

    /// `(a · b) mod m` without overflow.
    static func mulmod(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
        m.dividingFullWidth(a.multipliedFullWidth(by: b)).remainder
    }

    /// `(base ^ exponent) mod m` by repeated squaring.
    static func powmod(_ base: UInt64, _ exponent: UInt64, _ m: UInt64) -> UInt64 {
        if m == 1 { return 0 }
        var result: UInt64 = 1
        var base = base % m
        var exponent = exponent
        while exponent > 0 {
            if exponent & 1 == 1 { result = mulmod(result, base, m) }
            base = mulmod(base, base, m)
            exponent >>= 1
        }
        return result
    }
}
