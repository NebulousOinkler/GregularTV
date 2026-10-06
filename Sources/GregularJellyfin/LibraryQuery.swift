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
    /// The most items fetched of one kind, whatever total the server claims.
    /// Far beyond any real library; it stops a false total from planning
    /// billions of pages (and the app running out of memory at every launch).
    static let mostItems = 200_000
    /// The most text (bytes of IDs, names, genres and tags) one listing may
    /// hold. A real library of 100,000 items is about 10 MB; a server sending
    /// pages of huge names is stopped here, before it fills the app's memory.
    static let mostText = 64 * 1024 * 1024

    let api: JellyfinAPI
    let userID: String

    func fetchAll() async throws -> [MediaItem] {
        // Episodes rarely carry genres or tags themselves, so they inherit them from their series.
        async let seriesList = fetchPages(types: "Series", fields: "Genres,Tags")
        async let playable = fetchPages(types: "Episode,Movie", fields: "Genres,Tags")
        let seriesMetadata = Dictionary(try await seriesList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var seen = Set<String>()
        return try await playable
            .compactMap { $0.mediaItem(series: $0.seriesId.flatMap { seriesMetadata[$0] }) }
            .filter { seen.insert($0.id).inserted }   // paging can overlap if the library changes mid-fetch
    }

    /// Every item of `kinds` in one library (a Jellyfin "view"), such as the
    /// commercials library. Items in folders are told the folders' names
    /// (`MediaItem.folders`), for libraries arranged by folder.
    func fetchAll(inLibrary libraryID: String, kinds: Set<MediaItem.Kind>) async throws -> [MediaItem] {
        let types = MediaItem.Kind.allCases.filter(kinds.contains).map(ItemDTO.jellyfinType(for:))
        guard !types.isEmpty else { return [] }
        let items = try await fetchPages(types: types.joined(separator: ","), fields: "Genres,Tags,ParentId", parentID: libraryID)
        // The folders' names, only if something is in one.
        let inFolders = items.contains { $0.parentId != nil && $0.parentId != libraryID }
        let folders = inFolders ? try await fetchPages(types: "Folder", fields: "ParentId", parentID: libraryID) : []
        let foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func path(to parentID: String?) -> [String] {
            var names: [String] = [], next = parentID, seen = Set<String>()
            while let id = next, let folder = foldersByID[id], seen.insert(id).inserted {
                names.insert(folder.name ?? "", at: 0)
                next = folder.parentId
            }
            return names
        }
        var seen = Set<String>()
        return items
            .compactMap { $0.mediaItem(series: nil, folders: path(to: $0.parentId)) }
            .filter { seen.insert($0.id).inserted }
    }

    /// The first page reports the total. The rest are then fetched in
    /// parallel, a few at a time, and put back together in order. The total
    /// is only the server's word: it's capped at `mostItems`, pages stop
    /// being asked for once one comes back empty, each page counts for at
    /// most `pageSize` items, and all of them for at most `mostText` of text.
    private func fetchPages(types: String, fields: String, parentID: String? = nil) async throws -> [ItemDTO] {
        var text = 0
        func kept(_ items: [ItemDTO]) throws -> [ItemDTO] {
            let page = Array(items.prefix(Self.pageSize))
            text += page.reduce(0) { $0 + $1.textSize }
            guard text <= Self.mostText else { throw JellyfinError.responseTooLarge }
            return page
        }
        let first = try await fetchPage(types: types, fields: fields, parentID: parentID, startIndex: 0)
        let firstItems = try kept(first.items)
        let total = min(first.totalRecordCount, Self.mostItems)
        let starts = Array(stride(from: firstItems.count, to: total, by: Self.pageSize))
        guard !firstItems.isEmpty, !starts.isEmpty else { return firstItems }

        var pages: [Int: [ItemDTO]] = [:]
        try await withThrowingTaskGroup(of: (Int, [ItemDTO]).self) { group in
            var pending = starts.makeIterator()
            var reachedTheEnd = false
            func addNext() {
                guard !reachedTheEnd, let start = pending.next() else { return }
                group.addTask { (start, try await fetchPage(types: types, fields: fields, parentID: parentID, startIndex: start).items) }
            }
            for _ in 0..<Self.maxConcurrentPages { addNext() }
            while let (start, items) = try await group.next() {
                pages[start] = try kept(items)
                if items.isEmpty { reachedTheEnd = true }
                addNext()
            }
        }
        return firstItems + starts.flatMap { pages[$0] ?? [] }
    }

    private func fetchPage(types: String, fields: String, parentID: String?, startIndex: Int) async throws -> ItemsPage {
        try await api.get("/Items", query: query(types: types, fields: fields, parentID: parentID, startIndex: startIndex))
    }

    private func query(types: String, fields: String, parentID: String?, startIndex: Int) -> [URLQueryItem] {
        (parentID.map { [URLQueryItem(name: "ParentId", value: $0)] } ?? []) + [
            URLQueryItem(name: "userId", value: userID),
            URLQueryItem(name: "Recursive", value: "true"),
            URLQueryItem(name: "IncludeItemTypes", value: types),
            URLQueryItem(name: "IsMissing", value: "false"),
            URLQueryItem(name: "Fields", value: fields),
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
    let artists: [String]?
    let album: String?
    let hasLyrics: Bool?
    let container: String?
    /// The folder (or album, season…) it's in, when asked for.
    let parentId: String?

    /// Bytes of text it holds, for `LibraryQuery.mostText`.
    var textSize: Int {
        let texts = [id, name, type, seriesId, seriesName, premiereDate, album, container, parentId].compactMap { $0 }
            + (genres ?? []) + (tags ?? []) + (artists ?? [])
        return texts.reduce(0) { $0 + $1.utf8.count }
    }

    /// Nil for item types we don't play, or items with no runtime.
    /// - Parameter folders: the folders it's in within its library, outermost first.
    func mediaItem(series: ItemDTO?, folders: [String] = []) -> MediaItem? {
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
            tags: Self.union(tags, series?.tags),
            artists: artists ?? [],
            album: album,
            folders: folders,
            hasLyrics: hasLyrics ?? false,
            container: container
        )
    }

    /// Jellyfin's item types, as the schedule's kinds. Nil for any other type.
    static func kind(forJellyfinType type: String) -> MediaItem.Kind? {
        switch type {
        case "Episode": .episode
        case "Movie": .movie
        case "Video": .video
        case "Audio": .song
        case "MusicVideo": .musicVideo
        default: nil
        }
    }

    /// The Jellyfin item type for each kind (the other way from `kind(forJellyfinType:)`).
    static func jellyfinType(for kind: MediaItem.Kind) -> String {
        switch kind {
        case .episode: "Episode"
        case .movie: "Movie"
        case .video: "Video"
        case .song: "Audio"
        case .musicVideo: "MusicVideo"
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
