/// The code that picks the whole schedule. Every channel's shuffle comes from
/// it: two Apple TVs with the same code, the same media library and the
/// same `channels.json` show the same programmes at the same time, on every channel.
///
/// Format: 10 characters of Crockford base32 (the digits, and the letters
/// except I, L, O and U), shown as `XXXXX-XXXXX`. That's 50 bits. Typing is
/// forgiving: lower case is fine, dashes and spaces are ignored, O reads as 0,
/// and I and L read as 1.
///
/// From code to a channel's derangement:
/// 1. **code ↔ `value`:** one-to-one. Every code is a different 50-bit integer, and back.
/// 2. **`value` + channel seed → channel key:** `key(forChannelSeed:)` mixes
///    them into one 64-bit intermediate integer per channel, so channels are
///    shuffled independently.
/// 3. **channel key → (a, b):** `LazyDerangement(count:key:)` picks the prime
///    `p` from the channel's show count, then `a` and `b` in `1..<p` from the key.
public struct ScheduleCode: Sendable, Hashable, CustomStringConvertible {
    public static let length = 10
    public static let bits = 50
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public let value: UInt64

    /// The code used when none has been chosen (tests, previews).
    public static let standard = ScheduleCode(value: 0)!

    public init?(value: UInt64) {
        guard value < (1 << Self.bits) else { return nil }
        self.value = value
    }

    /// Parses what the user typed. Nil unless it's exactly 10 valid characters.
    public init?(_ text: String) {
        var value: UInt64 = 0
        var digits = 0
        for character in text.uppercased() {
            if character == "-" || character == " " { continue }
            let normalized: Character = switch character {
            case "O": "0"
            case "I", "L": "1"
            default: character
            }
            guard let digit = Self.alphabet.firstIndex(of: normalized) else { return nil }
            value = value << 5 | UInt64(digit)
            digits += 1
        }
        guard digits == Self.length else { return nil }
        self.value = value
    }

    /// A fresh random code, for first launch.
    public static func random() -> ScheduleCode {
        ScheduleCode(value: UInt64.random(in: 0..<(1 << bits)))!
    }

    /// `XXXXX-XXXXX`.
    public var description: String {
        let characters = (0..<Self.length).reversed().map { i in
            Self.alphabet[Int((value >> (5 * UInt64(i))) & 31)]
        }
        return String(characters.prefix(5)) + "-" + String(characters.suffix(5))
    }

    /// Step 2: the intermediate integer for one channel, mixing this code with
    /// the channel's seed from `channels.json`. It seeds everything random on
    /// that channel: the derangement's (a, b), the other strategies, and
    /// commercial breaks.
    public func key(forChannelSeed seed: UInt64) -> UInt64 {
        SeededRandom.mix(value ^ SeededRandom.mix(seed))
    }
}
