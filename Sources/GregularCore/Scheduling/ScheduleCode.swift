/// The code that picks the whole schedule. Every channel's shuffle comes from
/// it: two Apple TVs with the same code, the same media library and the
/// same `channels.json` show the same programmes at the same time, on every channel.
///
/// Format: 10 characters of Crockford base32 (see `Crockford`), shown as
/// `XXXXX-XXXXX`. That's 50 bits. Typing is forgiving, as with every code.
///
/// From code to a channel's shuffle:
/// 1. **code ↔ `value`:** one-to-one. Every code is a different 50-bit integer, and back.
/// 2. **`value` + channel seed → channel key:** `key(forChannelSeed:)` mixes
///    them into one 64-bit intermediate integer per channel, so channels are
///    shuffled independently.
/// 3. **channel key → shuffles:** the key seeds the channel's `ShuffledOrder`s
///    (one per pass) and every other random choice on it.
public struct ScheduleCode: Sendable, Hashable, CustomStringConvertible {
    public static let length = 10
    public static let bits = 50

    public let value: UInt64

    /// The code used when none has been chosen (tests, previews).
    public static let standard = ScheduleCode(value: 0)!

    public init?(value: UInt64) {
        guard value < (1 << Self.bits) else { return nil }
        self.value = value
    }

    /// Parses what the user typed. Nil unless it's exactly 10 valid characters.
    public init?(_ text: String) {
        guard let digits = Crockford.digits(of: text), digits.count == Self.length else { return nil }
        value = digits.reduce(0) { $0 << 5 | UInt64($1) }
    }

    /// A fresh random code, for first launch.
    public static func random() -> ScheduleCode {
        ScheduleCode(value: UInt64.random(in: 0..<(1 << bits)))!
    }

    /// `XXXXX-XXXXX`.
    public var description: String {
        Crockford.grouped((0..<Self.length).reversed().map { Crockford.alphabet[Int((value >> (5 * UInt64($0))) & 31)] })
    }

    /// Step 2: the intermediate integer for one channel, mixing this code with
    /// the channel's seed from `channels.json`. It seeds everything random on
    /// that channel: its shuffles (`ShuffledOrder`), the other strategies, and
    /// commercial breaks.
    public func key(forChannelSeed seed: UInt64) -> UInt64 {
        SeededRandom.mix(value ^ SeededRandom.mix(seed))
    }
}
