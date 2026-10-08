import GregularScreens
import JavaScriptKit

/// Karaoke in a browser: `KaraokeModel` drawn in its theme. Layers, from
/// the back: the theme's backdrop, the stage (the song, its lyrics, its
/// title card, or the attract screen), and karaoke's menus over it.
///
/// The keyboard works as the remote: arrows move the highlight, Enter
/// chooses, Escape steps back (`RemoteControls.karaokeMenus`), Space plays
/// or pauses the song (`.karaokeStage`); on the attract screen, any key
/// opens the menu. Touch and the mouse work everything too.
@MainActor final class KaraokePage: Page, KeyTarget {
    let element = El("main", "karaoke")
    private let model: KaraokeModel
    private let player: SongPlayer
    private let stage: KaraokeStageView
    private let menus = El("div", "k-menus")
    private let notice = El("div", "k-notice").attribute("role", "status").attribute("aria-live", "polite")
    private var menu: KaraokeMenu?
    private var drawnPlaces: [KaraokeModel.Place]?
    /// The item last highlighted in each menu, to come back to.
    private var highlighted: [KaraokeModel.Place: String] = [:]
    private var redraws: [Redraw] = []
    /// How many songs are on and queued, at the top of the menus.
    private let queueChip = El("p", "k-queue-chip")
    /// "Encore!" after a song sung to its end.
    private let encore = El("div", "k-encore").attribute("role", "status")
    /// What's been celebrated so far, and the stage as last seen, to tell what's new.
    private var queuedSeen = 0
    private var finishedSeen = 0
    private var lastState: KaraokeStage.State = .idle

    init(session: SpecialModeSession) {
        player = SongPlayer(check: session.checkFile)
        model = KaraokeModel(session: session, deck: player)
        stage = KaraokeStageView(model: model, player: player, pulseTarget: element)
        encore.hidden = true
        element.append(El("div", "k-backdrop", [KaraokeScene.element()]).attribute("aria-hidden", "true"),
                       stage.element, menus, queueChip, encore, notice)
        redraws = [
            Redraw { [weak self] in self?.drawTheme() },
            Redraw { [weak self] in self?.drawMenus() },
            Redraw { [weak self] in self?.drawNotice() },
            Redraw { [weak self] in self?.drawQueueChip() },
            Redraw { [weak self] in self?.celebrate() },
            Redraw { [weak self] in
                guard let self else { return }
                KaraokeSound.play(model.menuMusic)
                KaraokeSound.setMood(model.musicMood)
            },
        ]
        Keys.take(self)
    }

    func appeared() {
        menu?.appeared(highlighting: nil)
    }

    func close() {
        redraws.forEach { $0.stop() }
        menu?.close()
        stage.close()
        model.stage.stop()
        KaraokeSound.play(nil)
        Keys.release(self)
    }

    func press(_ button: RemoteButton) -> Bool {
        if model.isAttract {
            sound(.choose)
            model.leaveAttract()
            return true
        }
        guard model.place != nil else {
            guard let action = RemoteControls.karaokeStage[button] else { return false }
            model.perform(action)
            return true
        }
        if let direction = button.direction {
            let moved = Focus.move(direction, within: menus)
            if moved { sound(.move) }
            return moved
        }
        guard let action = RemoteControls.karaokeMenus[button] else { return false }
        if action == .stepBack {
            guard model.canGoBack else { return false }
            sound(.back)
        }
        model.perform(action)
        return true
    }

    private func sound(_ effect: KaraokeMusic.Effect) {
        KaraokeSound.effect(effect, in: model.shownTheme)
    }

    private func drawTheme() {
        element.attribute("data-theme", model.shownTheme.rawValue)
    }

    /// A new menu when the places change; each draws its own details.
    private func drawMenus() {
        let places = model.places
        element.classed("has-menu", !places.isEmpty)
        guard places != drawnPlaces else { return }
        let previous = drawnPlaces
        drawnPlaces = places
        if let menu, let key = menu.highlightedKey { highlighted[menu.place] = key }
        menu?.close()
        menu = places.last.map { KaraokeMenu(place: $0, model: model, sound: { [weak self] in self?.sound($0) }) }
        menus.replaceChildren(menu.map { [$0.element] } ?? [])
        // Back to a menu: the item that opened the one left.
        let returning = previous.map { places.count < $0.count } ?? false
        menu?.appeared(highlighting: returning ? places.last.flatMap { highlighted[$0] } : nil)
        if menu == nil { stage.focus() }
    }

    private func drawQueueChip() {
        let count = model.stage.queue.count + (model.stage.state.song == nil ? 0 : 1)
        let place = model.place
        queueChip.hidden = count == 0 || place == nil || place == .themes
        queueChip.text = "\u{266B} \(count)"
        queueChip.attribute("aria-label", "\(KaraokeModel.HomeItem.queue.title): \(count)")
    }

    /// Something to cheer: a song queued (its picture flies to the queue, in
    /// confetti), Play on a title card (a drum roll), or a song sung to its
    /// end ("Encore!").
    private func celebrate() {
        let queued = model.songsQueued
        let finished = model.stage.songsFinished
        let state = model.stage.state
        defer { (queuedSeen, finishedSeen, lastState) = (queued, finished, state) }
        if queued > queuedSeen, let song = model.lastQueued {
            KaraokeParts.confetti(into: element, x: 0.5, y: 0.55, pieces: 40)
            if !KaraokeParts.reducedMotion {
                let flying = El("div", "k-flying", [KaraokeParts.cover(KaraokeCover(song), size: "large")])
                element.append(flying)
                Task {
                    try? await Task.sleep(for: .seconds(0.9))
                    flying.remove()
                }
            }
            queueChip.classed("k-bounce", false)
            _ = queueChip.object.offsetWidth
            queueChip.classed("k-bounce", true)
        }
        if case .ready = lastState, case .singing = state { sound(.start) }
        if finished > finishedSeen, let song = model.stage.lastFinished {
            sound(.encore)
            encore.replaceChildren([KaraokeParts.title(KaraokeText.encore, "p", framed: true),
                                    El("p", "k-now", [KaraokeParts.cover(KaraokeCover(song), size: "small"),
                                                      El("span", text: KaraokeText.nowSinging(song))])])
            encore.hidden = false
            element.classed("k-cheering", true)
            KaraokeParts.confetti(into: element, x: 0.3, y: 0.4, pieces: 60)
            KaraokeParts.confetti(into: element, x: 0.7, y: 0.4, pieces: 60)
            Task { [encore, element] in
                try? await Task.sleep(for: .seconds(3.2))
                guard self.model.stage.songsFinished == finished else { return }
                encore.hidden = true
                element.classed("k-cheering", false)
            }
        }
    }

    private func drawNotice() {
        notice.text = model.notice ?? model.stage.notice ?? ""
        notice.hidden = notice.text.isEmpty
    }
}
