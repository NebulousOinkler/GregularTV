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
    /// What a video is, for its first few seconds.
    private let strip = El("div", "k-video-strip")
    private let lyrics = LyricsView()
    private let paused = El("p", "k-paused", text: "Paused")
    private let controls = El("div", "k-controls")
    private let playPause: El
    private var redraws: [Redraw] = []
    /// Moves the lyrics on, every frame, while there are lyrics to show.
    private var frames: AnimationLoop?
    /// Where `--k-pulse` goes, for the backdrop to throb with the singing.
    private let pulseTarget: El

    init(model: KaraokeModel, player: SongPlayer, pulseTarget: El) {
        self.model = model
        self.player = player
        self.pulseTarget = pulseTarget
        element.attribute("tabindex", "-1").attribute("aria-label", KaraokeText.karaoke)
        playPause = El.button("Play", icon: .play, "icon-button k-play", labelHidden: true) { [model] in
            model.stage.playOrPause()
        }
        let menu = El.button("Menu", icon: .list, "icon-button", labelHidden: true) { [model] in
            model.perform(.openKaraokeMenu)
        }
        controls.append(playPause, menu)
        strip.hidden = true
        element.append(player.video, strip, lyrics.element, card, paused, controls)
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
        card.attribute("data-card", { switch state {
        case .idle: "attract"
        case .loading: "loading"
        case .ready: "ready"
        case .singing, .paused: "on"
        } }())
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
            card.replaceChildren([KaraokeParts.title(KaraokeText.getReady, "p"), songTitle(song), KaraokeParts.loader()])
        case .ready(let song):
            let play = El.button(KaraokeText.pressPlay, "k-press-play") { [model] in model.stage.playOrPause() }
            var parts = [songTitle(song), play]
            let upNext = model.stage.queue.prefix(3)
            if !upNext.isEmpty {
                parts.append(El("div", "k-up-next", [El("h2", text: KaraokeText.upNext)] + upNext.map {
                    El("p", [KaraokeParts.cover(KaraokeCover($0), size: "small"), El("span", text: KaraokeText.line($0))])
                }))
            }
            card.replaceChildren(parts)
        case .singing(let song), .paused(let song):
            // A video shows its own words, with what it is for a moment; a song without timed lyrics shows its title.
            if song.isVideo {
                card.replaceChildren([])
                if strip.object.dataset.song.string != song.id {
                    strip.replaceChildren([KaraokeParts.cover(KaraokeCover(song)),
                                           El("span", "k-item-text", [El("span", "k-item-title", text: song.title),
                                                                      El("span", "k-item-detail", text: song.credit)])])
                    strip.attribute("data-song", song.id)
                }
            } else {
                card.replaceChildren(model.stage.lyrics != nil ? [] : [songTitle(song)])
            }
        }
        strip.hidden = !(onStage && song?.isVideo == true)
        card.hidden = card.object.childElementCount.number == 0
    }

    /// The song's picture beside its title, artist and album.
    private func songTitle(_ song: Songbook.Song) -> El {
        let text = El("div", "k-song-text", [El("h1", text: song.title), El("p", "k-song-credit", text: song.credit)])
        if let album = song.album { text.append(El("p", "k-song-album", text: album)) }
        if !song.hasLyrics { text.append(KaraokeParts.badge(KaraokeText.noLyrics, quiet: true)) }
        return El("div", "k-song-title", [KaraokeParts.cover(KaraokeCover(song), size: "large"), text])
    }

    /// Karaoke's name, "Pick a song!", and artists going by.
    private func attract() -> [El] {
        let artists = model.songbook.artists.prefix(24).map { El("span", text: $0.name) }
        return [
            KaraokeParts.title(KaraokeText.karaoke, "p", framed: true),
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
            pulseTarget.style("--k-pulse", "0")
        } else if frames == nil {
            frames = AnimationLoop { [weak self] in
                guard let self else { return }
                let position = player.position
                lyrics.update(at: position)
                let singing = { if case .singing = self.model.stage.state { true } else { false } }()
                pulseTarget.style("--k-pulse", singing ? String(format: "%.3f", self.model.stage.lyrics?.pulse(at: position) ?? 0) : "0")
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
