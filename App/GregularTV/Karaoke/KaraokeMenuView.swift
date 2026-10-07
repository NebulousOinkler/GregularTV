import GregularScreens
import SwiftUI

/// One of karaoke's menus (`KaraokeModel.Place`) over the stage: the theme
/// boxes, the home menu, artists, albums, songs, search, or the queue.
/// Menu steps back (`RemoteControls.karaokeMenus`); never out of karaoke.
///
/// Long lists have a rail of letters on the right, to jump through them.
struct KaraokeMenuView: View {
    let place: KaraokeModel.Place
    @Bindable var model: KaraokeModel
    /// The song picker's server, for Songs from Phones.
    let phones: LocalPageServer
    @FocusState private var focus: String?
    @State private var confirmingLeave = false
    @State private var ladder = BlipLadder()

    private var style: KaraokeStyle { KaraokeStyle(model.shownTheme) }
    private var theme: KaraokeTheme { model.shownTheme }

    var body: some View {
        Group {
            if place == .themes {
                themes
            } else {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        KaraokeTitle(text: place.title, size: place == .home ? 96 : 72, theme: theme, framed: place == .home)
                            .frame(maxWidth: 1300, alignment: .leading)
                            .padding(.leading, place == .home && theme == .vegasLounge ? 48 : 0)
                        hint
                    }
                    content
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .remoteControls(RemoteControls.karaokeMenus, takesArrows: false) { action in
            if action == .stepBack {
                guard model.canGoBack else { return }
                sound(.back)
            }
            model.perform(action)
        }
        .onChange(of: focus) { old, new in
            if old != nil, new != nil { KaraokeSynth.shared.effect(.move, in: theme, step: ladder.step(at: Date.now.timeIntervalSinceReferenceDate)) }
        }
        .confirming(model.leaveConfirmation, isPresented: $confirmingLeave) { model.leave() }
    }

    /// The buttons that work here, if any do.
    @ViewBuilder private var hint: some View {
        let controls = model.menuControls
        if !controls.isEmpty {
            Text(RemoteControls.hint(for: controls))
                .font(.caption)
                .foregroundStyle(style.inkSoft)
        }
    }

    private func sound(_ effect: KaraokeMusic.Effect) {
        KaraokeSynth.shared.effect(effect, in: theme)
    }

    @ViewBuilder private var content: some View {
        switch place {
        case .themes: EmptyView()
        case .home: home
        case .artists:
            let artists = model.songbook.artists
            list(artists.map { artist in
                item(artist.name, detail: KaraokeText.songCount(artist.songCount), key: "artist-" + artist.name,
                     cover: KaraokeCover(artist.name), round: true) {
                    sound(.choose)
                    model.open(.artist(artist.name))
                }
            }, jumps: jumps(artists.map(\.name)) { "artist-" + artists[$0].name })
        case .albums:
            let albums = model.songbook.albums
            list(albums.map(albumItem), jumps: jumps(albums.map { $0.title ?? "" }) { "album-" + albums[$0].id })
        case .artist(let name):
            let artist = model.songbook.artist(named: name)
            let albums = artist?.albums.filter { $0.title != nil } ?? []
            let loose = artist?.albums.first { $0.title == nil }?.songs ?? []
            list([surpriseItem(artist?.albums.flatMap(\.songs) ?? [])] + albums.map(albumItem) + loose.map(songItem))
        case .album(let album):
            list([surpriseItem(album.songs)] + album.songs.map(songItem))
        case .songs:
            let songs = model.songbook.songs
            list(songs.map(songItem), jumps: jumps(songs.map(\.title)) { "song-" + songs[$0].id })
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
        case .phones: phonesPlace
        }
    }

    /// Where each letter starts in a list, as the key of its first row.
    private func jumps(_ names: [String], key: (Int) -> String) -> [Jump] {
        Songbook.letters(of: names).map { Jump(letter: $0.letter, key: key($0.index)) }
    }

    // MARK: - Songs from phones

    /// The switch, and while it's on, where phones go and the code.
    private var phonesPlace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                item(KaraokeText.letPhonesAdd + ": " + SettingsText.onOff(model.phonesAllowed), key: "phones-switch",
                     symbol: model.phonesAllowed ? "iphone.radiowaves.left.and.right" : "iphone") {
                    sound(.choose)
                    model.setPhonesAllowed(!model.phonesAllowed)
                }
                if model.phonesAllowed {
                    switch phones.status {
                    case .starting:
                        ProgressView()
                    case .failed(let message):
                        Text(message).foregroundStyle(style.inkSoft)
                    case .ready(let addresses):
                        Text(KaraokeText.openOnPhone).font(.headline).foregroundStyle(style.inkSoft)
                        ForEach(addresses, id: \.self) { address in
                            Text(address).font(.system(size: 64, weight: .bold, design: .monospaced)).foregroundStyle(style.ink)
                        }
                        if let page = phones.page {
                            Text(KaraokeText.thenCode).font(.headline).foregroundStyle(style.inkSoft)
                            Text(page.isLocked ? "Locked" : page.code)
                                .font(.system(size: 96, weight: .heavy, design: .monospaced)).foregroundStyle(style.accent)
                            if page.isLocked {
                                Text("Locked after \(LocalPage.mostWrongCodesInAll) wrong codes. Turn it off and on again for a new code.")
                                    .foregroundStyle(style.inkSoft)
                            }
                        }
                    }
                }
                Text(KaraokeText.phonesNote).font(.caption).foregroundStyle(style.inkSoft)
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
    }

    // MARK: - Themes

    /// Karaoke's name over a box for each theme, each its backdrop playing in
    /// miniature with its own lettering. Highlighting one samples it across
    /// the screen, with its tune.
    private var themes: some View {
        VStack(spacing: 36) {
            KaraokeTitle(text: KaraokeText.karaoke, size: 120, theme: theme, framed: true)
            Text(style.cased(KaraokeText.pickATheme))
                .font(style.font(40))
                .foregroundStyle(style.inkSoft)
            HStack(spacing: 40) {
                ForEach(KaraokeTheme.allCases) { box in
                    let boxStyle = KaraokeStyle(box)
                    Button {
                        KaraokeSynth.shared.effect(.theme, in: box)
                        model.choose(box)
                    } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            ZStack {
                                KaraokeBackdrop(theme: box)
                                KaraokeTitle(text: KaraokeText.karaoke, size: 44, theme: box)
                            }
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            Text(boxStyle.cased(box.name)).font(boxStyle.font(36)).foregroundStyle(boxStyle.accent).lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(box.tagline).font(.caption).foregroundStyle(boxStyle.inkSoft).lineLimit(2, reservesSpace: true)
                        }
                        .padding(20)
                        .background(LinearGradient(colors: boxStyle.background, startPoint: .top, endPoint: .bottom),
                                    in: RoundedRectangle(cornerRadius: 28))
                    }
                    .buttonStyle(KaraokeBoxStyle(accent: boxStyle.accent))
                    .focused($focus, equals: box.rawValue)
                    .accessibilityLabel(box.name)
                }
            }
            .focusSection()
            hint
        }
        .padding(.horizontal, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focus, model.theme.rawValue)
        .onChange(of: focus) { _, key in
            model.preview(key.flatMap(KaraokeTheme.init(rawValue:)))
        }
    }

    // MARK: - Home

    private var home: some View {
        let items = model.homeItems
        let songControls = items.filter { $0.group == .song }
        let finding = items.filter { $0.group == .songs }
        let more = items.filter { $0.group == .more }
        return VStack(alignment: .leading, spacing: 30) {
            if let song = model.stage.state.song { nowSinging(song) }
            if !songControls.isEmpty {
                HStack(spacing: 28) {
                    ForEach(songControls, id: \.self) { homeItem in
                        homeButton(homeItem, large: homeItem == .backToSong)
                    }
                }
                .focusSection()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3), spacing: 28) {
                ForEach(Array(finding.enumerated()), id: \.element) { index, homeItem in
                    tile(homeItem).modifier(RowEntrance(index: index))
                }
            }
            .focusSection()
            upNext
            HStack(spacing: 28) {
                ForEach(more, id: \.self) { homeItem in
                    homeButton(homeItem, large: false)
                }
            }
            .focusSection()
        }
    }

    private static func symbol(_ item: KaraokeModel.HomeItem) -> String {
        switch item {
        case .backToSong: "play.fill"
        case .restartSong: "backward.end.fill"
        case .skipSong: "forward.end.fill"
        case .artists: "music.mic"
        case .albums: "square.stack.fill"
        case .songs: "music.note.list"
        case .search: "magnifyingglass"
        case .surpriseMe: "dice.fill"
        case .queue: "list.number"
        case .phones: "iphone"
        case .themes: "paintpalette.fill"
        case .leave: "door.left.hand.open"
        }
    }

    private func choose(_ homeItem: KaraokeModel.HomeItem) {
        if homeItem == .leave { return confirmingLeave = true }
        sound(homeItem == .surpriseMe ? .queue : .choose)
        model.choose(homeItem)
    }

    /// A tile for finding songs: a big icon over its name.
    private func tile(_ homeItem: KaraokeModel.HomeItem) -> some View {
        let count = homeItem == .queue ? model.stage.queue.count : 0
        return Button { choose(homeItem) } label: {
            VStack(spacing: 14) {
                Image(systemName: Self.symbol(homeItem)).font(.system(size: 54, weight: .bold))
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            Text("\(count)").font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 2)
                                .background(style.accent2, in: Capsule()).foregroundStyle(style.card.opacity(1))
                                .offset(x: 28, y: -14)
                        }
                    }
                Text(style.cased(homeItem.title)).font(style.font(32)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(KaraokeItemStyle(style: style, prominent: homeItem == .surpriseMe))
        .focused($focus, equals: "\(homeItem)")
        .accessibilityLabel(count > 0 ? "\(homeItem.title) (\(count))" : homeItem.title)
    }

    /// The song's controls (large) and the items at the foot (small).
    private func homeButton(_ homeItem: KaraokeModel.HomeItem, large: Bool) -> some View {
        Button { choose(homeItem) } label: {
            Label(style.cased(homeItem.title), systemImage: Self.symbol(homeItem))
                .font(style.font(large ? 34 : 26))
                .lineLimit(1)
                .padding(.horizontal, large ? 20 : 4)
        }
        .buttonStyle(KaraokeItemStyle(style: style, compact: !large, prominent: large))
        .focused($focus, equals: "\(homeItem)")
        .accessibilityLabel(homeItem.title)
    }

    private func nowSinging(_ song: Songbook.Song) -> some View {
        HStack(spacing: 20) {
            KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 64)
            Text(KaraokeText.nowSinging(song))
                .font(style.font(30))
                .foregroundStyle(style.inkSoft)
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(style.card, in: RoundedRectangle(cornerRadius: style.corner))
    }

    /// The next few songs, under the tiles.
    @ViewBuilder private var upNext: some View {
        let next = model.stage.queue.prefix(3)
        if !next.isEmpty {
            HStack(spacing: 16) {
                Text(style.cased(KaraokeText.upNext)).font(.caption.bold()).foregroundStyle(style.accent2)
                ForEach(next) { song in
                    KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 40)
                    Text(song.title).font(.caption).foregroundStyle(style.inkSoft).lineLimit(1)
                }
            }
        }
    }

    // MARK: - Songs

    private func albumItem(_ album: Songbook.Album) -> AnyView {
        item(album.title ?? KaraokeText.otherSongs, detail: "\(album.artist) \u{00B7} \(KaraokeText.songCount(album.songs.count))",
             key: "album-" + album.id, cover: KaraokeCover(album)) {
            sound(.choose)
            model.open(.album(album))
        }
    }

    /// A song: chosen, it joins the queue.
    private func songItem(_ song: Songbook.Song) -> AnyView {
        var badges: [(String, Bool)] = []
        if song.isVideo { badges.append((KaraokeText.video, false)) }
        if !song.hasLyrics { badges.append((KaraokeText.noLyrics, true)) }
        return item(song.title, detail: [song.credit, song.album].compactMap { $0 }.joined(separator: " \u{00B7} "),
                    badges: badges, key: "song-" + song.id, cover: KaraokeCover(song)) {
            sound(.queue)
            model.queue(song)
        }
    }

    private func surpriseItem(_ songs: [Songbook.Song]) -> AnyView {
        item(KaraokeModel.HomeItem.surpriseMe.title, key: "surprise", symbol: "dice.fill", prominent: true) {
            sound(.queue)
            model.surpriseMe(from: songs)
        }
    }

    private func item(_ title: String, detail: String? = nil, badges: [(String, Bool)] = [], key: String,
                      cover: KaraokeCover? = nil, round: Bool = false, symbol: String? = nil, prominent: Bool = false,
                      action: @escaping () -> Void) -> AnyView {
        AnyView(Button(action: action) {
            HStack(spacing: 24) {
                if let cover {
                    KaraokeCoverView(cover: cover, style: style, size: 72, round: round)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 36, weight: .bold)).frame(width: 72)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(style.cased(title)).font(style.font(32)).lineLimit(1)
                    if let detail, !detail.isEmpty { Text(detail).font(style.font(24)).opacity(0.75).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(badges, id: \.0) { badge in
                    KaraokeBadge(text: badge.0, style: style, quiet: badge.1)
                }
            }
        }
        .buttonStyle(KaraokeItemStyle(style: style, prominent: prominent))
        .focused($focus, equals: key)
        .accessibilityLabel(title)
        .id(key))
    }

    private func list(_ items: [AnyView], jumps: [Jump] = []) -> some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 40) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if items.isEmpty {
                            Text(KaraokeText.noSongs).foregroundStyle(style.inkSoft)
                        }
                        ForEach(items.indices, id: \.self) { index in
                            items[index].modifier(RowEntrance(index: index))
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.leading, style.look == .block ? 50 : 0)
                }
                .scrollClipDisabled()
                if !jumps.isEmpty {
                    LetterRail(jumps: jumps, style: style, focus: $focus) { jump in
                        proxy.scrollTo(jump.key, anchor: .top)
                        Task {
                            try? await Task.sleep(for: .milliseconds(120))
                            focus = jump.key
                        }
                    }
                }
            }
        }
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
                        HStack(spacing: 24) {
                            Text("\(index + 1)").font(style.font(40)).foregroundStyle(style.accent).frame(width: 60)
                            KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 72)
                            VStack(alignment: .leading) {
                                Text(style.cased(song.title)).font(style.font(32)).lineLimit(1)
                                Text(song.credit).font(style.font(24)).opacity(0.75).lineLimit(1)
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
                        .padding(.vertical, 14)
                        .background(style.item, in: RoundedRectangle(cornerRadius: style.corner))
                        .focusSection()
                        .modifier(RowEntrance(index: index))
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
    }

    private func queueButton(_ symbol: String, _ label: String, key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 34, weight: .bold)).frame(width: 44, height: 44) }
            .accessibilityLabel(label)
            .buttonStyle(KaraokeItemStyle(style: style, compact: true))
            .focused($focus, equals: key)
    }
}

/// A letter a long list jumps to, and the key of its first row.
struct Jump: Hashable {
    let letter: String
    let key: String
}

/// Letters down the right of a long list: choosing one jumps to it.
private struct LetterRail: View {
    let jumps: [Jump]
    let style: KaraokeStyle
    var focus: FocusState<String?>.Binding
    let jump: (Jump) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(jumps, id: \.self) { item in
                    Button { jump(item) } label: {
                        Text(item.letter).font(style.font(26)).frame(width: 44, height: 30)
                    }
                    .buttonStyle(KaraokeItemStyle(style: style, compact: true, tight: true))
                    .focused(focus, equals: "letter-" + item.letter)
                    .accessibilityLabel("Jump to \(item.letter)")
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .frame(width: 100)
        .focusSection()
    }
}

/// A karaoke row or button, highlighted in its theme's way (`KaraokeStyle.Look`):
/// neon flickering on, an 80s bar with a ►, a bubblegum bounce, or a Vegas glint.
struct KaraokeItemStyle: ButtonStyle {
    let style: KaraokeStyle
    var compact = false
    /// Stands out before it's highlighted (Surprise Me, Back to the Song).
    var prominent = false
    /// Hardly any padding (the letter rail).
    var tight = false

    func makeBody(configuration: Configuration) -> some View {
        Item(configuration: configuration, style: style, compact: compact, prominent: prominent, tight: tight)
    }

    private struct Item: View {
        let configuration: ButtonStyleConfiguration
        let style: KaraokeStyle
        let compact: Bool
        let prominent: Bool
        let tight: Bool
        @Environment(\.isFocused) private var isFocused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: tight ? 8 : style.corner)
            configuration.label
                .foregroundStyle(isFocused ? style.onAccent : prominent ? style.accent : style.ink)
                .padding(.horizontal, tight ? 6 : compact ? 24 : 32)
                .padding(.vertical, tight ? 2 : compact ? 16 : 18)
                .background { background(shape) }
                .overlay {
                    if prominent, !isFocused {
                        shape.stroke(style.accent, lineWidth: 3)
                    }
                }
                .overlay(alignment: .leading) {
                    if style.look == .block, isFocused, !tight {
                        Text("\u{25BA}").font(style.font(30)).foregroundStyle(style.accent).offset(x: -46)
                    }
                }
                .scaleEffect(scale)
                .keyframeAnimator(initialValue: 1.0, trigger: isFocused && style.look == .glow && !reduceMotion) { view, opacity in
                    view.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.55, duration: 0.04)
                        LinearKeyframe(1, duration: 0.05)
                        LinearKeyframe(0.75, duration: 0.05)
                        LinearKeyframe(1, duration: 0.06)
                    }
                }
                .animation(style.look == .squish ? .bouncy(duration: 0.35, extraBounce: 0.3) : .easeOut(duration: 0.15), value: isFocused)
        }

        private var scale: CGFloat {
            if configuration.isPressed { return 0.97 }
            guard isFocused, !tight else { return 1 }
            switch style.look {
            case .glow: return 1.03
            case .block: return 1
            case .squish: return 1.06
            case .gilt: return 1.02
            }
        }

        private var shadowColour: Color {
            guard isFocused else { return .clear }
            return style.look == .block ? .black : style.accent.opacity(style.look == .gilt ? 0.4 : 0.7)
        }

        @ViewBuilder private func background(_ shape: RoundedRectangle) -> some View {
            if isFocused, style.look == .gilt {
                ZStack {
                    shape.fill(style.card.opacity(1))
                    if !reduceMotion { Glint(colour: style.accent).clipShape(shape) }
                    shape.stroke(style.accent, lineWidth: 4)
                }
                .shadow(color: shadowColour, radius: 20)
            } else {
                // The shadow on the shape alone: on the text, 80s' hard one would double it.
                shape.fill(isFocused ? style.accent : style.item)
                    .shadow(color: shadowColour, radius: style.look == .block ? 0 : 20,
                            x: style.look == .block && isFocused ? 6 : 0, y: style.look == .block && isFocused ? 6 : 0)
            }
        }
    }
}

/// Vegas's highlight: a glint running across, now and then.
private struct Glint: View {
    let colour: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                let sweep = (timeline.date.timeIntervalSinceReferenceDate / 1.8).truncatingRemainder(dividingBy: 1)
                LinearGradient(colors: [.clear, colour.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.3)
                    .offset(x: (sweep * 1.6 - 0.3) * geometry.size.width)
            }
        }
        .allowsHitTesting(false)
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
                .scaleEffect(isFocused ? 1.08 : 1)
                .shadow(color: accent.opacity(isFocused ? 0.8 : 0), radius: 30)
                .animation(.bouncy(duration: 0.3), value: isFocused)
        }
    }
}
