import Foundation

/// One channel's definition, as written in `channels.json`.
///
/// ```json
/// { "number": 2, "name": "Comedy", "itemTypes": ["Episode"],
///   "source": { "type": "genre", "anyOf": ["Comedy", "Sitcom"] },
///   "strategy": "series-round-robin", "seed": 2 }
/// ```
///
/// Optional keys: `itemTypes` (default: both), `padTo` (minutes; off by default),
/// `filler` (what fills padding gaps, a `GapFiller` ID; default `"none"`), and
/// `epoch` (ISO 8601; default `Channel.defaultEpoch`).
public struct Channel: Sendable {
    /// The shared starting point for every channel's clock. Changing it
    /// reshuffles what's on every channel right now.
    public static let defaultEpoch = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00:00Z

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

    public init(
        number: Int,
        name: String,
        itemTypes: Set<MediaItem.Kind> = Set(MediaItem.Kind.allCases),
        source: any ChannelSource,
        strategyID: String,
        seed: UInt64,
        padToMinutes: Int? = nil,
        fillerID: String = "none",
        epoch: Date = Channel.defaultEpoch
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
    }

    /// True when the item should be on this channel.
    public func accepts(_ item: MediaItem) -> Bool {
        itemTypes.contains(item.kind) && source.matches(item)
    }
}

// MARK: - Decoding

extension Channel: Decodable {
    private enum CodingKeys: String, CodingKey {
        case number, name, itemTypes, source, strategy, seed, padTo, filler, epoch
    }

    private enum SourceTypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        number = try c.decode(Int.self, forKey: .number)
        name = try c.decode(String.self, forKey: .name)
        itemTypes = try c.decodeIfPresent(Set<MediaItem.Kind>.self, forKey: .itemTypes) ?? Set(MediaItem.Kind.allCases)
        seed = UInt64(bitPattern: try c.decode(Int64.self, forKey: .seed))
        padToMinutes = try c.decodeIfPresent(Int.self, forKey: .padTo)
        epoch = try c.decodeIfPresent(Date.self, forKey: .epoch) ?? Channel.defaultEpoch

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

        let sourceDecoder = try c.superDecoder(forKey: .source)
        let typeName = try sourceDecoder.container(keyedBy: SourceTypeKey.self).decode(String.self, forKey: .type)
        guard let sourceType = ChannelSourceRegistry.sourceType(named: typeName) else {
            let known = ChannelSourceRegistry.all.map { $0.type }.joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .source, in: c,
                debugDescription: "Channel \(number): unknown source type '\(typeName)'. Known: \(known)")
        }
        source = try sourceType.init(from: sourceDecoder)
    }
}
