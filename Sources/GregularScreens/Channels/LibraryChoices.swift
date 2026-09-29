import Foundation
import GregularCore

/// What the channel and set-times editors offer to pick from: names from the
/// library already in memory, sorted, with case-insensitive duplicates merged.
public struct LibraryChoices: Sendable {
    public let genres: [String]
    public let seriesNames: [String]
    public let tags: [String]
    public let movieNames: [String]
    /// The earliest and latest production years.
    public let years: ClosedRange<Int>?

    public init(_ library: [MediaItem]) {
        genres = Self.distinct(library.flatMap(\.genres))
        seriesNames = Self.distinct(library.compactMap(\.seriesName))
        tags = Self.distinct(library.flatMap(\.tags))
        movieNames = Self.distinct(library.filter { $0.kind == .movie }.map(\.name))
        let allYears = library.compactMap(\.productionYear)
        years = allYears.min().flatMap { low in allYears.max().map { low...$0 } }
    }

    private static func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

/// One line of an editor's preview: when, and what.
public struct UpcomingProgramme: Sendable, Identifiable {
    public let start: Date
    public let title: String
    public var id: Date { start }

    init(_ airing: Airing) {
        start = airing.start
        title = airing.item.displayTitle
    }
}
