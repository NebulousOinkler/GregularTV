import Foundation

/// One playable item (an episode, a movie, a plain video such as a
/// commercial, a song or a music video), as a `MediaLibrary` provides it.
///
/// Held in memory only. It's never written to disk (see PLAN.md §3).
public struct MediaItem: Sendable, Hashable, Identifiable {
    /// What sort of item it is. The raw values are the names `channels.json`
    /// uses in `itemTypes`. A `MediaLibrary` maps its server's own types to
    /// these. Only `MediaLibrary.fetchCollection(named:kinds:)` gives songs and
    /// music videos, so channels never see them.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case episode = "Episode"
        case movie = "Movie"
        /// A plain video, such as a commercial in a "Home Videos" library.
        /// Regular channels never see these; only gap fillers use them.
        case video = "Video"
        /// A sound file.
        case song = "Audio"
        case musicVideo = "MusicVideo"
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
    /// because servers such as Jellyfin rarely set genres on individual episodes.
    public let genres: [String]
    public let tags: [String]
    /// For songs and music videos: who performs it, and the album it's on.
    public let artists: [String]
    public let album: String?
    /// The folders it's in within its library, outermost first, for
    /// libraries arranged by folder (empty when it's at the top, or the
    /// server doesn't say).
    public let folders: [String]
    /// For songs: the server has lyrics for it (`LyricsSource`).
    public let hasLyrics: Bool
    /// The kind of file, as the server names it, such as "mp4" or
    /// "mov,mp4,m4a" (several when the server can't tell them apart). Nil if
    /// it doesn't say.
    public let container: String?

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
        tags: [String] = [],
        artists: [String] = [],
        album: String? = nil,
        folders: [String] = [],
        hasLyrics: Bool = false,
        container: String? = nil
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
        self.artists = artists
        self.album = album
        self.folders = folders
        self.hasLyrics = hasLyrics
        self.container = container
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
