import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// Karaoke's stage: the song on it (a video, or a sound file with its
/// lyrics and the bouncing ball over the theme's backdrop), its title card
/// before Play, "Get ready!" while it loads, or, with nothing queued, the
/// attract screen.
@MainActor final class KaraokeStageView {
    let element = El("section", "k-stage")
    private let model: KaraokeModel
    private let player: SongPlayer
    private let card = El("div", "k-card")
    private let lyrics = LyricsView()
    private let paused = El("p", "k-paused", text: "Paused")
    private let controls = El("div", "k-controls")
    private let playPause: El
    private var redraws: [Redraw] = []
    /// Moves the lyrics on, every frame, while there are lyrics to show.
    private var frames: AnimationLoop?

    init(model: KaraokeModel, player: SongPlayer) {
        self.model = model
        self.player = player
        element.attribute("tabindex", "-1").attribute("aria-label", KaraokeText.karaoke)
        playPause = El.button("Play", icon: .play, "icon-button k-play", labelHidden: true) { [model] in
            model.stage.playOrPause()
        }
        let menu = El.button("Menu", icon: .list, "icon-button", labelHidden: true) { [model] in
            model.perform(.openKaraokeMenu)
        }
        controls.append(playPause, menu)
        element.append(player.video, lyrics.element, card, paused, controls)
        // The attract screen: anything at all opens the menu.
        element.on("click") { [model] _ in
            if model.isAttract { model.leaveAttract() }
        }
        redraws = [
            Redraw { [weak self] in self?.draw() },
            Redraw { [weak self] in self?.drawLyrics() },
        ]
    }

    func focus() {
        element.focus()
    }

    func close() {
        redraws.forEach { $0.stop() }
        frames?.stop()
    }

    private func draw() {
        let state = model.stage.state
        let song = state.song
        let onStage: Bool
        switch state {
        case .singing, .paused: onStage = true
        case .idle, .loading, .ready: onStage = false
        }
        element.classed("k-showing-video", onStage && song?.isVideo == true)
        element.classed("k-attract", state == .idle)
        paused.hidden = { if case .paused = state { false } else { true } }()
        let singing = { if case .singing = state { true } else { false } }()
        let (label, icon): (String, Icon) = singing ? ("Pause", .pause) : ("Play", .play)
        playPause.replaceChildren([icon.element])
        playPause.attribute("aria-label", label).attribute("title", label)
        controls.hidden = !onStage && { if case .ready = state { false } else { true } }()
        switch state {
        case .idle:
            card.replaceChildren(attract())
        case .loading(let song):
            card.replaceChildren([El("p", "k-big", text: KaraokeText.getReady), songTitle(song), Parts.spinner(KaraokeText.getReady)])
        case .ready(let song):
            let play = El.button(KaraokeText.pressPlay, "k-press-play") { [model] in model.stage.playOrPause() }
            var parts = [songTitle(song), play]
            let upNext = model.stage.queue.prefix(3)
            if !upNext.isEmpty {
                parts.append(El("div", "k-up-next", [El("h2", text: KaraokeText.upNext)]
                    + upNext.map { El("p", text: "\($0.title) \u{2014} \($0.credit)") }))
            }
            card.replaceChildren(parts)
        case .singing(let song), .paused(let song):
            // A video shows its own words; a song without timed lyrics shows its title.
            card.replaceChildren(song.isVideo || model.stage.lyrics != nil ? [] : [songTitle(song)])
        }
        card.hidden = card.object.childElementCount.number == 0
    }

    private func songTitle(_ song: Songbook.Song) -> El {
        let title = El("div", "k-song-title", [El("h1", text: song.title), El("p", "k-song-credit", text: song.credit)])
        if let album = song.album { title.append(El("p", "k-song-album", text: album)) }
        if !song.hasLyrics { title.append(El("span", "k-badge k-badge-quiet", text: KaraokeText.noLyrics)) }
        return title
    }

    /// "Pick a song!", with artists going by.
    private func attract() -> [El] {
        let artists = model.songbook.artists.prefix(24).map { El("span", text: $0.name) }
        return [
            El("p", "k-big k-attract-title", text: KaraokeText.pickASong),
            El("div", "k-marquee", [El("div", "k-marquee-track", artists + artists.map { El("span", text: $0.text) })])
                .attribute("aria-hidden", "true"),
            El("p", "k-any-button", text: KaraokeText.anyButton),
        ]
    }

    /// The lyrics show for a sound file with timed lyrics, from its title card on.
    private func drawLyrics() {
        let timeline: LyricsTimeline? = switch model.stage.state {
        case .ready(let song), .singing(let song), .paused(let song): song.isVideo ? nil : model.stage.lyrics
        case .idle, .loading: nil
        }
        lyrics.show(timeline)
        if timeline == nil {
            frames?.stop()
            frames = nil
        } else if frames == nil {
            frames = AnimationLoop { [weak self] in
                guard let self else { return }
                lyrics.update(at: player.position)
            }
        }
    }
}

/// Calls `tick` before every frame the browser draws, until `stop()`.
@MainActor final class AnimationLoop {
    private var closure: JSClosure?
    private var request: JSValue = .undefined

    init(_ tick: @escaping @MainActor () -> Void) {
        closure = JSClosure { [weak self] _ in
            MainActor.assumeIsolated {
                tick()
                self?.next()
            }
            return .undefined
        }
        next()
    }

    func stop() {
        _ = JSObject.global.cancelAnimationFrame!(request)
        closure = nil
    }

    private func next() {
        guard let closure else { return }
        request = JSObject.global.requestAnimationFrame!(closure)
    }
}
