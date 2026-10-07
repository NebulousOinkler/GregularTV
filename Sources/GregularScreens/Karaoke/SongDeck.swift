import Foundation

/// One player for whole songs: each file is fetched completely into memory
/// (never to disk) before it plays, so nothing can stall partway. Each
/// platform brings one (an `<audio>`/`<video>` element in a browser, AVPlayer
/// on Apple TV); `KaraokeStage` decides what it does. Live TV's
/// `PlayerDeck` streams instead, and is untouched by karaoke.
@MainActor public protocol SongDeck: AnyObject {
    /// Fetches the file at `url` whole. Throws if it can't, if it's larger
    /// than `mostBytes`, or when the task is cancelled (which stops the fetch).
    /// Dropping the result frees its memory.
    func load(_ url: URL, mostBytes: Int) async throws -> any SongFile
    /// Puts `file` on, paused at its start, in place of anything else.
    func cue(_ file: any SongFile)
    func play()
    func pause()
    /// Back to the start of the song, carrying on as it was (playing or paused).
    func restart()
    /// Nothing on, and nothing held.
    func clear()
    /// Seconds into the song on, for the lyrics.
    var position: TimeInterval { get }
    /// Called when the song on plays to its end.
    var onFinish: (() -> Void)? { get set }
}

/// A song held in memory by a `SongDeck`, ready to play.
@MainActor public protocol SongFile: AnyObject, Sendable {}
