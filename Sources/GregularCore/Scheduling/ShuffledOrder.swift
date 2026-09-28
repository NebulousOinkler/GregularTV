/// A shuffled order of `0..<count`, readable at any position. Every shuffle
/// in the schedule goes through it.
///
/// - **Up to `fisherYatesLimit` items:** a Fisher–Yates shuffle, worked out
///   in full (at most 10 numbers). Every order is exactly as likely.
/// - **More:** `LazyPermutation`, which reads any position without building
///   the order, so libraries of thousands cost nothing extra. A Feistel
///   shuffle can't be exactly even over so few numbers, which is why small
///   orders use Fisher–Yates.
///
/// Positions wrap, so any integer works. Deterministic for a given seed.
public struct ShuffledOrder: Sendable {
    /// The most items shuffled with Fisher–Yates; above it, `LazyPermutation`.
    public static let fisherYatesLimit = 10

    public let count: Int
    private let order: Order

    private enum Order: Sendable {
        case built([Int])
        case lazy(LazyPermutation)
    }

    public init(count: Int, seed: UInt64) {
        precondition(count > 0, "count must be positive")
        self.count = count
        if count <= Self.fisherYatesLimit {
            var rng = SeededRandom(seed: seed)
            order = .built(rng.shuffled(Array(0..<count)))
        } else {
            order = .lazy(LazyPermutation(count: count, seed: seed))
        }
    }

    /// The index at `position`.
    public func index(at position: Int) -> Int {
        switch order {
        case .built(let indices): indices[ChannelContent.wrap(position, count)]
        case .lazy(let permutation): permutation.index(at: position)
        }
    }
}

extension ShuffledOrder {
    /// Pass after pass through `0..<count`, in a new shuffle each pass, seeded
    /// by `seed` and the pass number. Position `p` is in pass `⌊p / count⌋`,
    /// so every pass yields each index once. (What may follow what across a
    /// pass boundary is up to the `SequenceRule`s.)
    public struct Passes: Sendable {
        public let count: Int
        private let seed: UInt64

        public init(count: Int, seed: UInt64) {
            precondition(count > 0, "count must be positive")
            self.count = count
            self.seed = seed
        }

        /// Which pass `position` falls in.
        public func pass(of position: Int) -> Int {
            ChannelContent.pass(position, count)
        }

        /// The index at `position`.
        public func index(at position: Int) -> Int {
            var rng = SeededRandom(seed: seed, cycle: pass(of: position))
            return ShuffledOrder(count: count, seed: rng.next()).index(at: position)
        }
    }
}
