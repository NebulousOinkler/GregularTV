import Foundation

extension LocalPage {
    /// Karaoke's song picker: guests add songs to the queue from a phone on
    /// the home network. Off until it's turned on in karaoke's menu
    /// (`KaraokeModel.phonesAllowed`), never remembered, and served only on
    /// Apple TV while it's on.
    public static func songPicker(karaoke: KaraokeModel, hosts: Set<String>, code: String? = nil) -> LocalPage {
        LocalPage(html: SongPickerHTML.page, api: SongPickerAPI(karaoke: karaoke), hosts: hosts, code: code)
    }
}

/// The song picker page, from its files in `Picker/`.
enum SongPickerHTML {
    static let page = LocalPageHTML.page(title: "Gregular Karaoke", css: PackageResources.picker_css,
                                         body: PackageResources.picker_body_html, script: PackageResources.picker_js)
}

/// What the song picker asks, answered: the songbook (`/api/songs`), and
/// the queue (`/api/queue`: what's on, and adding a song). Phones are told
/// only songs' names (title, artists, album) and whether each is a video or
/// has lyrics: nothing else about the library or the server.
@MainActor final class SongPickerAPI: LocalPageAPI {
    static let songsPath = "/api/songs"
    static let queuePath = "/api/queue"
    /// The most songs phones may have waiting: more are turned down, so a
    /// phone can't flood the queue.
    static let mostQueued = 50

    private let karaoke: KaraokeModel

    init(karaoke: KaraokeModel) {
        self.karaoke = karaoke
    }

    func changes(_ path: String) -> Bool {
        path == Self.queuePath
    }

    func answer(_ method: String, _ path: String, _ body: Data) async -> HTTPResponse {
        switch (method, path) {
        case ("GET", Self.songsPath):
            return .json(Songs(songs: karaoke.songbook.songs.map(Song.init), stage: stage))
        case ("GET", Self.queuePath):
            return .json(stage)
        case ("POST", Self.queuePath):
            guard let id = try? JSONDecoder().decode(Add.self, from: body).id else {
                return .json(LocalPageFailure("That isn't a song."), status: 422)
            }
            guard karaoke.stage.queue.count < Self.mostQueued else {
                return .json(LocalPageFailure(KaraokeText.queueFull), status: 422)
            }
            guard karaoke.queueFromPhone(songID: id) else {
                return .json(LocalPageFailure(KaraokeText.notInSongbook), status: 422)
            }
            return .json(stage)
        case (_, Self.songsPath), (_, Self.queuePath):
            return .text(405, "Wrong method.")
        default:
            return .text(404, "Not found.")
        }
    }

    private var stage: Stage {
        Stage(now: karaoke.stage.state.song.map(Line.init), queue: karaoke.stage.queue.map(Line.init))
    }

    // MARK: - What it sends and takes

    struct Song: Encodable {
        let id, title, credit: String
        let album: String?
        let video, lyrics: Bool

        init(_ song: Songbook.Song) {
            id = song.id
            title = song.title
            credit = song.credit
            album = song.album
            video = song.isVideo
            lyrics = song.hasLyrics
        }
    }

    struct Line: Encodable {
        let title, credit: String

        init(_ song: Songbook.Song) {
            title = song.title
            credit = song.credit
        }
    }

    struct Stage: Encodable {
        let now: Line?
        let queue: [Line]
    }

    struct Songs: Encodable {
        let songs: [Song]
        let stage: Stage
    }

    struct Add: Decodable {
        let id: String
    }
}
