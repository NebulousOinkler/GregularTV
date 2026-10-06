import Foundation
import GregularCore

/// Every song karaoke can play, by artist, album and title, from a special
/// mode's programmes. Only files this device plays as they are are listed
/// (nothing converted, so nothing stalls); the server confirms each one as
/// it loads (`KaraokeStage`).
///
/// Songs come from tags (a Music or Music Videos library), or from folders
/// arranged Artist/Album/Title (a library of plain videos).
public struct Songbook: Sendable {
    public struct Song: Sendable, Hashable, Identifiable {
        public let item: MediaItem
        public var id: String { item.id }
        public var title: String { item.name }
        /// Who it's by, for grouping: the first artist.
        public let artist: String
        /// Everyone it's by, for showing: "ABBA, Benny Andersson".
        public let credit: String
        public let album: String?
        /// A video, with the words in the picture.
        public var isVideo: Bool { item.kind != .song }
        /// Something to sing along to: a video, or a song with lyrics.
        public var hasLyrics: Bool { isVideo || item.hasLyrics }

        public init(_ item: MediaItem) {
            self.item = item
            let folders = item.folders
            artist = item.artists.first ?? (folders.count >= 2 ? folders[folders.count - 2] : folders.first)
                ?? KaraokeText.unknownArtist
            credit = item.artists.isEmpty ? artist : item.artists.joined(separator: ", ")
            album = item.album ?? (folders.count >= 2 ? folders.last : nil)
        }
    }

    public struct Album: Sendable, Hashable, Identifiable {
        /// Nil for an artist's songs on no album.
        public let title: String?
        public let artist: String
        /// In title order.
        public let songs: [Song]
        public var id: String { "\(artist)\u{1F}\(title ?? "")" }
    }

    public struct Artist: Sendable, Hashable, Identifiable {
        public let name: String
        /// By title, with the songs on no album last.
        public let albums: [Album]
        public var id: String { name }
        public var songCount: Int { albums.reduce(0) { $0 + $1.songs.count } }
    }

    /// Every song, by title.
    public let songs: [Song]
    /// Every artist, by name.
    public let artists: [Artist]

    /// - Parameter formats: what this device plays; files it can't play as they are are left out.
    public init(_ items: [MediaItem], formats: PlayableFormats) {
        self.init(songs: items
            .filter { [.song, .musicVideo, .video].contains($0.kind) && $0.duration > 0 && formats.mightPlayAsIs($0.kind, container: $0.container) }
            .map(Song.init))
    }

    private init(songs: [Song]) {
        self.songs = songs.sorted { Self.ordered($0.title, $1.title, $0.id, $1.id) }
        artists = Dictionary(grouping: self.songs, by: \.artist).map { name, songs in
            let albums = Dictionary(grouping: songs, by: \.album).map { Album(title: $0.key, artist: name, songs: $0.value) }
            return Artist(name: name, albums: albums.sorted { a, b in
                switch (a.title, b.title) {
                case (nil, _): false
                case (_, nil): true
                case let (a?, b?): Self.ordered(a, b)
                }
            })
        }.sorted { Self.ordered($0.name, $1.name) }
    }

    /// Every album with a title, by title.
    public var albums: [Album] {
        artists.flatMap(\.albums).filter { $0.title != nil }.sorted { Self.ordered($0.title!, $1.title!, $0.artist, $1.artist) }
    }

    public func artist(named name: String) -> Artist? {
        artists.first { $0.name == name }
    }

    /// The songs whose title, artist or album has every word of `query` in
    /// it, whatever the case or accents. None for an empty query.
    public func search(_ query: String) -> [Song] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return songs.filter { song in
            let text = [song.title, song.credit, song.album ?? ""].joined(separator: " ")
            return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// A song at random from `songs` (every song unless told), preferring
    /// ones with something to sing along to.
    public func surprise(from songs: [Song]? = nil, using random: inout some RandomNumberGenerator) -> Song? {
        let pool = songs ?? self.songs
        return (pool.filter(\.hasLyrics).isEmpty ? pool : pool.filter(\.hasLyrics)).randomElement(using: &random)
    }

    /// Without `song`: one the server wouldn't play as it is, found as it loaded.
    public func removing(_ song: Song) -> Songbook {
        Songbook(songs: songs.filter { $0.id != song.id })
    }

    /// Case-insensitive, then by `tiebreak`, so the order never depends on the server's.
    private static func ordered(_ a: String, _ b: String, _ tiebreakA: String = "", _ tiebreakB: String = "") -> Bool {
        switch a.localizedCaseInsensitiveCompare(b) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: tiebreakA < tiebreakB
        }
    }
}
