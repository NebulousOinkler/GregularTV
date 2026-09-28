import Foundation

/// A channel made on the Apple TV, in Settings, rather than in
/// `channels.json`. It's kept deliberately simple: a name and number, which
/// kinds of programme, one content rule, two switches, and optionally
/// programmes at set times (in the time zone it was made in, kept with it
/// so every Apple TV agrees what "6:00 PM" means). Everything technical
/// takes the defaults: the Shuffled Shows strategy, a seed made from the
/// number, and the shuffled commercials.
///
/// **Channel codes.** `code` packs the definition into a short text to type
/// into another Apple TV, like the schedule code. The same schedule code
/// only gives the same schedule on two Apple TVs with the same channels, so
/// households share custom channels this way.
///
/// **Privacy.** A custom channel is saved on the device (as its channel
/// code, in `AppPreferences`) because the viewer typed or picked it: its
/// rule may name a genre, series or tag from the library, and nothing else
/// from the library is kept.
public struct CustomChannel: Sendable, Hashable {
    /// Which programmes the channel plays, by one rule. Names match as the
    /// bundled channels' sources do: by name, ignoring case.
    public enum Rule: Sendable, Hashable {
        case everything
        case genre(String)
        case series(String)
        case years(from: Int?, to: Int?)
        case tag(String)
    }

    public var number: Int
    public var name: String
    /// Episodes, movies, or both.
    public var kinds: Set<MediaItem.Kind>
    public var rule: Rule
    /// Programmes start on the hour and half hour, with breaks between.
    public var halfHourSlots: Bool
    /// Breaks play commercials (when there are any, and Settings allows).
    public var commercials: Bool
    /// Programmes at set times (see `FixedProgramme`), in `timeZone`.
    public var fixed: [FixedProgramme]
    public var timeZone: TimeZone

    public init(number: Int, name: String, kinds: Set<MediaItem.Kind> = [.episode, .movie], rule: Rule = .everything,
                halfHourSlots: Bool = true, commercials: Bool = true, fixed: [FixedProgramme] = [],
                timeZone: TimeZone = .current) {
        self.number = number
        self.name = name
        self.kinds = kinds
        self.rule = rule
        self.halfHourSlots = halfHourSlots
        self.commercials = commercials
        self.fixed = fixed
        self.timeZone = timeZone
    }

    /// The numbers custom channels may use, clear of the bundled ones
    /// (`CustomChannelNumbers`).
    public static let numbers = 20...99

    /// Custom channels' seeds start here, clear of the bundled channels'.
    static let seedBase: UInt64 = 1000

    /// As a line-up channel.
    public var channel: Channel {
        Channel(number: number, name: name, itemTypes: kinds, source: rule.source, strategyID: ShuffledShows.id,
                seed: Self.seedBase + UInt64(number), padToMinutes: halfHourSlots ? 30 : nil,
                fillerID: commercials ? ShuffledCommercials.id : NoGapFiller.id,
                timeZone: fixed.isEmpty ? nil : timeZone, fixed: fixed)
    }
}

extension CustomChannel.Rule {
    var source: any ChannelSource {
        switch self {
        case .everything: AllItemsSource()
        case .genre(let name): GenreSource(anyOf: [name])
        case .series(let name): SeriesSource(anyOf: [name])
        case .years(let from, let to): YearRangeSource(from: from, to: to)
        case .tag(let name): TagSource(anyOf: [name])
        }
    }
}

// MARK: - Channel codes

extension CustomChannel {
    /// The longest name, and the longest genre, series or tag, a code holds.
    public static let longestText = 60
    private static let version: UInt8 = 1

    /// The definition as a code to type into another Apple TV, in groups of
    /// five like the schedule code (see `Crockford`).
    ///
    /// Layout: version, number, flags (the kinds, the two switches and the
    /// rule), the name, the rule's text or years, the programmes at set
    /// times (with the time zone, if there are any), then a check byte so a
    /// mistyped code is caught rather than read wrongly.
    public var code: String {
        var bytes: [UInt8] = [Self.version, UInt8(clamping: number)]
        let ruleType: UInt8 = switch rule {
        case .everything: 0
        case .genre: 1
        case .series: 2
        case .years: 3
        case .tag: 4
        }
        bytes.append((kinds.contains(.episode) ? 1 : 0) | (kinds.contains(.movie) ? 2 : 0)
                     | (halfHourSlots ? 4 : 0) | (commercials ? 8 : 0) | ruleType << 4)
        Self.append(name, to: &bytes)
        switch rule {
        case .everything: break
        case .genre(let text), .series(let text), .tag(let text): Self.append(text, to: &bytes)
        case .years(let from, let to):
            for year in [from, to] { Self.append(number: year ?? 0, to: &bytes) }
        }
        bytes.append(UInt8(clamping: fixed.count))
        for entry in fixed.prefix(255) {
            let (isItem, text) = switch entry.match {
            case .series(let name): (false, name)
            case .item(let name): (true, name)
            }
            bytes.append((isItem ? 1 : 0) | (entry.exclusive ? 2 : 0))
            Self.append(text, to: &bytes)
            bytes.append(entry.weekdays.reduce(0) { $0 | UInt8(1 << ($1 - 1)) })
            bytes.append(UInt8(clamping: entry.dates.count))
            for date in entry.dates.sorted(by: { ($0.month, $0.day) < ($1.month, $1.day) }).prefix(255) {
                bytes += [UInt8(date.month), UInt8(date.day)]
            }
            bytes.append(UInt8(clamping: entry.times.count))
            for time in entry.times.prefix(255) { Self.append(number: time, to: &bytes) }
        }
        if !fixed.isEmpty { Self.append(timeZone.identifier, to: &bytes) }
        bytes.append(Self.check(bytes))
        return Crockford.encode(bytes)
    }

    /// Reads a channel code. Nil if it isn't one, or was mistyped.
    public init?(code: String) {
        guard let bytes = Crockford.decode(code), bytes.count >= 5,
              Self.check(Array(bytes.dropLast())) == bytes.last, bytes[0] == Self.version else { return nil }
        var reader = Reader(bytes: Array(bytes.dropLast()), offset: 3)
        let flags = bytes[2]
        guard let name = reader.text() else { return nil }
        let rule: Rule
        switch flags >> 4 {
        case 0: rule = .everything
        case 1: guard let text = reader.text() else { return nil }; rule = .genre(text)
        case 2: guard let text = reader.text() else { return nil }; rule = .series(text)
        case 3:
            guard let from = reader.number(), let to = reader.number() else { return nil }
            rule = .years(from: from == 0 ? nil : from, to: to == 0 ? nil : to)
        case 4: guard let text = reader.text() else { return nil }; rule = .tag(text)
        default: return nil
        }
        guard let fixed = reader.fixedProgrammes() else { return nil }
        var zone = TimeZone.current
        if !fixed.isEmpty {
            guard let identifier = reader.text(), let named = TimeZone(identifier: identifier) else { return nil }
            zone = named
        }
        guard reader.isAtEnd else { return nil }
        var kinds = Set<MediaItem.Kind>()
        if flags & 1 != 0 { kinds.insert(.episode) }
        if flags & 2 != 0 { kinds.insert(.movie) }
        self.init(number: Int(bytes[1]), name: name, kinds: kinds, rule: rule,
                  halfHourSlots: flags & 4 != 0, commercials: flags & 8 != 0, fixed: fixed, timeZone: zone)
    }

    /// Two bytes: a year, or minutes after midnight.
    private static func append(number: Int, to bytes: inout [UInt8]) {
        bytes += [UInt8(truncatingIfNeeded: number >> 8), UInt8(truncatingIfNeeded: number)]
    }

    private static func append(_ text: String, to bytes: inout [UInt8]) {
        let utf8 = Array(String(text.prefix(longestText)).utf8.prefix(255))
        bytes.append(UInt8(utf8.count))
        bytes += utf8
    }

    /// CRC-8: catches any single mistyped character, and most others.
    private static func check(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0)) { crc, byte in
            (0..<8).reduce(crc ^ byte) { c, _ in c & 0x80 != 0 ? (c << 1) ^ 0x07 : c << 1 }
        }
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int

        var isAtEnd: Bool { offset == bytes.count }

        mutating func text() -> String? {
            guard offset < bytes.count, offset + 1 + Int(bytes[offset]) <= bytes.count else { return nil }
            let length = Int(bytes[offset])
            defer { offset += 1 + length }
            return String(bytes: bytes[(offset + 1)..<(offset + 1 + length)], encoding: .utf8)
        }

        mutating func number() -> Int? {
            guard offset + 2 <= bytes.count else { return nil }
            defer { offset += 2 }
            return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
        }

        mutating func byte() -> UInt8? {
            guard offset < bytes.count else { return nil }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func fixedProgrammes() -> [FixedProgramme]? {
            guard let count = byte() else { return nil }
            var entries: [FixedProgramme] = []
            for _ in 0..<count {
                guard let flags = byte(), let name = text(), let weekdayBits = byte(), let dateCount = byte() else { return nil }
                var dates = Set<FixedProgramme.MonthDay>()
                for _ in 0..<dateCount {
                    guard let month = byte(), let day = byte() else { return nil }
                    dates.insert(FixedProgramme.MonthDay(month: Int(month), day: Int(day)))
                }
                guard let timeCount = byte() else { return nil }
                var times: [Int] = []
                for _ in 0..<timeCount {
                    guard let time = number() else { return nil }
                    times.append(time)
                }
                entries.append(FixedProgramme(match: flags & 1 != 0 ? .item(name) : .series(name), times: times,
                                              weekdays: Set((1...7).filter { weekdayBits & UInt8(1 << ($0 - 1)) != 0 }),
                                              dates: dates, exclusive: flags & 2 != 0))
            }
            return entries
        }
    }
}
