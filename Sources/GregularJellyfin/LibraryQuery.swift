import Foundation
import GregularCore

/// Fetches every playable episode and movie, and turns them into `MediaItem`s.
///
/// We only ask for the fields the schedule needs. We don't request images,
/// user data (watched state) or overviews.
struct LibraryQuery: Sendable {
    static let pageSize = 500
    /// Parallel page requests. Kept low so a small server (such as a
    /// Raspberry Pi) isn't swamped.
    static let maxConcurrentPages = 4

    let api: JellyfinAPI
    let userID: String

    func fetchAll() async throws -> [MediaItem] {
        // Episodes rarely carry genres or tags themselves, so they inherit them from their series.
        async let seriesList = fetchPages(types: "Series")
        async let playable = fetchPages(types: "Episode,Movie")
        let seriesMetadata = Dictionary(try await seriesList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var seen = Set<String>()
        return try await playable
            .compactMap { $0.mediaItem(series: $0.seriesId.flatMap { seriesMetadata[$0] }) }
            .filter { seen.insert($0.id).inserted }   // paging can overlap if the library changes mid-fetch
    }

    /// Every video in one library (a Jellyfin "view"), such as the
    /// commercials library. Only the fields a filler needs are requested.
    func fetchAll(inLibrary libraryID: String) async throws -> [MediaItem] {
        var seen = Set<String>()
        return try await fetchPages(types: "Video,Movie,Episode", parentID: libraryID)
            .compactMap { $0.mediaItem(series: nil) }
            .filter { seen.insert($0.id).inserted }
    }

    /// The first page reports the total. The rest are then fetched in
    /// parallel, a few at a time, and put back together in order.
    private func fetchPages(types: String, parentID: String? = nil) async throws -> [ItemDTO] {
        let first = try await fetchPage(types: types, parentID: parentID, startIndex: 0)
        let starts = Array(stride(from: first.items.count, to: first.totalRecordCount, by: Self.pageSize))
        guard !first.items.isEmpty, !starts.isEmpty else { return first.items }

        var pages: [Int: [ItemDTO]] = [:]
        try await withThrowingTaskGroup(of: (Int, [ItemDTO]).self) { group in
            var pending = starts.makeIterator()
            func addNext() {
                guard let start = pending.next() else { return }
                group.addTask { (start, try await fetchPage(types: types, parentID: parentID, startIndex: start).items) }
            }
            for _ in 0..<Self.maxConcurrentPages { addNext() }
            while let (start, items) = try await group.next() {
                pages[start] = items
                addNext()
            }
        }
        return first.items + starts.flatMap { pages[$0] ?? [] }
    }

    private func fetchPage(types: String, parentID: String?, startIndex: Int) async throws -> ItemsPage {
        try await api.get("/Items", query: query(types: types, parentID: parentID, startIndex: startIndex))
    }

    private func query(types: String, parentID: String?, startIndex: Int) -> [URLQueryItem] {
        (parentID.map { [URLQueryItem(name: "ParentId", value: $0)] } ?? []) + [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: types),
            URLQueryItem(name: "IsMissing", value: "false"),
            URLQueryItem(name: "Fields", value: "Genres,Tags"),
            URLQueryItem(name: "EnableImages", value: "false"),
            URLQueryItem(name: "EnableUserData", value: "false"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "StartIndex", value: String(startIndex)),
            URLQueryItem(name: "Limit", value: String(Self.pageSize)),
        ]
    }
}

// MARK: - DTOs

struct ItemsPage: Decodable, Sendable {
    let items: [ItemDTO]
    let totalRecordCount: Int
}

struct ItemDTO: Decodable, Sendable {
    let id: String
    let name: String?
    let type: String
    let runTimeTicks: Int64?
    let seriesId: String?
    let seriesName: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let productionYear: Int?
    let premiereDate: String?
    let genres: [String]?
    let tags: [String]?

    /// Nil for item types we don't schedule, or items with no runtime.
    func mediaItem(series: ItemDTO?) -> MediaItem? {
        guard let kind = Self.kind(forJellyfinType: type),
              let ticks = runTimeTicks, ticks > 0
        else { return nil }

        return MediaItem(
            id: id,
            kind: kind,
            name: name ?? "",
            duration: Ticks.seconds(ticks),
            seriesID: seriesId,
            seriesName: seriesName,
            seasonNumber: parentIndexNumber,
            episodeNumber: indexNumber,
            productionYear: productionYear ?? series?.productionYear,
            premiereDate: premiereDate.flatMap(Self.parseDate),
            genres: Self.union(genres, series?.genres),
            tags: Self.union(tags, series?.tags)
        )
    }

    /// Jellyfin's item types, as the schedule's kinds. Nil for any other type.
    static func kind(forJellyfinType type: String) -> MediaItem.Kind? {
        switch type {
        case "Episode": .episode
        case "Movie": .movie
        case "Video": .video
        default: nil
        }
    }

    /// Jellyfin sends dates like `2008-09-22T00:00:00.0000000Z`. The seven
    /// fractional digits trip up `ISO8601DateFormatter`, and ordering only
    /// needs whole seconds, so we drop them.
    static func parseDate(_ string: String) -> Date? {
        guard string.count >= 19 else { return nil }
        return try? Date(String(string.prefix(19)) + "Z", strategy: .iso8601)
    }

    private static func union(_ own: [String]?, _ inherited: [String]?) -> [String] {
        var seen = Set<String>()
        return ((own ?? []) + (inherited ?? [])).filter { seen.insert($0.lowercased()).inserted }
    }
}
