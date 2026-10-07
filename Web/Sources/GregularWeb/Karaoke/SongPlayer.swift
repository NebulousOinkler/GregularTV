import Foundation
import GregularBrowser
import GregularScreens
import JavaScriptKit

/// `SongDeck` in a browser: each song fetched whole (`WholeFile`) and
/// played from memory in one `<video>`, which plays sound files too. Only
/// the song on is given a `blob:` URL, taken back as soon as it's off, so a
/// song is let go once nothing holds it.
@MainActor final class SongPlayer: SongDeck {
    /// The video, for the stage to show (a song's is hidden behind its lyrics).
    let video = El("video", "song-video")
    var onFinish: (() -> Void)?
    private var objectURL: String?

    init() {
        video.attribute("playsinline", "").attribute("preload", "auto").attribute("disableremoteplayback", "")
        video.on("ended") { [weak self] _ in self?.onFinish?() }
    }

    func load(_ url: URL, mostBytes: Int) async throws -> any SongFile {
        BrowserSong(blob: try await WholeFile.fetch(url, mostBytes: mostBytes))
    }

    func cue(_ file: any SongFile) {
        guard let file = file as? BrowserSong else { return }
        clear()
        let url = JSObject.global.URL.function!.createObjectURL!(file.blob).string!
        objectURL = url
        video.object.src = .string(url)
        _ = video.object.load!()
    }

    func play() {
        SoundUnlock.play(video)
    }

    func pause() {
        _ = video.object.pause!()
    }

    func restart() {
        video.object.currentTime = .number(0)
    }

    func clear() {
        video.emptyVideo()
        if let objectURL { _ = JSObject.global.URL.function!.revokeObjectURL!(objectURL) }
        objectURL = nil
    }

    var position: TimeInterval {
        video.object.currentTime.number ?? 0
    }
}

/// A song held in the browser's memory.
@MainActor final class BrowserSong: SongFile {
    let blob: JSObject
    init(blob: JSObject) { self.blob = blob }
}
