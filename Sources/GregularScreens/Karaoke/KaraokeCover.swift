/// A song's or album's picture, made up from its name: a pattern like a
/// record sleeve's, in two of its theme's colours, with its initials. Karaoke
/// fetches no artwork (nothing more about the library than the names), so
/// each front end draws this instead. The same name always gets the same
/// picture, on every device.
public struct KaraokeCover: Sendable, Equatable {
    public enum Pattern: String, Sendable, CaseIterable {
        /// Diagonal stripes, at `angle`.
        case stripes
        /// Rings round the middle, like a record's grooves.
        case rings
        /// Polka dots.
        case dots
        /// Rays from a corner.
        case sunburst
        /// A chequerboard.
        case checks
        /// Two halves, split at `angle`.
        case split
    }

    public let pattern: Pattern
    /// Which of its theme's cover colours go behind and in front (`0..<KaraokeCover.colourCount`; never the same).
    public let back: Int
    public let front: Int
    /// The pattern's angle, in degrees: one of 0, 45, 90 or 135.
    public let angle: Int
    /// Up to two letters: the name's first two words' first letters.
    public let initials: String

    /// How many colours each theme has for covers.
    public static let colourCount = 4

    /// The picture for a song or album called `name`, by `by` (an artist, so
    /// songs of the same name by different people differ).
    public init(_ name: String, by: String = "") {
        // FNV-1a over the UTF-8: the same on every device and every launch, unlike Hasher.
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in (name + "\u{1F}" + by).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        pattern = Pattern.allCases[Int(hash % UInt64(Pattern.allCases.count))]
        hash /= UInt64(Pattern.allCases.count)
        back = Int(hash % UInt64(Self.colourCount))
        hash /= UInt64(Self.colourCount)
        front = (back + 1 + Int(hash % UInt64(Self.colourCount - 1))) % Self.colourCount
        hash /= UInt64(Self.colourCount - 1)
        angle = Int(hash % 4) * 45
        initials = Self.initials(of: name)
    }

    public init(_ song: Songbook.Song) {
        self.init(song.title, by: song.credit)
    }

    public init(_ album: Songbook.Album) {
        self.init(album.title ?? KaraokeText.otherSongs, by: album.artist)
    }

    /// The first letters of the first two words that start with a letter or digit, in capitals.
    static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .compactMap { $0.first { $0.isLetter || $0.isNumber } }
        return String(words.prefix(2)).uppercased()
    }
}
