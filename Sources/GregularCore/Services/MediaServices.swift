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

/// Items' files, for playing whole: fetched completely before they play,
/// so nothing can stall partway (unlike a `StreamSource`'s streams).
public protocol WholeFiles: Sendable {
    /// Where `item`'s file is, to fetch whole: the original, if this device
    /// plays it as it is; else, for a song, the server's conversion of it to
    /// a sound format the device plays, made as it's fetched. Nil for
    /// anything else the server would have to convert (a video).
    func wholeFile(of item: MediaItem) async throws -> URL?

    /// The whole of a `wholeFile(of:)`, in memory (never on disk), for
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

    /// The most sound channels a stream converted for the built-in player
    /// carries (more are mixed down).
    var mostSoundChannels: Int { get }

    /// What a conversion for the built-in player ends up as, which every
    /// player plays: never ruled out by a failure (`StreamRequest.unplayable`).
    var safestFormats: Set<MediaFormat> { get }

    /// How to play `itemID`, as `request` asks: as it is, on the first of its
    /// players (in order) that plays it so, or else converted for the
    /// built-in player.
    func stream(for itemID: String, _ request: StreamRequest) async throws -> MediaStream

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

/// What to ask a server for, for one stream.
public struct StreamRequest: Sendable, Equatable {
    /// At most this many bits per second (see `StreamingQuality`).
    public var maxBitrate: Int
    /// The players to ask about for playing the file as it is, in order.
    public var players: [MediaStream.Player]
    /// Sound the server converts is mixed down to stereo: less work for it.
    public var stereoSound: Bool
    /// What each player turned out not to decode, this session: left out of
    /// what it's said to play, so the server sends something else.
    public var unplayable: [MediaStream.Player: Set<MediaFormat>]

    public init(maxBitrate: Int, players: [MediaStream.Player], stereoSound: Bool = false,
                unplayable: [MediaStream.Player: Set<MediaFormat>] = [:]) {
        self.maxBitrate = maxBitrate
        self.players = players
        self.stereoSound = stereoSound
        self.unplayable = unplayable
    }
}

/// A video or sound format, in the names media servers use: a codec such as
/// "hevc" or "eac3", and for video its profile where it matters, such as
/// "main 10". Lowercase.
public struct MediaFormat: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Sendable { case video, sound }

    public let kind: Kind
    public let codec: String
    /// The video profile, or nil for any (and always for sound).
    public let profile: String?

    public init(_ kind: Kind, _ codec: String, profile: String? = nil) {
        self.kind = kind
        self.codec = codec.lowercased()
        self.profile = profile?.lowercased()
    }

    public var description: String { [codec, profile].compactMap { $0 }.joined(separator: " ") }
}

/// What a stream carries, as the server says: its video and its sound, as
/// they reach the player (a conversion's output, or the file's own where
/// it's copied). Read for one thing only: learning what a player can't decode.
public struct StreamContents: Sendable, Equatable {
    public var video: MediaFormat?
    public var sound: MediaFormat?

    public init(video: MediaFormat? = nil, sound: MediaFormat? = nil) {
        self.video = video
        self.sound = sound
    }

    /// Its formats, the sound first: cheaper to convert if it's the one at fault.
    public var formats: [MediaFormat] { [sound, video].compactMap { $0 } }
}

/// A playable stream for one item.
public struct MediaStream: Sendable, Equatable {
    /// How the server sends it, from no work to the most.
    public enum Delivery: Sendable, Equatable {
        /// The original file, played as it is.
        case original
        /// Streamed by the server, with only the container changed: cheap.
        case repackaged
        /// Streamed by the server with its sound converted (the video copied
        /// as it is): the server has to keep up, but with little work.
        case soundConverted
        /// Streamed by the server with its video re-encoded (whatever the
        /// sound): the expensive kind, which a slow server may not keep up with.
        case reencoded

        /// The server converts it (its sound or its video): it has to keep up.
        public var isConverted: Bool { self == .soundConverted || self == .reencoded }
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
    /// Why the server is converting it, in plain words such as "container
    /// not supported" (for diagnostics). Empty for the original file.
    public let conversionReasons: [String]
    /// The server's handle on the work it's doing for this stream, for
    /// `StreamSource.release(_:)`. Nil when there's nothing to stop.
    public let sessionID: String?
    public let player: Player
    /// What it carries, as far as the server says.
    public let contents: StreamContents

    /// The server has to re-encode its video: the expensive kind of
    /// conversion (`Delivery.reencoded`).
    public var reencodes: Bool { delivery == .reencoded }

    public init(url: URL, delivery: Delivery, player: Player = .builtIn,
                conversionReasons: [String] = [], sessionID: String? = nil, contents: StreamContents = StreamContents()) {
        self.url = url
        self.delivery = delivery
        self.player = player
        self.contents = contents
        self.conversionReasons = conversionReasons
        self.sessionID = sessionID
    }
}

/// An error from a media server that says whether signing in again is the
/// only fix (the server rejected the session).
/// A player couldn't decode what it was sent: the format's fault, not the
/// connection's or the server's. (A player's errors say so by conforming.)
public protocol UnplayableMedia: Error {}

/// A failure that's the connection's: it dropped, or couldn't carry the
/// stream fast enough. A lower quality may help, where a server's own
/// error, or a file a player can't show, wouldn't. (A player's or a
/// network's errors say so by conforming.)
public protocol ConnectionFailure: Error {}

public protocol MediaServiceFailure: LocalizedError {
    var isSessionExpired: Bool { get }
}
