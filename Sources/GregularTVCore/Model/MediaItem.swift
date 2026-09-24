import Foundation

/// One playable episode or movie, as fetched from Jellyfin.
///
/// Held in memory only. It's never written to disk (see PLAN.md §3).
public struct MediaItem: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case episode = "Episode"
        case movie = "Movie"
        /// A plain video, such as a commercial in a "Home Videos" library.
        /// Regular channels never see these; only gap fillers use them.
        case video = "Video"
    }

    public let id: String
    public let kind: Kind
    public let name: String
    /// Runtime in seconds.
    public let duration: TimeInterval
    public let seriesID: String?
    public let seriesName: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let productionYear: Int?
    /// Original air or release date. Orders episodes that have no episode
    /// number, such as daily or year-numbered shows.
    public let premiereDate: Date?
    /// For episodes, the client fills this with the parent series' genres,
    /// because Jellyfin rarely sets genres on individual episodes.
    public let genres: [String]
    public let tags: [String]

    public init(
        id: String,
        kind: Kind,
        name: String,
        duration: TimeInterval,
        seriesID: String? = nil,
        seriesName: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        productionYear: Int? = nil,
        premiereDate: Date? = nil,
        genres: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.duration = duration
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.productionYear = productionYear
        self.premiereDate = premiereDate
        self.genres = genres
        self.tags = tags
    }
}

// MARK: - Helpers for strategies

extension MediaItem {
    /// Groups items that belong together. Episodes of one series share a key.
    /// Every movie gets its own key.
    public var seriesKey: String {
        seriesID.map { "series:\($0)" } ?? "item:\(id)"
    }

    /// Sort order for episodes within a series: season, then episode number,
    /// then air date. Air date matters for shows without episode numbers.
    /// Specials (season 0) and unnumbered items go last.
    public static func airedOrder(_ a: MediaItem, _ b: MediaItem) -> Bool {
        func key(_ item: MediaItem) -> (Int, Int, Date, String, String) {
            let season = item.seasonNumber.flatMap { $0 == 0 ? nil : $0 } ?? .max
            return (season, item.episodeNumber ?? .max, item.premiereDate ?? .distantFuture, item.name, item.id)
        }
        return key(a) < key(b)
    }

    /// Splits items into series groups. Each group is in aired order, and the
    /// groups are sorted by `seriesKey`, so the result doesn't depend on input order.
    public static func groupedBySeries(_ items: [MediaItem]) -> [[MediaItem]] {
        Dictionary(grouping: items, by: \.seriesKey)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted(by: airedOrder) }
    }
}
