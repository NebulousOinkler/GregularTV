import Foundation
@testable import GregularCore

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

extension ChannelSchedule {
    /// The programmes at set times from `start` to `end`, each as its window:
    /// from its set time to the end of its slot. (For checking set times; the
    /// app only ever asks for the schedule as it airs.)
    func setTimeAirings(from start: Date, to end: Date) -> [Airing] {
        setTimeWindows(from: milliseconds(since: channel.epoch, to: start), to: milliseconds(since: channel.epoch, to: end))
            .map { window in
                Airing(item: window.item, start: date(atMilliseconds: window.start),
                       end: date(atMilliseconds: window.start + Self.milliseconds(of: window.item.duration)),
                       slotEnd: date(atMilliseconds: window.end), isFiller: false)
            }
    }
}

#if os(macOS)
extension Fixtures {
    /// Runs one of the repository's `scripts/`, for the checks the app build
    /// also runs. Its exit status, and everything it printed.
    static func runScript(_ name: String) throws -> (status: Int32, log: String) {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = repo.appendingPathComponent("scripts/\(name)")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
}
#endif
