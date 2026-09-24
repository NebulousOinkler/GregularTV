import Foundation

/// `{ "type": "all" }`: every item. Narrow it with the channel's `itemTypes`.
struct AllItemsSource: ChannelSource {
    static let type = "all"

    func matches(_ item: MediaItem) -> Bool { true }
}

/// `{ "type": "genre", "anyOf": ["Science Fiction", "Sci-Fi"] }`
///
/// Case-insensitive. List alternative spellings, because metadata providers
/// name genres differently.
struct GenreSource: ChannelSource {
    static let type = "genre"
    let anyOf: [String]

    func matches(_ item: MediaItem) -> Bool {
        item.genres.contains { anyOf.containsIgnoringCase($0) }
    }
}

/// `{ "type": "series", "anyOf": ["Star Trek: The Next Generation"] }`
///
/// Matches by series name (case-insensitive), never by Jellyfin ID.
struct SeriesSource: ChannelSource {
    static let type = "series"
    let anyOf: [String]

    func matches(_ item: MediaItem) -> Bool {
        item.seriesName.map { anyOf.containsIgnoringCase($0) } ?? false
    }
}

/// `{ "type": "years", "from": 1950, "to": 1979 }`: production year,
/// inclusive. Leave out either end to make it open. Items with no year never match.
struct YearRangeSource: ChannelSource {
    static let type = "years"
    let from: Int?
    let to: Int?

    func matches(_ item: MediaItem) -> Bool {
        guard let year = item.productionYear else { return false }
        return year >= (from ?? .min) && year <= (to ?? .max)
    }
}

/// `{ "type": "tag", "anyOf": ["Christmas"] }`: Jellyfin tags, case-insensitive.
struct TagSource: ChannelSource {
    static let type = "tag"
    let anyOf: [String]

    func matches(_ item: MediaItem) -> Bool {
        item.tags.contains { anyOf.containsIgnoringCase($0) }
    }
}

extension [String] {
    func containsIgnoringCase(_ value: String) -> Bool {
        contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}
