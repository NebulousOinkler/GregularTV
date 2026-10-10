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
    /// larger than `mostBytes`, or if `checkDownload(_:)` would.
    func download(_ url: URL, mostBytes: Int) async throws -> Data

    /// Throws unless `url` is a file this server may send as one of its
    /// own, by the rules every request follows: what `download(_:mostBytes:)`
    /// checks first, for a platform that fetches the file some other way
    /// (a browser, into its own memory).
    func checkDownload(_ url: URL) throws
}

/// Turns a scheduled item into something a player can play.
public protocol StreamSource: Sendable {
    /// The players the device has: the built-in one, and an add-on, if it has one.
    var players: [MediaStream.Player] { get }

    /// How to play `itemID`, at no more than `maxBitrate` bits per second
    /// (see `StreamingQuality`): as it is, on the first of `players` (in
    /// order) that plays it so, or else converted for the built-in player.
    func stream(for itemID: String, maxBitrate: Int, players: [MediaStream.Player]) async throws -> MediaStream

    /// Lets the server stop any work it's doing for `stream` (such as a
    /// transcode) now that the player is finished with it.
    func release(_ stream: MediaStream) async

    /// Tells the server the player still wants `stream`, so it carries on
    /// with the work it's doing for it. A player that has buffered enough
    /// stops asking for more (paused, or far enough ahead), and a server
    /// may take that as the player having gone, and stop. Only a stream
    /// with a `sessionID` has work to keep going.
    func keepAlive(_ stream: MediaStream) async

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

    /// Which of the device's players plays it.
    public enum Player: Sendable, Equatable {
        /// The platform's own: AVFoundation on Apple TV, `<video>` in a browser.
        case builtIn
        /// A player the app brings with it (VLC on Apple TV), where it has
        /// one: for files the platform's own can't play as they are, so the
        /// server needn't convert them, or any it plays as they are, when
        /// the viewer asks for it.
        case addOn
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
    public let player: Player

    public init(url: URL, delivery: Delivery, player: Player = .builtIn, reencodes: Bool = false,
                conversionReasons: [String] = [], sessionID: String? = nil) {
        self.url = url
        self.delivery = delivery
        self.player = player
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
