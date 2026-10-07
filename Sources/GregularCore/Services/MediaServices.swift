import Foundation

// What the logic and the player need from a media server, and nothing more.
// `GregularJellyfin` provides these for Jellyfin; another server (or a test
// fake) only has to provide the same. Nothing here knows how a server is
// reached, signed in to, or what its API looks like.

/// Where a channel's programmes and commercials come from.
public protocol MediaLibrary: Sendable {
    /// Every item that can air as a programme, held in memory by the caller.
    func fetchProgrammes() async throws -> [MediaItem]

    /// The items of these kinds in the collection called `name`
    /// (case-insensitive), for example the commercials. Nil if there's no
    /// collection by that name.
    func fetchCollection(named name: String, kinds: Set<MediaItem.Kind>) async throws -> [MediaItem]?
}

/// Songs' words, timed to the music.
public protocol LyricsSource: Sendable {
    /// `itemID`'s lyrics, if the server has them timed. Nil if it has none,
    /// or only untimed words.
    func lyrics(for itemID: String) async throws -> SyncedLyrics?
}

/// Items' original files, for playing whole: fetched completely before they
/// play, so nothing can stall partway (unlike a `StreamSource`'s streams).
public protocol OriginalFiles: Sendable {
    /// Where `item`'s original file is, if this device plays it as it is.
    /// Nil if the server would have to convert it.
    func originalFile(of item: MediaItem) async throws -> URL?

    /// The whole of an `originalFile(of:)`, in memory (never on disk), for
    /// a platform whose player can't fetch it whole itself. Throws if it's
    /// larger than `mostBytes`.
    func download(_ url: URL, mostBytes: Int) async throws -> Data
}

/// Turns a scheduled item into something a player can play.
public protocol StreamSource: Sendable {
    /// How to play `itemID`, at no more than `maxBitrate` bits per second
    /// (see `StreamingQuality`).
    func stream(for itemID: String, maxBitrate: Int) async throws -> MediaStream

    /// Lets the server stop any work it's doing for `stream` (such as a
    /// transcode) now that the player is finished with it.
    func release(_ stream: MediaStream) async

    /// How fast the server can send data right now, in bits per second.
    func measureBandwidth() async throws -> Int
}

/// A playable stream for one item.
public struct MediaStream: Sendable, Equatable {
    public enum Delivery: Sendable, Equatable {
        /// The original file, played as it is.
        case original
        /// Streamed by the server: repackaged, or converted.
        case converted
    }

    public let url: URL
    public let delivery: Delivery
    /// The server has to re-encode it (not just repackage it). That's the
    /// expensive kind of conversion: a slow server may not keep up.
    public let reencodes: Bool
    /// Why the server is converting it, in plain words such as "container
    /// not supported" (for diagnostics). Empty for the original file.
    public let conversionReasons: [String]
    /// The server's handle on the work it's doing for this stream, for
    /// `StreamSource.release(_:)`. Nil when there's nothing to stop.
    public let sessionID: String?

    public init(url: URL, delivery: Delivery, reencodes: Bool = false,
                conversionReasons: [String] = [], sessionID: String? = nil) {
        self.url = url
        self.delivery = delivery
        self.reencodes = reencodes
        self.conversionReasons = conversionReasons
        self.sessionID = sessionID
    }
}

/// An error from a media server that says whether signing in again is the
/// only fix (the server rejected the session).
public protocol MediaServiceFailure: LocalizedError {
    var isSessionExpired: Bool { get }
}
