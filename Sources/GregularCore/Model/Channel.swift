import Foundation

/// One channel's definition, as written in `channels.json`.
///
/// ```json
/// { "number": 2, "name": "Comedy",
///   "source": { "type": "genre", "anyOf": ["Comedy", "Sitcom"] },
///   "strategy": "shuffled-mix", "films": 0.35, "needsVariety": true, "seed": 2 }
/// ```
///
/// Optional keys: `itemTypes` (default: both), `padTo` (minutes; off by default),
/// `films` (a mixed channel's share of airtime for films, 0 to 1, for the
/// `shuffled-mix` strategy), `needsVariety` (hidden unless the library has
/// enough different programmes; see `ChannelVariety`),
/// `filler` (what fills padding gaps, a `GapFiller` ID; default `"none"`),
/// `epoch` (ISO 8601; default `Channel.defaultEpoch`), and `fixed` with
/// `timeZone` (programmes at set local times, laid over the channel's shared
/// schedule; see `FixedProgramme`).
public struct Channel: Sendable {
    /// The shared starting point for every channel's clock, at midnight
    /// Pacific: each day's run starts at this wall-clock time in
    /// `ChannelSchedule.dayTimeZone`. Changing it reshuffles what's on every
    /// channel right now.
    public static let defaultEpoch = Date(timeIntervalSince1970: 1_704_096_000) // 2024-01-01T00:00:00-08:00

    public let number: Int
    public let name: String
    public let itemTypes: Set<MediaItem.Kind>
    public let source: any ChannelSource
    public let strategyID: String
    public let seed: UInt64
    /// Round each slot up to a multiple of this many minutes, e.g. 30 means
    /// programmes start on the hour and half-hour.
    public let padToMinutes: Int?
    /// The `GapFiller` for padding gaps.
    public let fillerID: String
    public let epoch: Date
    /// Programmes at set local times, laid over the shared schedule.
    public let fixed: [FixedProgramme]
    /// A mixed channel's share of airtime for films, 0 to 1 (`ShuffledMix`).
    /// The library can move it (`ChannelVariety.filmShare(wanted:)`).
    public let filmShare: Double?
    /// Hidden unless the library has enough different programmes to fill a
    /// day without repeats coming round too soon (`ChannelVariety.fillsADay`).
    public let needsVariety: Bool

    public init(
        number: Int,
        name: String,
        itemTypes: Set<MediaItem.Kind> = Set(MediaItem.Kind.allCases),
        source: any ChannelSource,
        strategyID: String,
        seed: UInt64,
        padToMinutes: Int? = nil,
        fillerID: String = "none",
        epoch: Date = Channel.defaultEpoch,
        fixed: [FixedProgramme] = [],
        filmShare: Double? = nil,
        needsVariety: Bool = false
    ) {
        self.number = number
        self.name = name
        self.itemTypes = itemTypes
        self.source = source
        self.strategyID = strategyID
        self.seed = seed
        self.padToMinutes = padToMinutes
        self.fillerID = fillerID
        self.epoch = epoch
        self.fixed = fixed
        self.filmShare = filmShare
        self.needsVariety = needsVariety
    }

    /// The same channel with its clock started at `epoch` instead.
    public func withEpoch(_ epoch: Date) -> Channel {
        Channel(number: number, name: name, itemTypes: itemTypes, source: source, strategyID: strategyID, seed: seed,
                padToMinutes: padToMinutes, fillerID: fillerID, epoch: epoch, fixed: fixed,
                filmShare: filmShare, needsVariety: needsVariety)
    }

    /// The same channel with more set times (a household's `SetTimes`).
    public func adding(_ setTimes: [FixedProgramme]) -> Channel {
        Channel(number: number, name: name, itemTypes: itemTypes, source: source, strategyID: strategyID, seed: seed,
                padToMinutes: padToMinutes, fillerID: fillerID, epoch: epoch, fixed: fixed + setTimes,
                filmShare: filmShare, needsVariety: needsVariety)
    }

    /// True when the item should be on this channel.
    public func accepts(_ item: MediaItem) -> Bool {
        itemTypes.contains(item.kind) && source.matches(item)
    }
}

// MARK: - Decoding

extension Channel: Decodable {
    private enum CodingKeys: String, CodingKey {
        case number, name, itemTypes, source, strategy, seed, padTo, filler, epoch, timeZone, fixed, films, needsVariety
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        number = try c.decode(Int.self, forKey: .number)
        name = try c.decode(String.self, forKey: .name)
        itemTypes = try c.decodeIfPresent(Set<MediaItem.Kind>.self, forKey: .itemTypes) ?? Set(MediaItem.Kind.allCases)
        seed = UInt64(bitPattern: try c.decode(Int64.self, forKey: .seed))
        padToMinutes = try c.decodeIfPresent(Int.self, forKey: .padTo)
        epoch = try c.decodeIfPresent(Date.self, forKey: .epoch) ?? Channel.defaultEpoch
        filmShare = try c.decodeIfPresent(Double.self, forKey: .films)
        if let filmShare, !(0...1).contains(filmShare) {
            throw DecodingError.dataCorruptedError(forKey: .films, in: c,
                                                   debugDescription: "Channel \(number): \"films\" is a share of airtime, from 0 to 1.")
        }
        needsVariety = try c.decodeIfPresent(Bool.self, forKey: .needsVariety) ?? false
        // The channel's "timeZone" is where its set times are read.
        let entries = try c.decodeIfPresent([FixedProgramme].self, forKey: .fixed) ?? []
        if let identifier = try c.decodeIfPresent(String.self, forKey: .timeZone) {
            guard let zone = TimeZone(identifier: identifier) else {
                throw DecodingError.dataCorruptedError(forKey: .timeZone, in: c,
                                                       debugDescription: "Channel \(number): unknown time zone '\(identifier)'.")
            }
            fixed = entries.map { $0.in(zone) }
        } else {
            fixed = entries
        }

        strategyID = try c.decode(String.self, forKey: .strategy)
        guard StrategyRegistry.contains(id: strategyID) else {
            let known = StrategyRegistry.all.map { $0.id }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .strategy, in: c,
                debugDescription: "Channel \(number): unknown strategy '\(strategyID)'. Known: \(known)")
        }

        fillerID = try c.decodeIfPresent(String.self, forKey: .filler) ?? NoGapFiller.id
        guard GapFillerRegistry.contains(id: fillerID) else {
            let known = GapFillerRegistry.all.map { $0.id }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .filler, in: c,
                debugDescription: "Channel \(number): unknown filler '\(fillerID)'. Known: \(known)")
        }

        do {
            source = try ChannelSourceRegistry.decode(from: c.superDecoder(forKey: .source))
        } catch DecodingError.dataCorrupted(let context) {
            throw DecodingError.dataCorruptedError(forKey: .source, in: c,
                                                   debugDescription: "Channel \(number): \(context.debugDescription)")
        }
    }
}
