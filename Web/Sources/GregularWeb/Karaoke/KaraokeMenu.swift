import Foundation
import GregularScreens
import JavaScriptKit

/// One of karaoke's menus (`KaraokeModel.Place`), drawn over the stage:
/// the theme boxes, the home menu, artists, albums, songs, search, or the
/// queue. Every item is a button, so the arrows, Enter, touch and the mouse
/// all work; each has a `data-key`, so the highlight can come back to it.
/// Long lists have a rail of letters to jump by.
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
        var bar: [El] = []
        if model.canGoBack {
            bar.append(El.button("Back", icon: .back, "icon-button k-back", labelHidden: true) {
                sound(.back)
                model.back()
            })
        }
        var top: [El] = []
        if place == .themes {
            top = [KaraokeParts.title(KaraokeText.karaoke, framed: true), El("h2", "k-pick", text: place.title)]
        } else {
            bar.append(KaraokeParts.title(place.title, framed: place == .home))
        }
        let controls = model.menuControls
        let hint = controls.isEmpty ? [] : [El("p", "k-hint", text: RemoteControls.hint(for: controls, names: KeyboardControls.names))]
        element = El("section", "k-menu k-menu-\(Self.kind(of: place))", [El("header", "k-bar", bar + top)] + hint + [body])
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
        case .phones: "phones"
        }
    }

    private func build() {
        switch place {
        case .themes: buildThemes()
        case .home: redraws.append(Redraw { [weak self] in self?.drawHome() })
        case .artists:
            let artists = model.songbook.artists
            body.replaceChildren([list(artists.map { artist in
                item(artist.name, detail: KaraokeText.songCount(artist.songCount), key: "artist-" + artist.name,
                     cover: KaraokeParts.cover(KaraokeCover(artist.name), round: true)) { [model, sound] in
                    sound(.choose)
                    model.open(.artist(artist.name))
                }
            }, jumps: jumps(artists.map(\.name)) { "artist-" + artists[$0].name })])
        case .albums:
            let albums = model.songbook.albums
            body.replaceChildren([list(albums.map(albumItem), jumps: jumps(albums.map { $0.title ?? "" }) { "album-" + albums[$0].id })])
        case .artist(let name):
            redraws.append(Redraw { [weak self] in self?.drawArtist(name) })
        case .album(let album):
            body.replaceChildren([surpriseItem(album.songs), list(album.songs.map(songItem))])
        case .songs:
            redraws.append(Redraw { [weak self] in
                guard let self else { return }
                let songs = model.songbook.songs
                body.replaceChildren([list(songs.map(songItem), jumps: jumps(songs.map(\.title)) { "song-" + songs[$0].id })])
            })
        case .search: buildSearch()
        case .queue: redraws.append(Redraw { [weak self] in self?.drawQueue() })
        case .phones: break   // Apple TV only: the web version doesn't offer it (`KaraokeModel.offersPhones`)
        }
    }

    // MARK: - Themes

    /// A box for each theme: its scene in miniature, playing, with its
    /// lettering. Highlighting one samples it across the page, with its tune.
    private func buildThemes() {
        let boxes = KaraokeTheme.allCases.map { theme in
            let box = El("button", "k-theme-box", [
                El("span", "k-mini", [KaraokeScene.element(), KaraokeParts.title(KaraokeText.karaoke, "span")])
                    .attribute("aria-hidden", "true"),
                El("span", "k-theme-name", text: theme.name),
                El("span", "k-theme-tagline", text: theme.tagline),
            ])
            box.attribute("type", "button").attribute("data-theme", theme.rawValue).attribute("data-key", theme.rawValue)
            box.on("focus") { [model] _ in model.preview(theme) }
            // A mouse pointing at it samples it; a tap just chooses it.
            box.on("pointerenter") { [model] event in
                if event.pointerType.string == "mouse" { model.preview(theme) }
            }
            box.on("click") { [model] _ in
                KaraokeSound.effect(.theme, in: theme)
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

    private static func icon(_ item: KaraokeModel.HomeItem) -> Icon {
        switch item {
        case .backToSong: .play
        case .restartSong: .restart
        case .skipSong: .skip
        case .artists: .mic
        case .albums: .albums
        case .songs: .songs
        case .search: .search
        case .surpriseMe: .dice
        case .queue: .list
        case .phones: .phone
        case .themes: .palette
        case .leave: .door
        }
    }

    private func homeButton(_ homeItem: KaraokeModel.HomeItem, _ classes: String) -> El {
        let queued = homeItem == .queue ? model.stage.queue.count : 0
        let button = El.button(homeItem.title, icon: Self.icon(homeItem), classes) { [model, sound] in
            if homeItem == .leave {
                Parts.confirm(model.leaveConfirmation) { model.leave() }
                return
            }
            sound(homeItem == .surpriseMe ? .queue : .choose)
            model.choose(homeItem)
        }
        if queued > 0 {
            button.append(El("span", "k-count", text: "\(queued)").attribute("aria-hidden", "true"))
            button.attribute("aria-label", "\(homeItem.title) (\(queued))")
        }
        return button.attribute("data-key", "\(homeItem)")
    }

    private func drawHome() {
        let items = model.homeItems
        var parts: [El] = []
        if let song = model.stage.state.song { parts.append(nowSinging(song)) }
        let song = items.filter { $0.group == .song }
        if !song.isEmpty {
            parts.append(El("div", "k-song-controls", song.map { homeButton($0, "k-item k-big-button" + ($0 == .backToSong ? " k-prominent" : "")) }))
        }
        parts.append(El("div", "k-tiles", items.filter { $0.group == .songs }.enumerated().map { index, homeItem in
            homeButton(homeItem, "k-item k-tile" + (homeItem == .surpriseMe ? " k-prominent" : "")).styled("--i: \(index)")
        }))
        let next = model.stage.queue.prefix(3)
        if !next.isEmpty {
            parts.append(El("p", "k-up-next-strip", [El("strong", text: KaraokeText.upNext)] + next.flatMap { song in
                [KaraokeParts.cover(KaraokeCover(song), size: "small"), El("span", text: song.title)]
            }))
        }
        parts.append(El("div", "k-more", items.filter { $0.group == .more }.map { homeButton($0, "k-item k-small-button") }))
        let focused = highlightedKey
        body.replaceChildren(parts)
        if let focused { Focus.focusable(in: body).first { $0.object.dataset.key.string == focused }?.focus() }
    }

    private func nowSinging(_ song: Songbook.Song) -> El {
        El("p", "k-now", [KaraokeParts.cover(KaraokeCover(song), size: "small"), El("span", text: KaraokeText.nowSinging(song))])
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
             key: "album-" + album.id, cover: KaraokeParts.cover(KaraokeCover(album))) { [model, sound] in
            sound(.choose)
            model.open(.album(album))
        }
    }

    /// A song: chosen, it joins the queue.
    private func songItem(_ song: Songbook.Song) -> El {
        let badges = El("span", "k-badges")
        if song.isVideo { badges.append(KaraokeParts.badge(KaraokeText.video)) }
        if !song.hasLyrics { badges.append(KaraokeParts.badge(KaraokeText.noLyrics, quiet: true)) }
        let detail = [song.credit, song.album].compactMap { $0 }.joined(separator: " \u{00B7} ")
        let row = item(song.title, detail: detail, key: "song-" + song.id, cover: KaraokeParts.cover(KaraokeCover(song))) { [model, sound] in
            sound(.queue)
            model.queue(song)
        }
        row.append(badges)
        return row
    }

    private func surpriseItem(_ songs: [Songbook.Song]) -> El {
        El.button(KaraokeModel.HomeItem.surpriseMe.title, icon: .dice, "k-item k-surprise k-prominent") { [model, sound] in
            sound(.queue)
            model.surpriseMe(from: songs)
        }.attribute("data-key", "surprise")
    }

    private func item(_ title: String, detail: String?, key: String, cover: El? = nil, action: @escaping @MainActor () -> Void) -> El {
        let text = El("span", "k-item-text", [El("span", "k-item-title", text: title)])
        if let detail, !detail.isEmpty { text.append(El("span", "k-item-detail", text: detail)) }
        let button = El("button", "k-item k-row", (cover.map { [$0] } ?? []) + [text])
        button.attribute("type", "button").attribute("data-key", key)
        button.on("click") { _ in action() }
        return button
    }

    /// Where each letter starts in a list, as the key of its first row.
    private func jumps(_ names: [String], key: (Int) -> String) -> [(letter: String, key: String)] {
        Songbook.letters(of: names).map { ($0.letter, key($0.index)) }
    }

    private func list(_ items: [El], jumps: [(letter: String, key: String)] = []) -> El {
        guard !items.isEmpty else { return El("p", "k-empty", text: KaraokeText.noSongs) }
        for (index, item) in items.enumerated() { item.styled("--i: \(min(index, 12))") }
        let list = El("div", "k-list", items)
        guard !jumps.isEmpty else { return list }
        let rail = El("nav", "k-rail", jumps.map { jump in
            El.button(jump.letter, "k-rail-letter") { [list] in
                guard let row = Focus.focusable(in: list).first(where: { $0.object.dataset.key.string == jump.key }) else { return }
                row.focus()
                _ = row.object.scrollIntoView!(JSObject.options(["block": "start"]))
            }
            .attribute("aria-label", "Jump to \(jump.letter)")
            .attribute("data-key", "letter-" + jump.letter)
        }).attribute("aria-label", "Jump to a letter")
        return El("div", "k-list-wrap", [list, rail])
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
        if let song = model.stage.state.song { parts.append(nowSinging(song)) }
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
                El("span", "k-queue-number", text: "\(index + 1)").attribute("aria-hidden", "true"),
                KaraokeParts.cover(KaraokeCover(song)),
                El("span", "k-item-text", [El("span", "k-item-title", text: song.title), El("span", "k-item-detail", text: song.credit)]),
                controls,
            ]).styled("--i: \(min(index, 12))")
        }))
        body.replaceChildren(parts)
        if let focused { Focus.focusable(in: body).first { $0.object.dataset.key.string == focused }?.focus() }
    }
}
