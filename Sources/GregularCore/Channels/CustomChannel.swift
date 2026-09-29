import Foundation

/// A channel made on the Apple TV, in Settings, rather than in
/// `channels.json`. It's kept deliberately simple: a name and number, which
/// kinds of programme, one content rule, and two switches. Everything
/// technical takes the defaults: the Shuffled Shows strategy, a seed made
/// from the number, and the shuffled commercials. (Set times on it, as on
/// any channel, are a separate `SetTimes`.)
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
    /// The longest a channel name may be, in characters, so it fits the guide.
    public static let longestName = 60
    /// Episodes, movies, or both.
    public var kinds: Set<MediaItem.Kind>
    public var rule: Rule
    /// Programmes start on the hour and half hour, with breaks between.
    public var halfHourSlots: Bool
    /// Breaks play commercials (when there are any, and Settings allows).
    public var commercials: Bool

    public init(number: Int, name: String, kinds: Set<MediaItem.Kind> = [.episode, .movie], rule: Rule = .everything,
                halfHourSlots: Bool = true, commercials: Bool = true) {
        self.number = number
        self.name = name
        self.kinds = kinds
        self.rule = rule
        self.halfHourSlots = halfHourSlots
        self.commercials = commercials
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
                fillerID: commercials ? ShuffledCommercials.id : NoGapFiller.id)
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
    private static let version: UInt8 = 1

    /// The definition as a code to type into another Apple TV, in groups of
    /// five like the schedule code (see `CodeWriter`): the number, flags (the
    /// kinds, the two switches and the rule), the name, and the rule's text
    /// or years.
    public var code: String {
        var writer = CodeWriter(version: Self.version)
        writer.byte(UInt8(clamping: number))
        let ruleType: UInt8 = switch rule {
        case .everything: 0
        case .genre: 1
        case .series: 2
        case .years: 3
        case .tag: 4
        }
        writer.byte((kinds.contains(.episode) ? 1 : 0) | (kinds.contains(.movie) ? 2 : 0)
                    | (halfHourSlots ? 4 : 0) | (commercials ? 8 : 0) | ruleType << 4)
        writer.text(name)
        switch rule {
        case .everything: break
        case .genre(let text), .series(let text), .tag(let text): writer.text(text)
        case .years(let from, let to):
            writer.number(from ?? 0)
            writer.number(to ?? 0)
        }
        return writer.code
    }

    /// Reads a channel code. Nil if it isn't one, or was mistyped.
    public init?(code: String) {
        guard var reader = CodeReader(code: code, version: Self.version),
              let number = reader.byte(), let flags = reader.byte(), let name = reader.text() else { return nil }
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
        guard reader.isAtEnd else { return nil }
        var kinds = Set<MediaItem.Kind>()
        if flags & 1 != 0 { kinds.insert(.episode) }
        if flags & 2 != 0 { kinds.insert(.movie) }
        self.init(number: Int(number), name: name, kinds: kinds, rule: rule,
                  halfHourSlots: flags & 4 != 0, commercials: flags & 8 != 0)
    }
}
