/// A small, deterministic random number generator (SplitMix64).
///
/// Strategies must use this RNG, and only through the methods below. The
/// schedule depends on every random choice being reproducible from the
/// channel's seed. That's what lets us rebuild the same line-up on every
/// launch without storing it.
///
/// This type deliberately does *not* conform to `RandomNumberGenerator`. The
/// standard library's `shuffle(using:)` and `random(in:using:)` don't promise
/// the same results across Swift releases, and an OS update would then
/// silently reshuffle every channel.
public struct SeededRandom: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    /// Gives each run (or other numbered unit) of a channel its own independent stream.
    public init(seed: UInt64, cycle: Int) {
        state = seed ^ (UInt64(bitPattern: Int64(cycle)) &* 0xD1B5_4A32_D192_ED03)
    }

    /// The next raw 64-bit value.
    public mutating func next() -> UInt64 {
        defer { state &+= Self.golden }
        return Self.mix(state)
    }

    private static let golden: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// SplitMix64's mixer: a bijection on 64-bit integers that scatters
    /// nearby inputs far apart. Also used to derive keys and round keys
    /// (`ScheduleCode`, `LazyPermutation`), so there's one copy of the constants.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ golden
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniformly distributed integer in `0..<upperBound`.
    public mutating func int(below upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be positive")
        let bound = UInt64(upperBound)
        // Rejection sampling removes modulo bias.
        let threshold = (0 &- bound) % bound
        while true {
            let r = next()
            if r >= threshold { return Int(r % bound) }
        }
    }

    /// A uniformly distributed value in `0.0..<1.0`.
    public mutating func double() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Shuffles `array` in place (Fisher–Yates).
    public mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, int(below: i + 1))
        }
    }

    /// Returns a shuffled copy of `array`.
    public mutating func shuffled<T>(_ array: [T]) -> [T] {
        var copy = array
        shuffle(&copy)
        return copy
    }
}
