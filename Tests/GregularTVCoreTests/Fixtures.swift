import Foundation
@testable import GregularTVCore

/// A small fake library for tests.
enum Fixtures {
    static func episode(
        _ series: String, s season: Int, e episode: Int,
        minutes: Double = 22, genres: [String] = [], year: Int? = nil
    ) -> MediaItem {
        MediaItem(
            id: "\(series)-s\(season)e\(episode)",
            kind: .episode,
            name: "\(series) S\(season)E\(episode)",
            duration: minutes * 60,
            seriesID: "id-\(series)",
            seriesName: series,
            seasonNumber: season,
            episodeNumber: episode,
            productionYear: year,
            genres: genres
        )
    }

    static func movie(_ name: String, minutes: Double = 100, year: Int? = nil, genres: [String] = [], tags: [String] = []) -> MediaItem {
        MediaItem(id: "movie-\(name)", kind: .movie, name: name, duration: minutes * 60,
                  productionYear: year, genres: genres, tags: tags)
    }

    static func series(_ name: String, seasons: Int, episodes: Int, minutes: Double = 22, genres: [String] = []) -> [MediaItem] {
        (1...seasons).flatMap { s in
            (1...episodes).map { e in episode(name, s: s, e: e, minutes: minutes, genres: genres) }
        }
    }

    /// Three series of different lengths, plus four movies.
    static let library: [MediaItem] =
        series("Alpha", seasons: 2, episodes: 5, genres: ["Comedy"])
        + series("Bravo", seasons: 1, episodes: 3, minutes: 44, genres: ["Drama"])
        + series("Charlie", seasons: 3, episodes: 4, minutes: 30, genres: ["Science Fiction", "Drama"])
        + [
            movie("Old Classic", minutes: 95, year: 1962, genres: ["Drama"]),
            movie("Explosions", minutes: 128, year: 2019, genres: ["Action"]),
            movie("Laughs", minutes: 91, year: 2005, genres: ["comedy"], tags: ["Christmas"]),
            movie("No Metadata", minutes: 80),
        ]

    static func channel(
        number: Int = 1,
        strategy: String = RandomShuffle.id,
        seed: UInt64 = 42,
        itemTypes: Set<MediaItem.Kind> = Set(MediaItem.Kind.allCases),
        source: any ChannelSource = AllItemsSource(),
        padTo: Int? = nil
    ) -> Channel {
        Channel(number: number, name: "Test \(number)", itemTypes: itemTypes, source: source,
                strategyID: strategy, seed: seed, padToMinutes: padTo)
    }
}
