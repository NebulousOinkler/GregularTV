import Foundation
import GregularCore
import Observation

extension SpecialMode.ID {
    /// Karaoke's id in special-modes.jsonc, for the front ends' tables of screens.
    public static let karaoke: Self = "karaoke"
}

/// Karaoke, the special mode: what its screens do, for each front end to
/// draw in its own theme.
///
/// **Where things are.** `places` is a stack of menus over the stage: the
/// last is on screen. Karaoke opens on the theme boxes (`.themes`); a theme
/// chosen, it's the home menu. With no menus, the stage shows: the song on
/// it, or, with nothing queued, the attract screen, which any button leaves
/// for the home menu. Back steps out of a menu to the one below, and from
/// the home menu to the song (never out of karaoke: only Leave Karaoke, in
/// the home menu, does that).
///
/// **Music.** `menuMusic` is the theme whose tune should play: while
/// menus, title cards and the attract screen show, never over a song.
@MainActor @Observable
public final class KaraokeModel {
    public enum Place: Hashable, Sendable {
        /// The theme boxes: where karaoke opens.
        case themes
        case home
        case artists
        /// An artist's albums, and their songs on no album.
        case artist(String)
        case albums
        case album(Songbook.Album)
        /// Every song, A to Z.
        case songs
        case search
        case queue

        /// Its heading.
        public var title: String {
            switch self {
            case .themes: KaraokeText.pickATheme
            case .home: KaraokeText.karaoke
            case .artists: HomeItem.artists.title
            case .artist(let name): name
            case .albums: HomeItem.albums.title
            case .album(let album): album.title ?? KaraokeText.otherSongs
            case .songs: HomeItem.songs.title
            case .search: HomeItem.search.title
            case .queue: HomeItem.queue.title
            }
        }
    }

    /// The home menu's items, in order.
    public enum HomeItem: Hashable, Sendable {
        case backToSong, restartSong, skipSong
        case artists, albums, songs, search, surpriseMe, queue, themes, leave

        public var title: String {
            switch self {
            case .backToSong: "Back to the Song"
            case .restartSong: "Start the Song Again"
            case .skipSong: "Skip This Song"
            case .artists: "Artists"
            case .albums: "Albums"
            case .songs: "All Songs"
            case .search: "Search"
            case .surpriseMe: "Surprise Me!"
            case .queue: "Queue"
            case .themes: "Change Theme"
            case .leave: KaraokeText.leave.action
            }
        }
    }

    /// The menus open, the one on screen last. Empty: the stage.
    public private(set) var places: [Place] = [.themes]
    /// The theme chosen. Karaoke opens on the theme boxes, so one is chosen before anything else.
    public private(set) var theme: KaraokeTheme = .neonDisco
    /// The theme box highlighted (focused or under the pointer): the page
    /// takes its look, and its tune plays, until another is.
    public private(set) var previewedTheme: KaraokeTheme?
    public private(set) var songbook: Songbook
    public let stage: KaraokeStage
    /// What's typed in Search.
    public var query = ""
    /// Something to say, such as a song queued. Gone at the next change.
    public private(set) var notice: String?

    private let session: SpecialModeSession
    private var hasChosenTheme = false

    public init(session: SpecialModeSession, deck: any SongDeck) {
        self.session = session
        songbook = Songbook(session.programmes, formats: session.formats)
        stage = KaraokeStage(deck: deck, media: session.media)
        stage.onUnplayable = { [weak self] song in
            guard let self else { return }
            songbook = songbook.removing(song)
        }
    }

    /// The menu on screen; nil for the stage.
    public var place: Place? { places.last }
    /// The stage, with a song on it, is on screen.
    public var isOnStage: Bool { places.isEmpty && stage.state != .idle }
    /// Nothing queued, and no menus: the attract screen.
    public var isAttract: Bool { places.isEmpty && stage.state == .idle }
    /// Whether `back()` goes anywhere: not from the theme boxes before a
    /// theme is chosen, nor from the home menu with nothing on stage.
    public var canGoBack: Bool {
        switch place {
        case .themes: hasChosenTheme
        case .home: stage.state != .idle
        default: true
        }
    }

    /// The look on screen: the highlighted theme box's, or the chosen theme's.
    public var shownTheme: KaraokeTheme { previewedTheme ?? theme }

    /// The theme whose tune plays now, or nil for quiet: never over a song,
    /// singing or paused.
    public var menuMusic: KaraokeTheme? {
        switch stage.state {
        case .singing: nil
        case .paused: places.isEmpty ? nil : shownTheme
        case .idle, .loading, .ready: shownTheme
        }
    }

    // MARK: - Themes

    /// A theme box is highlighted; nil when none is.
    public func preview(_ theme: KaraokeTheme?) {
        previewedTheme = theme
    }

    public func choose(_ theme: KaraokeTheme) {
        self.theme = theme
        previewedTheme = nil
        if hasChosenTheme { back() } else { places = [.home] }
        hasChosenTheme = true
    }

    // MARK: - Moving around

    public func open(_ place: Place) {
        notice = nil
        if place == .search { query = "" }
        places.append(place)
    }

    /// One step back: out of a menu, and from the home menu to the song on stage.
    public func back() {
        notice = nil
        guard let place else { return places = [.home] }
        switch place {
        case .themes where !hasChosenTheme:
            return
        case .home:
            if stage.state != .idle { places = [] }
        default:
            places.removeLast()
            previewedTheme = nil
        }
    }

    /// Any button on the attract screen: the home menu.
    public func leaveAttract() {
        places = [.home]
    }

    /// What a button does, by `RemoteControls.karaokeStage` and `.karaokeMenus`.
    public func perform(_ action: RemoteAction) {
        switch action {
        case .playOrPauseSong: stage.playOrPause()
        case .openKaraokeMenu: places = [.home]
        case .stepBack, .close: back()
        default: break
        }
    }

    /// The home menu: the song's controls when one is on, then everything else.
    public var homeItems: [HomeItem] {
        let song: [HomeItem] = switch stage.state {
        case .idle: []
        case .loading, .ready: [.backToSong, .skipSong]
        case .singing, .paused: [.backToSong, .restartSong, .skipSong]
        }
        return song + [.artists, .albums, .songs, .search, .surpriseMe, .queue, .themes, .leave]
    }

    /// Carries out a home menu item (except Leave, which asks first: `leave()`).
    public func choose(_ item: HomeItem) {
        switch item {
        case .backToSong: places = []
        case .restartSong: stage.restart(); places = []
        case .skipSong: stage.skip(); places = []
        case .artists: open(.artists)
        case .albums: open(.albums)
        case .songs: open(.songs)
        case .search: open(.search)
        case .surpriseMe: surpriseMe()
        case .queue: open(.queue)
        case .themes: open(.themes)
        case .leave: break
        }
    }

    // MARK: - Songs

    /// The songs a list shows: an album's, every song, or Search's.
    public var songs: [Songbook.Song] {
        switch place {
        case .album(let album): album.songs
        case .songs: songbook.songs
        case .search: songbook.search(query)
        default: []
        }
    }

    /// Queues `song`. With nothing on, the stage shows it loading; otherwise
    /// it says where in the queue it is.
    public func queue(_ song: Songbook.Song) {
        let wasIdle = stage.state == .idle
        stage.add(song)
        if wasIdle {
            places = []
        } else {
            notice = KaraokeText.queued(song, place: stage.queue.count)
        }
    }

    /// Queues a song at random: from `songs` (a list being looked at), or from them all.
    public func surpriseMe(from songs: [Songbook.Song]? = nil) {
        var random = SystemRandomNumberGenerator()
        guard let song = songbook.surprise(from: songs, using: &random) else { return }
        queue(song)
    }

    // MARK: - Leaving

    /// Asked before `leave()`.
    public var leaveConfirmation: Confirmation { KaraokeText.leave }

    /// Back to live TV, letting go of every song.
    public func leave() {
        stage.stop()
        session.exit()
    }
}
