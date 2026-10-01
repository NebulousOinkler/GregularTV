import Foundation
import GregularCore

/// The viewer's own channels and set times as JSON, the shape the editing
/// page edits and shows (and can paste in or copy out). It follows
/// `channels.json` where the two overlap: set times are written the same
/// way, and a channel's rule is three lists of conditions.
///
/// ```json
/// { "channels": [
///     { "number": 30, "name": "Laughs", "plays": "both",
///       "rule": { "anyOf": [{ "genre": "Comedy" }, { "series": "Taskmaster" }],
///                 "allOf": [{ "years": { "from": 1990 } }],
///                 "noneOf": [{ "tag": "Christmas" }] },
///       "halfHourSlots": true, "commercials": true } ],
///   "setTimes": [
///     { "channel": 1, "timeZone": "America/Los_Angeles",
///       "programmes": [{ "series": "The Simpsons", "at": ["18:00", "18:30"], "days": ["Mon", "Tue"] }] } ] }
/// ```
///
/// Everything in it is checked as the codes are (`ChannelLineup.adding`), so
/// a document can't do more than the editors on the Apple TV can.
public struct EditingDocument: Codable, Sendable, Equatable {
    public var channels: [ChannelEntry]
    public var setTimes: [SetTimesEntry]

    public struct ChannelEntry: Codable, Sendable, Equatable {
        public var number: Int
        public var name: String
        /// "episodes", "movies" or "both".
        public var plays: String
        public var rule: RuleEntry
        public var halfHourSlots: Bool?
        public var commercials: Bool?
    }

    public struct RuleEntry: Codable, Sendable, Equatable {
        public var anyOf: [MatchEntry]?
        public var allOf: [MatchEntry]?
        public var noneOf: [MatchEntry]?
    }

    /// One of `genre`, `series`, `tag` or `years`.
    public struct MatchEntry: Codable, Sendable, Equatable {
        public var genre: String?
        public var series: String?
        public var tag: String?
        public var years: YearsEntry?
    }

    public struct YearsEntry: Codable, Sendable, Equatable {
        public var from: Int?
        public var to: Int?
    }

    public struct SetTimesEntry: Codable, Sendable, Equatable {
        public var channel: Int
        /// An identifier such as "America/Los_Angeles".
        public var timeZone: String
        public var programmes: [ProgrammeEntry]
    }

    /// As in `channels.json`: one of `series` or `item` (a film), `at`
    /// ("18:30"), and optionally `days` ("Mon", "Feb 2") and `exclusive`.
    public struct ProgrammeEntry: Codable, Sendable, Equatable {
        public var series: String?
        public var item: String?
        public var at: [String]
        public var days: [String]?
        public var exclusive: Bool?
    }

    /// Why a document can't be used, in plain words.
    public struct Problem: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    public init(channels: [CustomChannel], setTimes: [SetTimes]) {
        self.channels = channels.map(ChannelEntry.init)
        self.setTimes = setTimes.map(SetTimesEntry.init)
    }

    /// The channels and set times it describes. Throws a `Problem` naming
    /// the first thing that's wrong.
    public func resolved() throws -> (channels: [CustomChannel], setTimes: [SetTimes]) {
        (try channels.map { try $0.channel() }, try setTimes.map { try $0.setTimes() })
    }

    /// The document as text: pretty, with keys in a fixed order.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Reads `data` as a document. Throws a `Problem` if it isn't one.
    public static func read(_ data: Data) throws -> EditingDocument {
        do {
            return try JSONDecoder().decode(EditingDocument.self, from: data)
        } catch {
            throw Problem(description: "That isn't a channels document: \(Self.describe(error))")
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context), DecodingError.keyNotFound(_, let context),
             DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
            return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
        default:
            return "\(error)"
        }
    }
}

// MARK: - Channels

extension EditingDocument.ChannelEntry {
    init(_ channel: CustomChannel) {
        number = channel.number
        name = channel.name
        plays = switch (channel.kinds.contains(.episode), channel.kinds.contains(.movie)) {
        case (true, false): "episodes"
        case (false, true): "movies"
        default: "both"
        }
        let entries = { (mode: CustomChannel.Rule.Mode) -> [EditingDocument.MatchEntry]? in
            let matches = channel.rule.conditions(mode).map(EditingDocument.MatchEntry.init)
            return matches.isEmpty ? nil : matches
        }
        rule = EditingDocument.RuleEntry(anyOf: entries(.anyOf), allOf: entries(.allOf), noneOf: entries(.noneOf))
        halfHourSlots = channel.halfHourSlots
        commercials = channel.commercials
    }

    func channel() throws -> CustomChannel {
        let kinds: Set<MediaItem.Kind>
        switch plays.lowercased() {
        case "episodes": kinds = [.episode]
        case "movies": kinds = [.movie]
        case "both": kinds = [.episode, .movie]
        default: throw EditingDocument.Problem(description: "Channel \(number): \"plays\" is \"episodes\", \"movies\" or \"both\".")
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw EditingDocument.Problem(description: "Channel \(number) needs a name.") }
        guard trimmed.count <= CustomChannel.longestName else {
            throw EditingDocument.Problem(description: "Channel \(number): keep the name to \(CustomChannel.longestName) characters.")
        }
        var conditions: [CustomChannel.Rule.Condition] = []
        for (mode, entries) in [(CustomChannel.Rule.Mode.anyOf, rule.anyOf), (.allOf, rule.allOf), (.noneOf, rule.noneOf)] {
            for entry in entries ?? [] {
                conditions.append(.init(mode, try entry.match(onChannel: number)))
            }
        }
        guard conditions.count <= CustomChannel.Rule.mostConditions else {
            throw EditingDocument.Problem(description: "Channel \(number) has more than \(CustomChannel.Rule.mostConditions) conditions.")
        }
        return CustomChannel(number: number, name: trimmed, kinds: kinds, rule: CustomChannel.Rule(conditions),
                             halfHourSlots: halfHourSlots ?? true, commercials: commercials ?? true)
    }
}

extension EditingDocument.MatchEntry {
    init(_ match: CustomChannel.Rule.Match) {
        switch match {
        case .genre(let name): genre = name
        case .series(let name): series = name
        case .tag(let name): tag = name
        case .years(let from, let to): years = EditingDocument.YearsEntry(from: from, to: to)
        }
    }

    func match(onChannel number: Int) throws -> CustomChannel.Rule.Match {
        let named = [genre.map(CustomChannel.Rule.Match.genre), series.map(CustomChannel.Rule.Match.series),
                     tag.map(CustomChannel.Rule.Match.tag),
                     years.map { CustomChannel.Rule.Match.years(from: $0.from, to: $0.to) }].compactMap { $0 }
        guard named.count == 1, let match = named.first else {
            throw EditingDocument.Problem(description: "Channel \(number): each condition is one \"genre\", \"series\", \"tag\" or \"years\".")
        }
        if case .years(let from, let to) = match {
            guard from != nil || to != nil else {
                throw EditingDocument.Problem(description: "Channel \(number): \"years\" needs a \"from\", a \"to\", or both.")
            }
            if let from, let to, from > to {
                throw EditingDocument.Problem(description: "Channel \(number): the first year comes after the last.")
            }
            guard [from, to].allSatisfy({ ($0 ?? 1) > 0 && ($0 ?? 1) < 10_000 }) else {
                throw EditingDocument.Problem(description: "Channel \(number): years are from 1 to 9999.")
            }
        } else if match.label.trimmingCharacters(in: .whitespaces).isEmpty {
            throw EditingDocument.Problem(description: "Channel \(number): a condition names nothing.")
        }
        return match
    }
}

// MARK: - Set times

extension EditingDocument.SetTimesEntry {
    init(_ setTimes: SetTimes) {
        channel = setTimes.channelNumber
        timeZone = setTimes.timeZone.identifier
        programmes = setTimes.programmes.map { entry in
            let (series, item): (String?, String?) = switch entry.match {
            case .series(let name): (name, nil)
            case .item(let name): (nil, name)
            }
            return EditingDocument.ProgrammeEntry(series: series, item: item, at: entry.times.map(FixedProgramme.text(forMinutes:)),
                                                  days: entry.days.isEmpty ? nil : entry.days,
                                                  exclusive: entry.exclusive ? true : nil)
        }
    }

    func setTimes() throws -> SetTimes {
        guard let zone = TimeZone(identifier: timeZone) else {
            throw EditingDocument.Problem(description: "Set times on channel \(channel): \"\(timeZone)\" isn't a time zone.")
        }
        // Read each programme as channels.json does, so the two never disagree.
        let programmes: [FixedProgramme]
        do {
            programmes = try JSONDecoder().decode([FixedProgramme].self, from: JSONEncoder().encode(self.programmes))
        } catch {
            throw EditingDocument.Problem(description: "Set times on channel \(channel): \(EditingDocument.describe(error))")
        }
        return SetTimes(channelNumber: channel, programmes: programmes.map { $0.in(zone) }, timeZone: zone)
    }
}
