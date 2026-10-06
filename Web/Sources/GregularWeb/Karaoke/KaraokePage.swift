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
    private let player = SongPlayer()
    private let stage: KaraokeStageView
    private let menus = El("div", "k-menus")
    private let notice = El("div", "k-notice").attribute("role", "status").attribute("aria-live", "polite")
    private var menu: KaraokeMenu?
    private var drawnPlaces: [KaraokeModel.Place]?
    /// The item last highlighted in each menu, to come back to.
    private var highlighted: [KaraokeModel.Place: String] = [:]
    private var redraws: [Redraw] = []

    init(session: SpecialModeSession) {
        model = KaraokeModel(session: session, deck: player)
        stage = KaraokeStageView(model: model, player: player)
        element.append(El("div", "k-backdrop", (0..<12).map { El("span", "k-sparkle k-sparkle-\($0)") })
                        .attribute("aria-hidden", "true"),
                       stage.element, menus, notice)
        redraws = [
            Redraw { [weak self] in self?.drawTheme() },
            Redraw { [weak self] in self?.drawMenus() },
            Redraw { [weak self] in self?.drawNotice() },
            Redraw { [weak self] in
                guard let self else { return }
                KaraokeSound.play(model.menuMusic)
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

    private func sound(_ effect: KaraokeSound.Effect) {
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

    private func drawNotice() {
        notice.text = model.notice ?? model.stage.notice ?? ""
        notice.hidden = notice.text.isEmpty
    }
}
