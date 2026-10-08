import Foundation

/// A channel made on the Apple TV, in Settings, rather than in
/// `channels.json`. It's kept deliberately simple: a name and number, which
/// kinds of programme, a rule of a few conditions, and two switches. Everything
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
    /// Which programmes the channel plays: conditions, each joined to the
    /// rest one of three ways. A programme is on the channel when it matches
    /// any of the "any of" conditions (or there are none), all of the "all
    /// of" ones, and none of the "none of" ones. No conditions at all is
    /// everything. Names match as the bundled channels' sources do: by name,
    /// ignoring case.
    public struct Rule: Sendable, Hashable {
        /// How a condition joins the others.
        public enum Mode: UInt8, CaseIterable, Sendable {
            case anyOf = 0, allOf = 1, noneOf = 2
        }

        /// What one condition matches.
        public enum Match: Sendable, Hashable {
            case genre(String)
            case series(String)
            case tag(String)
            case years(from: Int?, to: Int?)
        }

        public struct Condition: Sendable, Hashable {
            public var mode: Mode
            public var match: Match

            public init(_ mode: Mode, _ match: Match) {
                self.mode = mode
                self.match = match
            }
        }

        public var conditions: [Condition]

        /// The most conditions a rule may have, so a code stays typeable.
        public static let mostConditions = 20

        public init(_ conditions: [Condition] = []) {
            self.conditions = conditions
        }

        public static let everything = Rule()
        public static func genre(_ name: String) -> Rule { Rule([Condition(.anyOf, .genre(name))]) }
        public static func series(_ name: String) -> Rule { Rule([Condition(.anyOf, .series(name))]) }
        public static func tag(_ name: String) -> Rule { Rule([Condition(.anyOf, .tag(name))]) }
        public static func years(from: Int?, to: Int?) -> Rule { Rule([Condition(.anyOf, .years(from: from, to: to))]) }

        /// The conditions joined one way.
        public func conditions(_ mode: Mode) -> [Match] {
            conditions.filter { $0.mode == mode }.map(\.match)
        }
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

extension CustomChannel {
    /// What's wrong with this channel, in plain words, or nothing: a name
    /// that's empty or longer than `longestName`, more than
    /// `Rule.mostConditions` conditions, or a condition that names nothing
    /// (years must be from 1 to 9999, the first no later than the last).
    public var problems: [String] {
        let name = name.trimmingCharacters(in: .whitespaces)
        var problems: [String] = []
        if name.isEmpty { problems.append("Channel \(number) needs a name.") }
        if name.count > Self.longestName { problems.append("Channel \(number): keep the name to \(Self.longestName) characters.") }
        if rule.conditions.count > Rule.mostConditions {
            problems.append("Channel \(number) has more than \(Rule.mostConditions) conditions.")
        }
        for condition in rule.conditions {
            switch condition.match {
            case .genre(let text), .series(let text), .tag(let text):
                if text.trimmingCharacters(in: .whitespaces).isEmpty { problems.append("Channel \(number): a condition names nothing.") }
            case .years(nil, nil):
                problems.append("Channel \(number): \"years\" needs a \"from\", a \"to\", or both.")
            case .years(let from?, let to?) where from > to:
                problems.append("Channel \(number): the first year comes after the last.")
            case .years(let from, let to):
                if ![from, to].allSatisfy({ (1...9999).contains($0 ?? 1) }) { problems.append("Channel \(number): years are from 1 to 9999.") }
            }
        }
        return problems
    }
}

extension CustomChannel.Rule {
    /// As a line-up source: all of the "all of" conditions, any of the "any
    /// of" ones, and not any of the "none of" ones (`CombinedSources`).
    var source: any ChannelSource {
        var parts = conditions(.allOf).map(\.source)
        let any = conditions(.anyOf), none = conditions(.noneOf)
        if !any.isEmpty { parts.append(any.count == 1 ? any[0].source : AnyOfSource(sources: any.map(\.source))) }
        if !none.isEmpty { parts.append(NotSource(source: AnyOfSource(sources: none.map(\.source)))) }
        switch parts.count {
        case 0: return AllItemsSource()
        case 1: return parts[0]
        default: return AllOfSource(sources: parts)
        }
    }
}

extension CustomChannel.Rule.Match {
    var source: any ChannelSource {
        switch self {
        case .genre(let name): GenreSource(anyOf: [name])
        case .series(let name): SeriesSource(anyOf: [name])
        case .tag(let name): TagSource(anyOf: [name])
        case .years(let from, let to): YearRangeSource(from: from, to: to)
        }
    }
}

// MARK: - Channel codes

extension CustomChannel {
    /// Codes of this version carry a rule of several conditions; version 1
    /// (still read) carried one.
    private static let version: UInt8 = 2

    /// The definition as a code to type into another Apple TV, in groups of
    /// five like the schedule code (see `CodeWriter`): the number, flags (the
    /// kinds and the two switches), the name, then the conditions, each a
    /// byte (how it joins, and what it matches) and its text or years.
    public var code: String {
        var writer = CodeWriter(version: Self.version)
        writer.byte(UInt8(clamping: number))
        writer.byte(flags)
        writer.text(name)
        writer.byte(UInt8(clamping: rule.conditions.count))
        for condition in rule.conditions.prefix(Rule.mostConditions) {
            let kind: UInt8 = switch condition.match {
            case .genre: 0
            case .series: 1
            case .tag: 2
            case .years: 3
            }
            writer.byte(condition.mode.rawValue << 4 | kind)
            switch condition.match {
            case .genre(let text), .series(let text), .tag(let text): writer.text(text)
            case .years(let from, let to):
                writer.number(from ?? 0)
                writer.number(to ?? 0)
            }
        }
        return writer.code
    }

    private var flags: UInt8 {
        (kinds.contains(.episode) ? 1 : 0) | (kinds.contains(.movie) ? 2 : 0) | (halfHourSlots ? 4 : 0) | (commercials ? 8 : 0)
    }

    /// Reads a channel code, of this version or the first. Nil if it isn't
    /// one, was mistyped, or has more than `Rule.mostConditions` conditions.
    public init?(code: String) {
        if var reader = CodeReader(code: code, version: Self.version) {
            guard let number = reader.byte(), let flags = reader.byte(), let name = reader.text(),
                  let count = reader.byte(), count <= Rule.mostConditions else { return nil }
            var conditions: [Rule.Condition] = []
            for _ in 0..<count {
                guard let byte = reader.byte(), let mode = Rule.Mode(rawValue: byte >> 4) else { return nil }
                let match: Rule.Match
                switch byte & 0x0F {
                case 0: guard let text = reader.text() else { return nil }; match = .genre(text)
                case 1: guard let text = reader.text() else { return nil }; match = .series(text)
                case 2: guard let text = reader.text() else { return nil }; match = .tag(text)
                case 3:
                    guard let from = reader.number(), let to = reader.number() else { return nil }
                    match = .years(from: from == 0 ? nil : from, to: to == 0 ? nil : to)
                default: return nil
                }
                conditions.append(Rule.Condition(mode, match))
            }
            guard reader.isAtEnd else { return nil }
            self.init(number: Int(number), flags: flags, name: name, rule: Rule(conditions))
        } else {
            self.init(firstVersionCode: code)
        }
    }

    private init(number: Int, flags: UInt8, name: String, rule: Rule) {
        var kinds = Set<MediaItem.Kind>()
        if flags & 1 != 0 { kinds.insert(.episode) }
        if flags & 2 != 0 { kinds.insert(.movie) }
        self.init(number: number, name: name, kinds: kinds, rule: rule,
                  halfHourSlots: flags & 4 != 0, commercials: flags & 8 != 0)
    }

    /// A version 1 code: one rule, its kind in the flags' top four bits.
    private init?(firstVersionCode code: String) {
        guard var reader = CodeReader(code: code, version: 1),
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
        self.init(number: Int(number), flags: flags & 0x0F, name: name, rule: rule)
    }
}
