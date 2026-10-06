import Foundation
import GregularCore
import Observation

/// Karaoke's songs: the queue, and the song on stage.
///
/// - **Nothing stalls:** a song is fetched whole before it starts ("Get
///   ready!"), and the next in the queue is fetched while this one plays, so
///   usually there's no wait at all. Only one is fetched at a time.
/// - **Title card:** a loaded song waits, with its title and the queue, for
///   Play.
/// - A song that can't be loaded (the server would have to convert it, or
///   the fetch fails) is skipped with a notice, and leaves the songbook.
@MainActor @Observable
public final class KaraokeStage {
    public enum State: Equatable, Sendable {
        /// Nothing on or queued.
        case idle
        /// Being fetched: "Get ready!"
        case loading(Songbook.Song)
        /// On its title card, waiting for Play.
        case ready(Songbook.Song)
        case singing(Songbook.Song)
        case paused(Songbook.Song)

        /// The song on stage, if any.
        public var song: Songbook.Song? {
            switch self {
            case .idle: nil
            case .loading(let song), .ready(let song), .singing(let song), .paused(let song): song
            }
        }
    }

    /// The most one song may be: a long video at a high bitrate fits.
    public static let mostBytes = 300 * 1024 * 1024

    public private(set) var state: State = .idle
    /// The songs after the one on stage, in order.
    public private(set) var queue: [Songbook.Song] = []
    /// The song on stage's lyrics, once it's loaded (nil for a video, or none on the server).
    public private(set) var lyrics: LyricsTimeline?
    /// Something to say, such as a song skipped. Gone at the next change.
    public private(set) var notice: String?
    /// Told of a song that couldn't be loaded, to leave it out from now on.
    var onUnplayable: ((Songbook.Song) -> Void)?

    /// Seconds into the song on stage.
    public var position: TimeInterval { deck.position }

    private let deck: any SongDeck
    private let media: any LyricsSource & OriginalFiles
    /// The song on stage, held in memory.
    private var onStage: Loaded?
    /// The song on stage being fetched ("Get ready!").
    private var loading: Task<Loaded?, Never>?
    /// The next song, being fetched (or fetched) while this one plays.
    private var preload: (song: Songbook.Song, task: Task<Loaded?, Never>)?

    private struct Loaded: Sendable {
        let file: any SongFile
        let lyrics: LyricsTimeline?
    }

    init(deck: any SongDeck, media: any LyricsSource & OriginalFiles) {
        self.deck = deck
        self.media = media
        deck.onFinish = { [weak self] in self?.next() }
    }

    /// Adds `song` to the end of the queue; with nothing on, it loads at once.
    public func add(_ song: Songbook.Song) {
        notice = nil
        queue.append(song)
        if state == .idle { next() } else { preloadNext() }
    }

    public func remove(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        preloadNext()
    }

    /// Moves a queued song one place towards the front (`by: -1`) or back (`by: 1`).
    public func move(at index: Int, by offset: Int) {
        let target = index + offset
        guard queue.indices.contains(index), queue.indices.contains(target) else { return }
        queue.swapAt(index, target)
        preloadNext()
    }

    /// Play/Pause: starts the song on its title card, or pauses and resumes it.
    public func playOrPause() {
        switch state {
        case .ready(let song), .paused(let song):
            deck.play()
            state = .singing(song)
        case .singing(let song):
            deck.pause()
            state = .paused(song)
        case .idle, .loading:
            break
        }
    }

    /// The song on stage from its start.
    public func restart() {
        switch state {
        case .singing, .paused: deck.restart()
        case .idle, .loading, .ready: break
        }
    }

    /// Ends the song on stage, for the next one's title card.
    public func skip() {
        guard state != .idle else { return }
        next()
    }

    /// Stops everything and lets go of every song, for leaving karaoke.
    public func stop() {
        loading?.cancel()
        loading = nil
        preload?.task.cancel()
        preload = nil
        onStage = nil
        queue = []
        lyrics = nil
        deck.clear()
        state = .idle
    }

    // MARK: - Private

    /// The next song in the queue onto the stage, or nothing.
    private func next() {
        loading?.cancel()
        loading = nil
        onStage = nil
        lyrics = nil
        deck.clear()
        guard !queue.isEmpty else {
            state = .idle
            return
        }
        let song = queue.removeFirst()
        state = .loading(song)
        let loading: Task<Loaded?, Never>
        if let preload, preload.song == song {
            loading = preload.task
        } else {
            preload?.task.cancel()
            loading = load(song)
        }
        preload = nil
        self.loading = loading
        Task { [weak self] in
            let loaded = await loading.value
            guard let self, self.state == .loading(song) else { return }
            self.loading = nil
            guard let loaded else {
                self.notice = KaraokeText.skipped(song)
                self.onUnplayable?(song)
                return self.next()
            }
            self.onStage = loaded
            self.lyrics = loaded.lyrics
            self.deck.cue(loaded.file)
            self.state = .ready(song)
            self.preloadNext()
        }
    }

    /// Fetches the first song in the queue, unless it's already being fetched.
    /// Only while a song is on stage, so one song is fetched at a time.
    private func preloadNext() {
        guard let first = queue.first else {
            preload?.task.cancel()
            preload = nil
            return
        }
        guard preload?.song != first else { return }
        preload?.task.cancel()
        preload = nil
        switch state {
        case .ready, .singing, .paused: preload = (first, load(first))
        case .idle, .loading: break
        }
    }

    /// The song's file and lyrics, or nil if it can't be loaded.
    private func load(_ song: Songbook.Song) -> Task<Loaded?, Never> {
        let (deck, media) = (deck, media)
        return Task {
            guard let url = try? await media.originalFile(of: song.item) else { return nil }
            async let lyrics = song.isVideo || !song.item.hasLyrics ? nil : try? await media.lyrics(for: song.id)
            guard let file = try? await deck.load(url, mostBytes: Self.mostBytes), !Task.isCancelled else { return nil }
            return Loaded(file: file, lyrics: await lyrics.map(LyricsTimeline.init))
        }
    }
}
