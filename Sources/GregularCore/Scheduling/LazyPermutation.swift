/// A shuffled order of `0..<count` that can be read at any position without
/// building it. Position 0, 1, 2… maps to a distinct index each time, and all
/// `count` positions together cover every index exactly once.
///
/// Strategies use it to shuffle thousands of items while only computing the
/// few programmes the next couple of hours need.
///
/// How it works: a 4-round Feistel network (a standard way to build a
/// bijection) over the smallest even-bit-width power of two ≥ `count`, with
/// "cycle walking": results outside `0..<count` are permuted again until they
/// land inside. Deterministic for a given seed, on every platform and Swift version.
public struct LazyPermutation: Sendable {
    public let count: Int
    private let halfBits: Int
    private let roundKeys: [UInt64]

    public init(count: Int, seed: UInt64) {
        precondition(count > 0, "count must be positive")
        var bits = 2
        while (1 << bits) < count { bits += 1 }
        if bits % 2 == 1 { bits += 1 }   // split evenly into two halves
        self.count = count
        halfBits = bits / 2
        var rng = SeededRandom(seed: seed)
        roundKeys = (0..<4).map { _ in rng.next() }
    }

    /// The index at `position`. Positions wrap, so any integer works.
    public func index(at position: Int) -> Int {
        var x = UInt64(ChannelContent.wrap(position, count))
        repeat { x = permute(x) } while x >= UInt64(count)
        return Int(x)
    }

    private func permute(_ x: UInt64) -> UInt64 {
        let mask = (UInt64(1) << halfBits) - 1
        var left = x >> halfBits
        var right = x & mask
        for key in roundKeys {
            (left, right) = (right, left ^ (SeededRandom.mix(right ^ key) & mask))
        }
        return (left << halfBits) | right
    }
}
