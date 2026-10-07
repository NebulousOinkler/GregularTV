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
    /// so every pass yields each index once.
    ///
    /// **Halves.** Every pass is split the same way: one half of the indices
    /// (picked once from `seed`, `halves`) is shuffled into its first half,
    /// the rest into its second. So what closed one pass never opens the
    /// next, and every index comes round again at least half a pass after
    /// it last did. (Until 2026-10-07 passes were independent, so an index
    /// near the end of one pass could come straight back early in the next:
    /// a film seen a few days before.) Each pass on its own is still an even
    /// shuffle: a random half first, and each half in a random order.
    public struct Passes: Sendable {
        public let count: Int
        private let seed: UInt64
        /// How many indices open every pass: the first `opening` of `halves`.
        private let opening: Int
        /// Which indices open every pass, and which close it.
        private let halves: ShuffledOrder

        public init(count: Int, seed: UInt64) {
            precondition(count > 0, "count must be positive")
            self.count = count
            self.seed = seed
            opening = count / 2
            var rng = SeededRandom(seed: seed ^ Self.halvesSalt)
            halves = ShuffledOrder(count: count, seed: rng.next())
        }

        /// Keeps the split's seed apart from the passes' own.
        private static let halvesSalt: UInt64 = 0x4A1F_5E7D

        /// Which pass `position` falls in.
        public func pass(of position: Int) -> Int {
            ChannelContent.pass(position, count)
        }

        /// The index at `position`.
        public func index(at position: Int) -> Int {
            let pass = pass(of: position)
            let offset = position - pass * count
            var rng = SeededRandom(seed: seed, cycle: pass)
            let openingSeed = rng.next(), closingSeed = rng.next()
            if offset < opening {
                return halves.index(at: ShuffledOrder(count: opening, seed: openingSeed).index(at: offset))
            }
            return halves.index(at: opening + ShuffledOrder(count: count - opening, seed: closingSeed).index(at: offset - opening))
        }
    }
}
