import Foundation
import GregularScreens
import JavaScriptKit

/// One of karaoke's menus (`KaraokeModel.Place`), drawn over the stage:
/// the theme boxes, the home menu, artists, albums, songs, search, or the
/// queue. Every item is a button, so the arrows, Enter, touch and the mouse
/// all work; each has a `data-key`, so the highlight can come back to it.
@MainActor final class KaraokeMenu {
    let place: KaraokeModel.Place
    let element: El
    private let model: KaraokeModel
    private let sound: (KaraokeMusic.Effect) -> Void
    private let body = El("div", "k-menu-body")
    private var redraws: [Redraw] = []

    init(place: KaraokeModel.Place, model: KaraokeModel, sound: @escaping (KaraokeMusic.Effect) -> Void) {
        self.place = place
        self.model = model
        self.sound = sound
        let heading = El("h1", "k-title", text: place.title)
        var bar: [El] = []
        if model.canGoBack {
            bar.append(El.button("Back", icon: .back, "icon-button k-back", labelHidden: true) {
                sound(.back)
                model.back()
            })
        }
        bar.append(heading)
        let hint = El("p", "k-hint", text: RemoteControls.hint(for: RemoteControls.karaokeMenus, names: KeyboardControls.names))
        element = El("section", "k-menu k-menu-\(Self.kind(of: place))", [El("header", "k-bar", bar), body, hint])
        element.attribute("aria-label", place.title)
        build()
    }

    /// The item highlighted now, to come back to.
    var highlightedKey: String? {
        guard let focused = DOM.focused, element.object.contains!(focused).boolean == true else { return nil }
        return focused.dataset.object?.key.string
    }

    /// Highlights the item with `key`, or the first.
    func appeared(highlighting key: String?) {
        let items = Focus.focusable(in: body)
        let item = key.flatMap { key in items.first { $0.object.dataset.key.string == key } } ?? items.first
        item?.focus()
        _ = item?.object.scrollIntoView!(JSObject.options(["block": "nearest"]))
    }

    func close() {
        redraws.forEach { $0.stop() }
    }

    private static func kind(of place: KaraokeModel.Place) -> String {
        switch place {
        case .themes: "themes"
        case .home: "home"
        case .artists, .albums: "groups"
        case .artist, .album, .songs: "songs"
        case .search: "search"
        case .queue: "queue"
        }
    }

    private func build() {
        switch place {
        case .themes: buildThemes()
        case .home: redraws.append(Redraw { [weak self] in self?.drawHome() })
        case .artists:
            body.replaceChildren([list(model.songbook.artists.map { artist in
                item(artist.name, detail: KaraokeText.songCount(artist.songCount), key: "artist-" + artist.name) { [model] in
                    model.open(.artist(artist.name))
                }
            })])
        case .albums:
            body.replaceChildren([list(model.songbook.albums.map(albumItem))])
        case .artist(let name):
            redraws.append(Redraw { [weak self] in self?.drawArtist(name) })
        case .album(let album):
            body.replaceChildren([surpriseItem(album.songs), list(album.songs.map(songItem))])
        case .songs:
            redraws.append(Redraw { [weak self] in
                guard let self else { return }
                body.replaceChildren([list(model.songbook.songs.map(songItem))])
            })
        case .search: buildSearch()
        case .queue: redraws.append(Redraw { [weak self] in self?.drawQueue() })
        }
    }

    // MARK: - Themes

    /// A box for each theme: its look in miniature, playing. Highlighting one
    /// samples it across the page, with its tune.
    private func buildThemes() {
        let boxes = KaraokeTheme.allCases.map { theme in
            let box = El("button", "k-theme-box", [
                El("span", "k-mini", (0..<5).map { El("span", "k-mini-\($0)") }).attribute("aria-hidden", "true"),
                El("span", "k-theme-name", text: theme.name),
                El("span", "k-theme-tagline", text: theme.tagline),
            ])
            box.attribute("type", "button").attribute("data-theme", theme.rawValue).attribute("data-key", theme.rawValue)
            box.on("focus") { [model] _ in model.preview(theme) }
            // A mouse pointing at it samples it; a tap just chooses it.
            box.on("pointerenter") { [model] event in
                if event.pointerType.string == "mouse" { model.preview(theme) }
            }
            box.on("click") { [model, sound] _ in
                sound(.choose)
                model.choose(theme)
            }
            return box
        }
        let grid = El("div", "k-theme-grid", boxes)
        grid.on("pointerleave") { [model] _ in
            if DOM.focused.map({ grid.object.contains!($0).boolean != true }) ?? true { model.preview(nil) }
        }
        grid.on("focusout") { [model] event in
            if event.relatedTarget.object.map({ grid.object.contains!($0).boolean != true }) ?? true { model.preview(nil) }
        }
        body.replaceChildren([grid])
    }

    // MARK: - Home

    private func drawHome() {
        let song = model.stage.state.song
        var parts: [El] = []
        if let song {
            parts.append(El("p", "k-now", text: "\u{266A} \(song.title) \u{2014} \(song.credit)"))
        }
        parts.append(El("div", "k-home-items", model.homeItems.map { homeItem in
            let classes = "k-item k-home-item" + (homeItem == .leave ? " k-leave" : homeItem == .surpriseMe ? " k-surprise" : "")
            let title = homeItem == .queue && !model.stage.queue.isEmpty ? "\(homeItem.title) (\(model.stage.queue.count))" : homeItem.title
            let button = El.button(title, classes) { [model, sound] in
                if homeItem == .leave {
                    Parts.confirm(model.leaveConfirmation) { model.leave() }
                    return
                }
                sound(homeItem == .surpriseMe ? .queue : .choose)
                model.choose(homeItem)
            }
            return button.attribute("data-key", "\(homeItem)")
        }))
        let focused = highlightedKey
        body.replaceChildren(parts)
        if let focused { Focus.focusable(in: body).first { $0.object.dataset.key.string == focused }?.focus() }
    }

    // MARK: - Artists, albums and songs

    private func drawArtist(_ name: String) {
        guard let artist = model.songbook.artist(named: name) else { return body.replaceChildren([]) }
        let songs = artist.albums.flatMap(\.songs)
        var parts = [surpriseItem(songs)]
        let titled = artist.albums.filter { $0.title != nil }
        if !titled.isEmpty { parts.append(list(titled.map(albumItem))) }
        if let loose = artist.albums.first(where: { $0.title == nil }) {
            if !titled.isEmpty { parts.append(El("h2", "k-subtitle", text: KaraokeText.otherSongs)) }
            parts.append(list(loose.songs.map(songItem)))
        }
        body.replaceChildren(parts)
    }

    private func albumItem(_ album: Songbook.Album) -> El {
        item(album.title ?? KaraokeText.otherSongs, detail: "\(album.artist) \u{00B7} \(KaraokeText.songCount(album.songs.count))",
             key: "album-" + album.id) { [model] in model.open(.album(album)) }
    }

    /// A song: chosen, it joins the queue.
    private func songItem(_ song: Songbook.Song) -> El {
        let badges = El("span", "k-badges")
        if song.isVideo { badges.append(El("span", "k-badge", text: KaraokeText.video)) }
        if !song.hasLyrics { badges.append(El("span", "k-badge k-badge-quiet", text: KaraokeText.noLyrics)) }
        let detail = [song.credit, song.album].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let row = item(song.title, detail: detail, key: "song-" + song.id) { [model, sound] in
            sound(.queue)
            model.queue(song)
        }
        row.append(badges)
        return row
    }

    private func surpriseItem(_ songs: [Songbook.Song]) -> El {
        El.button(KaraokeModel.HomeItem.surpriseMe.title, "k-item k-surprise") { [model, sound] in
            sound(.queue)
            model.surpriseMe(from: songs)
        }.attribute("data-key", "surprise")
    }

    private func item(_ title: String, detail: String?, key: String, action: @escaping @MainActor () -> Void) -> El {
        let text = El("span", "k-item-text", [El("span", "k-item-title", text: title)])
        if let detail, !detail.isEmpty { text.append(El("span", "k-item-detail", text: detail)) }
        let button = El("button", "k-item", [text])
        button.attribute("type", "button").attribute("data-key", key)
        button.on("click") { _ in action() }
        return button
    }

    private func list(_ items: [El]) -> El {
        items.isEmpty ? El("p", "k-empty", text: KaraokeText.noSongs) : El("div", "k-list", items)
    }

    // MARK: - Search

    private func buildSearch() {
        let field = El("input", "k-search-field")
        field.attribute("type", "search").attribute("placeholder", KaraokeText.searchPrompt)
            .attribute("aria-label", KaraokeText.searchPrompt).attribute("autocomplete", "off")
            .attribute("spellcheck", "false").attribute("enterkeyhint", "search")
        field.object.value = .string(model.query)
        let results = El("div", "k-results")
        field.on("input") { [model] _ in model.query = field.object.value.string ?? "" }
        // Down from the field to the results, as the arrows can't leave a text field otherwise.
        field.on("keydown") { event in
            guard event.key.string == "ArrowDown", let first = Focus.focusable(in: results).first else { return }
            _ = event.preventDefault!()
            first.focus()
        }
        body.replaceChildren([field, results])
        redraws.append(Redraw { [weak self] in
            guard let self else { return }
            let query = model.query
            let songs = model.songs
            results.replaceChildren(query.trimmingCharacters(in: .whitespaces).isEmpty ? []
                : songs.isEmpty ? [El("p", "k-empty", text: KaraokeText.nothingFound)] : [list(songs.map(songItem))])
        })
    }

    // MARK: - Queue

    private func drawQueue() {
        let queue = model.stage.queue
        let focused = highlightedKey
        var parts: [El] = []
        if let song = model.stage.state.song {
            parts.append(El("p", "k-now", text: "\u{266A} \(song.title) \u{2014} \(song.credit)"))
        }
        guard !queue.isEmpty else {
            body.replaceChildren(parts + [El("p", "k-empty", text: KaraokeText.emptyQueue)])
            return
        }
        parts.append(El("ol", "k-queue", queue.enumerated().map { index, song in
            let controls = El("span", "k-queue-controls", [
                El.button("Move \(song.title) up", icon: .chevronUp, "icon-button", labelHidden: true) { [model] in
                    model.stage.move(at: index, by: -1)
                }.attribute("data-key", "up-\(song.id)"),
                El.button("Move \(song.title) down", icon: .chevronDown, "icon-button", labelHidden: true) { [model] in
                    model.stage.move(at: index, by: 1)
                }.attribute("data-key", "down-\(song.id)"),
                El.button("Remove \(song.title)", icon: .close, "icon-button", labelHidden: true) { [model, sound] in
                    sound(.back)
                    model.stage.remove(at: index)
                }.attribute("data-key", "remove-\(song.id)"),
            ])
            return El("li", "k-queue-item", [
                El("span", "k-item-text", [El("span", "k-item-title", text: song.title), El("span", "k-item-detail", text: song.credit)]),
                controls,
            ])
        }))
        body.replaceChildren(parts)
        if let focused { Focus.focusable(in: body).first { $0.object.dataset.key.string == focused }?.focus() }
    }
}
