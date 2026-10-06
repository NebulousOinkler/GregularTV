import GregularScreens
import SwiftUI

/// One of karaoke's menus (`KaraokeModel.Place`) over the stage: the theme
/// boxes, the home menu, artists, albums, songs, search, or the queue.
/// Menu steps back (`RemoteControls.karaokeMenus`); never out of karaoke.
struct KaraokeMenuView: View {
    let place: KaraokeModel.Place
    @Bindable var model: KaraokeModel
    @FocusState private var focus: String?
    @State private var confirmingLeave = false

    private var style: KaraokeStyle { KaraokeStyle(model.shownTheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(style.cased(place.title))
                .font(style.font(72))
                .foregroundStyle(style.accent)
                .shadow(color: style.accent.opacity(0.6), radius: 16)
                .lineLimit(1)
            content
            Text(RemoteControls.hint(for: RemoteControls.karaokeMenus))
                .font(.caption)
                .foregroundStyle(style.inkSoft)
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .remoteControls(RemoteControls.karaokeMenus, takesArrows: false) { action in
            if action == .stepBack {
                guard model.canGoBack else { return }
                sound(.back)
            }
            model.perform(action)
        }
        .onChange(of: focus) { old, new in
            if old != nil, new != nil { sound(.move) }
        }
        .confirming(model.leaveConfirmation, isPresented: $confirmingLeave) { model.leave() }
    }

    private func sound(_ effect: KaraokeMusic.Effect) {
        KaraokeSynth.shared.effect(effect, in: model.shownTheme)
    }

    @ViewBuilder private var content: some View {
        switch place {
        case .themes: themes
        case .home: home
        case .artists:
            list(model.songbook.artists.map { artist in
                item(artist.name, detail: KaraokeText.songCount(artist.songCount), key: "artist-" + artist.name) {
                    model.open(.artist(artist.name))
                }
            })
        case .albums:
            list(model.songbook.albums.map(albumItem))
        case .artist(let name):
            let artist = model.songbook.artist(named: name)
            let albums = artist?.albums.filter { $0.title != nil } ?? []
            let loose = artist?.albums.first { $0.title == nil }?.songs ?? []
            list([surpriseItem(artist?.albums.flatMap(\.songs) ?? [])] + albums.map(albumItem) + loose.map(songItem))
        case .album(let album):
            list([surpriseItem(album.songs)] + album.songs.map(songItem))
        case .songs:
            list(model.songbook.songs.map(songItem))
        case .search:
            VStack(alignment: .leading, spacing: 24) {
                TextField(KaraokeText.searchPrompt, text: $model.query)
                    .autocorrectionDisabled()
                    .focused($focus, equals: "search")
                if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if model.songs.isEmpty {
                        Text(KaraokeText.nothingFound).foregroundStyle(style.inkSoft)
                    } else {
                        list(model.songs.map(songItem))
                    }
                }
            }
            .defaultFocus($focus, "search")
        case .queue: queue
        }
    }

    // MARK: - Themes

    /// A box for each theme, its backdrop playing in miniature. Highlighting
    /// one samples it across the screen, with its tune.
    private var themes: some View {
        HStack(spacing: 40) {
            ForEach(KaraokeTheme.allCases) { theme in
                let boxStyle = KaraokeStyle(theme)
                Button {
                    sound(.choose)
                    model.choose(theme)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        KaraokeBackdrop(theme: theme)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        Text(boxStyle.cased(theme.name)).font(boxStyle.font(34)).foregroundStyle(boxStyle.accent)
                        Text(theme.tagline).font(.caption).foregroundStyle(boxStyle.inkSoft).lineLimit(2)
                    }
                    .padding(20)
                    .background(LinearGradient(colors: boxStyle.background, startPoint: .top, endPoint: .bottom),
                                in: RoundedRectangle(cornerRadius: 28))
                }
                .buttonStyle(KaraokeBoxStyle(accent: boxStyle.accent))
                .focused($focus, equals: theme.rawValue)
            }
        }
        .focusSection()
        .defaultFocus($focus, model.theme.rawValue)
        .onChange(of: focus) { _, key in
            model.preview(key.flatMap(KaraokeTheme.init(rawValue:)))
        }
    }

    // MARK: - Home

    private var home: some View {
        let song = model.stage.state.song
        return VStack(alignment: .leading, spacing: 24) {
            if let song { nowSinging(song) }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible(), spacing: 32)], spacing: 24) {
                ForEach(model.homeItems, id: \.self) { homeItem in
                    let count = homeItem == .queue && !model.stage.queue.isEmpty ? " (\(model.stage.queue.count))" : ""
                    item(homeItem.title + count, key: "\(homeItem)", centred: true) {
                        if homeItem == .leave { return confirmingLeave = true }
                        sound(homeItem == .surpriseMe ? .queue : .choose)
                        model.choose(homeItem)
                    }
                }
            }
        }
    }

    private func nowSinging(_ song: Songbook.Song) -> some View {
        Text("\u{266A} \(song.title) \u{2014} \(song.credit)")
            .font(style.font(30))
            .foregroundStyle(style.inkSoft)
            .padding(20)
            .background(style.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Songs

    private func albumItem(_ album: Songbook.Album) -> AnyView {
        item(album.title ?? KaraokeText.otherSongs, detail: "\(album.artist) \u{00B7} \(KaraokeText.songCount(album.songs.count))",
             key: "album-" + album.id) { model.open(.album(album)) }
    }

    /// A song: chosen, it joins the queue.
    private func songItem(_ song: Songbook.Song) -> AnyView {
        var badges: [String] = []
        if song.isVideo { badges.append(KaraokeText.video) }
        if !song.hasLyrics { badges.append(KaraokeText.noLyrics) }
        return item(song.title, detail: [song.credit, song.album].compactMap { $0 }.joined(separator: " \u{00B7} "),
                    badges: badges, key: "song-" + song.id) {
            sound(.queue)
            model.queue(song)
        }
    }

    private func surpriseItem(_ songs: [Songbook.Song]) -> AnyView {
        item(KaraokeModel.HomeItem.surpriseMe.title, key: "surprise", centred: true) {
            sound(.queue)
            model.surpriseMe(from: songs)
        }
    }

    private func item(_ title: String, detail: String? = nil, badges: [String] = [], key: String, centred: Bool = false,
                      action: @escaping () -> Void) -> AnyView {
        AnyView(Button(action: action) {
            HStack(spacing: 20) {
                VStack(alignment: centred ? .center : .leading, spacing: 6) {
                    Text(style.cased(title)).font(style.font(32)).lineLimit(1)
                    if let detail, !detail.isEmpty { Text(detail).font(.caption).opacity(0.75).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: centred ? .center : .leading)
                ForEach(badges, id: \.self) { badge in
                    Text(badge).font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 4)
                        .background(style.accent2.opacity(0.85), in: Capsule())
                }
            }
        }
        .buttonStyle(KaraokeItemStyle(style: style))
        .focused($focus, equals: key))
    }

    private func list(_ items: [AnyView]) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if items.isEmpty {
                    Text(KaraokeText.noSongs).foregroundStyle(style.inkSoft)
                }
                ForEach(items.indices, id: \.self) { items[$0] }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
    }

    // MARK: - Queue

    private var queue: some View {
        let queue = model.stage.queue
        return VStack(alignment: .leading, spacing: 20) {
            if let song = model.stage.state.song { nowSinging(song) }
            if queue.isEmpty {
                Text(KaraokeText.emptyQueue).foregroundStyle(style.inkSoft)
            }
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(queue.enumerated()), id: \.element.id) { index, song in
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Text(style.cased(song.title)).font(style.font(32))
                                Text(song.credit).font(.caption).opacity(0.75)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            queueButton("chevron.up", "Move \(song.title) up", key: "up-" + song.id) { model.stage.move(at: index, by: -1) }
                            queueButton("chevron.down", "Move \(song.title) down", key: "down-" + song.id) { model.stage.move(at: index, by: 1) }
                            queueButton("xmark", "Remove \(song.title)", key: "remove-" + song.id) {
                                sound(.back)
                                model.stage.remove(at: index)
                            }
                        }
                        .foregroundStyle(style.ink)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(style.item, in: RoundedRectangle(cornerRadius: 18))
                        .focusSection()
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }

    private func queueButton(_ symbol: String, _ label: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .accessibilityLabel(label)
            .buttonStyle(KaraokeItemStyle(style: style, compact: true))
            .focused($focus, equals: key)
    }
}

/// A karaoke row or button: lit in the theme's accent when highlighted.
struct KaraokeItemStyle: ButtonStyle {
    let style: KaraokeStyle
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Item(configuration: configuration, style: style, compact: compact)
    }

    private struct Item: View {
        let configuration: ButtonStyleConfiguration
        let style: KaraokeStyle
        let compact: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(isFocused ? style.card.opacity(1) : style.ink)
                .padding(.horizontal, compact ? 24 : 32)
                .padding(.vertical, compact ? 16 : 22)
                .background(isFocused ? style.accent : style.item, in: RoundedRectangle(cornerRadius: 18))
                .scaleEffect(isFocused ? 1.04 : configuration.isPressed ? 0.98 : 1)
                .shadow(color: style.accent.opacity(isFocused ? 0.7 : 0), radius: 20)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// A theme box: grows and glows in its own accent when highlighted.
private struct KaraokeBoxStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        Box(configuration: configuration, accent: accent)
    }

    private struct Box: View {
        let configuration: ButtonStyleConfiguration
        let accent: Color
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(accent, lineWidth: isFocused ? 6 : 0))
                .scaleEffect(isFocused ? 1.06 : 1)
                .shadow(color: accent.opacity(isFocused ? 0.8 : 0), radius: 30)
                .animation(.easeOut(duration: 0.2), value: isFocused)
        }
    }
}
