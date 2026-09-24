import Foundation

/// The full set of configured channels, loaded from `channels.json`.
public struct ChannelLineup: Sendable {
    public enum LoadError: Error, Equatable, CustomStringConvertible {
        case missingBundledFile
        case duplicateChannelNumber(Int)

        public var description: String {
            switch self {
            case .missingBundledFile: "channels.json is missing from the app bundle"
            case .duplicateChannelNumber(let n): "channels.json defines channel \(n) more than once"
            }
        }
    }

    /// Sorted by channel number.
    public let channels: [Channel]
    /// The Jellyfin library holding the commercials (gap filler clips), by
    /// name. Nil means no commercials.
    public let commercialsLibrary: String?

    public init(channels: [Channel], commercialsLibrary: String? = nil) throws {
        var seen = Set<Int>()
        for channel in channels where !seen.insert(channel.number).inserted {
            throw LoadError.duplicateChannelNumber(channel.number)
        }
        self.channels = channels.sorted { $0.number < $1.number }
        self.commercialsLibrary = commercialsLibrary
    }

    /// `channels.json` is either a list of channels, or
    /// `{ "commercials": { "library": "Commercials" }, "channels": [ … ] }`.
    public static func load(from data: Data) throws -> ChannelLineup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([Channel].self, from: data) {
            return try ChannelLineup(channels: list)
        }
        let file = try decoder.decode(File.self, from: data)
        return try ChannelLineup(channels: file.channels, commercialsLibrary: file.commercials?.library)
    }

    private struct File: Decodable {
        struct Commercials: Decodable { let library: String }
        let commercials: Commercials?
        let channels: [Channel]
    }

    /// The line-up that ships with the app (`Resources/channels.json`).
    public static func bundled() throws -> ChannelLineup {
        guard let url = Bundle.module.url(forResource: "channels", withExtension: "json") else {
            throw LoadError.missingBundledFile
        }
        return try load(from: Data(contentsOf: url))
    }

    /// Builds a schedule for every channel that has content. Channels that
    /// match nothing in this library are left out (hidden), so channel
    /// numbers can have gaps.
    /// - Parameters:
    ///   - fillerPool: clips for channels with a gap `filler`: the videos
    ///     from `commercialsLibrary`. They never air as programmes, even if
    ///     that library is also a movie library.
    ///   - code: one code for every channel; each channel derives its own key from it.
    ///   - playsCommercials: false leaves every break blank. The clips are
    ///     still kept out of the programmes, so programme times are exactly
    ///     the same either way: everyone with the same code stays in step.
    public func schedules(for items: [MediaItem], fillerPool: [MediaItem] = [],
                          code: ScheduleCode = .standard, playsCommercials: Bool = true) -> [ChannelSchedule] {
        let clipIDs = Set(fillerPool.map(\.id))
        let programmes = clipIDs.isEmpty ? items : items.filter { !clipIDs.contains($0.id) }
        let clips = playsCommercials ? fillerPool : []
        return channels.compactMap { ChannelSchedule(channel: $0, items: programmes, fillerPool: clips, code: code) }
    }
}
