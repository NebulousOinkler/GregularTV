import GregularCore
import GregularScreens
import SwiftUI

/// Karaoke's stage: the song on it (a video, or a sound file with its lyrics
/// and the bouncing ball over the theme's backdrop), its title card before
/// Play, "Get ready!" while it loads, or, with nothing queued, the attract
/// screen, which any button leaves for the menu.
struct KaraokeStageView: View {
    let model: KaraokeModel
    let deck: AVSongDeck
    @FocusState private var focused: Bool

    private var style: KaraokeStyle { KaraokeStyle(model.shownTheme) }

    var body: some View {
        let state = model.stage.state
        ZStack {
            if case .singing(let song) = state, song.isVideo { video(song) }
            if case .paused(let song) = state, song.isVideo { video(song) }
            if let lyrics = shownLyrics {
                TimelineView(.animation) { _ in
                    LyricsLinesView(timeline: lyrics, moment: lyrics.moment(at: deck.position), style: style)
                }
                .padding(.horizontal, 120)
            }
            card(for: state)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .id(cardKey(state))
            if case .paused = state {
                VStack {
                    Text(style.cased("Paused")).font(style.font(44)).foregroundStyle(style.ink)
                        .padding(.horizontal, 40).padding(.vertical, 14)
                        .background(style.card, in: Capsule())
                    Spacer()
                }
                .padding(.top, 80)
            }
        }
        .animation(style.animation, value: cardKey(state))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .focusable(model.place == nil)
        .focused($focused)
        .onChange(of: model.place == nil, initial: true) { _, onStage in focused = onStage }
        // The stage's buttons, by `RemoteControls.karaokeStage`; on the attract screen, any of them.
        .onPlayPauseCommand { press(.playPause) }
        .onExitCommand { press(.menu) }
        .onTapGesture { press(.click) }
        .onMoveCommand { _ in if model.isAttract { model.leaveAttract() } }
    }

    /// Which card shows, so a new one animates in.
    private func cardKey(_ state: KaraokeStage.State) -> String {
        switch state {
        case .idle: "attract"
        case .loading(let song): "loading-" + song.id
        case .ready(let song): "ready-" + song.id
        case .singing(let song), .paused(let song): "on-" + song.id
        }
    }

    /// A video fills the screen; for its first few seconds, a strip says what it is.
    private func video(_ song: Songbook.Song) -> some View {
        ZStack(alignment: .bottomLeading) {
            VideoSurface(player: deck.player).ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let showing = deck.position < 6
                HStack(spacing: 24) {
                    KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(style.cased(song.title)).font(style.font(44)).foregroundStyle(style.ink)
                        Text(song.credit).font(style.font(28)).foregroundStyle(style.inkSoft)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(style.card, in: RoundedRectangle(cornerRadius: style.corner))
                .padding(80)
                .opacity(showing ? 1 : 0)
                .offset(x: showing ? 0 : -60)
                .animation(.easeInOut(duration: 0.6), value: showing)
            }
        }
    }

    private func press(_ button: RemoteButton) {
        if model.isAttract {
            KaraokeSynth.shared.effect(.choose, in: model.shownTheme)
            return model.leaveAttract()
        }
        guard model.place == nil, let action = RemoteControls.karaokeStage[button] else { return }
        model.perform(action)
    }

    /// The lyrics show for a sound file with timed lyrics, once it's begun
    /// (its title card has the screen to itself).
    private var shownLyrics: LyricsTimeline? {
        switch model.stage.state {
        case .singing(let song), .paused(let song): song.isVideo ? nil : model.stage.lyrics
        case .idle, .loading, .ready: nil
        }
    }

    @ViewBuilder private func card(for state: KaraokeStage.State) -> some View {
        switch state {
        case .idle:
            attract
        case .loading(let song):
            KaraokeCard(style: style) {
                KaraokeTitle(text: KaraokeText.getReady, size: 96, theme: model.shownTheme)
                songTitle(song)
                KaraokeLoader(theme: model.shownTheme)
            }
        case .ready(let song):
            KaraokeCard(style: style) {
                songTitle(song)
                PressPlay(style: style)
                let upNext = model.stage.queue.prefix(3)
                if !upNext.isEmpty {
                    VStack(spacing: 10) {
                        Text(style.cased(KaraokeText.upNext)).font(.caption.bold()).foregroundStyle(style.accent2)
                        ForEach(upNext) { next in
                            HStack(spacing: 14) {
                                KaraokeCoverView(cover: KaraokeCover(next), style: style, size: 40)
                                Text(KaraokeText.line(next)).foregroundStyle(style.inkSoft).lineLimit(1)
                            }
                        }
                    }
                }
            }
        case .singing(let song), .paused(let song):
            if !song.isVideo && model.stage.lyrics == nil {
                KaraokeCard(style: style) { songTitle(song) }
            }
        }
    }

    /// The song's picture beside its title, artist and album.
    private func songTitle(_ song: Songbook.Song) -> some View {
        HStack(spacing: 40) {
            KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 220)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
            VStack(alignment: .leading, spacing: 10) {
                Text(style.cased(song.title)).font(style.font(64)).foregroundStyle(style.ink).lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(song.credit).font(style.font(34)).foregroundStyle(style.inkSoft)
                if let album = song.album { Text(album).italic().foregroundStyle(style.inkSoft) }
                if !song.hasLyrics { KaraokeBadge(text: KaraokeText.noLyrics, style: style, quiet: true) }
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    /// Karaoke's name, "Pick a song!", and artists going by.
    private var attract: some View {
        let artists = model.songbook.artists.prefix(24).map(\.name).joined(separator: "     \u{2605}     ")
        return VStack(spacing: 36) {
            KaraokeTitle(text: KaraokeText.karaoke, size: 150, theme: model.shownTheme, framed: true)
            KaraokeCard(style: style) {
                TimelineView(.animation) { timeline in
                    let wobble = sin(timeline.date.timeIntervalSinceReferenceDate * 2.4)
                    Text(style.cased(KaraokeText.pickASong)).font(style.font(96)).foregroundStyle(style.accent)
                        .shadow(color: style.accent.opacity(0.7), radius: 24)
                        .rotationEffect(.degrees(wobble * 2))
                        .scaleEffect(1 + 0.03 * wobble)
                }
                Marquee(text: style.cased(artists), style: style)
                Text(KaraokeText.anyButton).foregroundStyle(style.inkSoft)
            }
        }
    }
}

/// "Press Play to sing", pulsing gently.
private struct PressPlay: View {
    let style: KaraokeStyle
    @State private var big = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "playpause.fill").accessibilityHidden(true)
            Text(style.cased(KaraokeText.pressPlay))
        }
            .font(style.font(40)).foregroundStyle(style.onAccent)
            .padding(.horizontal, 44).padding(.vertical, 18)
            .accentCapsule(style)
            .shadow(color: style.accent.opacity(0.6), radius: big ? 28 : 12)
            .scaleEffect(big ? 1.05 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever()) { big = true }
            }
    }
}

/// A card in the middle of the stage.
private struct KaraokeCard<Content: View>: View {
    let style: KaraokeStyle
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 28) { content }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
            .frame(maxWidth: 1300)
            .background(style.card, in: RoundedRectangle(cornerRadius: 40))
            .shadow(color: .black.opacity(0.4), radius: 40)
    }
}

/// A line of text scrolling by, round and round.
private struct Marquee: View {
    let text: String
    let style: KaraokeStyle

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let offset = (timeline.date.timeIntervalSinceReferenceDate * 80).truncatingRemainder(dividingBy: width * 2)
                Text(text)
                    .font(style.font(34))
                    .foregroundStyle(style.accent2)
                    .fixedSize()
                    .offset(x: width - offset)
            }
        }
        .frame(height: 50)
        .clipped()
    }
}

// MARK: - Lyrics

/// The lyrics at one moment (`LyricsTimeline.Moment`): the countdown dots,
/// the line being sung lighting up word by word, the next line below (it
/// rises into place as its turn comes), and the bouncing ball over the
/// words, placed from where each word is drawn.
private struct LyricsLinesView: View {
    let timeline: LyricsTimeline
    let moment: LyricsTimeline.Moment
    let style: KaraokeStyle

    var body: some View {
        VStack(spacing: 44) {
            CountdownDots(count: moment.countdown, style: style)
            VStack(spacing: 24) {
                ForEach([moment.line, moment.next].compactMap { $0 }, id: \.self) { index in
                    let current = index == moment.line
                    line(index, sung: current ? moment.sung : 0)
                        .scaleEffect(current ? 1 : 0.68)
                        .opacity(current ? 1 : 0.6)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                removal: .move(edge: .top).combined(with: .opacity)))
                }
            }
            .animation(.spring(duration: 0.45), value: moment.line)
        }
        .overlayPreferenceValue(WordBounds.self) { words in
            GeometryReader { geometry in
                if let ball = moment.ball, let from = words[Spot(ball.from)].map({ geometry[$0] }) {
                    let to = ball.to.flatMap { words[Spot($0)] }.map { geometry[$0] } ?? from
                    Ball(from: from, to: to, progress: ball.to == nil ? 0 : ball.progress, hopping: ball.to != nil, style: style)
                }
            }
        }
    }

    private func line(_ index: Int, sung: Double) -> some View {
        FlowLine {
            ForEach(timeline.segments(ofLine: index)) { segment in
                WordView(text: style.cased(segment.text), fill: segment.fill(sung: sung), font: style.font(84), style: style)
                    .anchorPreference(key: WordBounds.self, value: .bounds) { [Spot(line: index, start: segment.range.lowerBound): $0] }
            }
        }
    }
}

/// The bouncing ball, hopping from one word to the next: squashed as it
/// lands and leaves, a shadow on the words growing as it comes down, and a
/// faint trail.
private struct Ball: View {
    let from: CGRect
    let to: CGRect
    let progress: Double
    /// Hopping on to another word (not resting on the last).
    let hopping: Bool
    let style: KaraokeStyle
    static let size: CGFloat = 44

    var body: some View {
        let height = max(from.height, to.height)
        ZStack {
            // The shadow on the words below.
            let closeness = 1 - sin(.pi * progress)
            Ellipse()
                .fill(Color.black.opacity(0.3 * closeness))
                .frame(width: Self.size * (0.5 + 0.5 * closeness), height: 10)
                .position(x: x(progress), y: from.minY + (to.minY - from.minY) * progress - 4)
            ForEach(1..<4) { step in
                let earlier = progress - Double(step) * 0.05
                if earlier > 0 {
                    ball.frame(width: Self.size * (1 - 0.18 * Double(step)), height: Self.size * (1 - 0.18 * Double(step)))
                        .opacity(0.3 / Double(step))
                        .position(x: x(earlier), y: y(earlier, height))
                }
            }
            let squash = hopping ? max(0, 1 - min(progress, 1 - progress) / 0.1) : 0
            ball.frame(width: Self.size, height: Self.size)
                .scaleEffect(x: 1 + 0.22 * squash, y: 1 - 0.22 * squash, anchor: .bottom)
                .position(x: x(progress), y: y(progress, height))
        }
        .allowsHitTesting(false)
    }

    private func x(_ p: Double) -> CGFloat {
        from.midX + (to.midX - from.midX) * p
    }

    private func y(_ p: Double, _ height: CGFloat) -> CGFloat {
        from.minY + (to.minY - from.minY) * p - sin(.pi * p) * 0.7 * height - Self.size / 2 - 6
    }

    /// The ball in the theme's style: neon's glowing, 80s' square, a bubble, or gold.
    @ViewBuilder private var ball: some View {
        switch style.look {
        case .glow:
            Circle().fill(.white).shadow(color: style.accent2, radius: 6).shadow(color: style.accent2, radius: 14)
        case .block:
            Rectangle().fill(style.accent2).shadow(color: .black, radius: 0, x: 4, y: 4)
        case .squish:
            Circle().fill(.white.opacity(0.7)).overlay(Circle().stroke(style.accent, lineWidth: 5))
        case .gilt:
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.97, blue: 0.8), style.accent], center: .topLeading,
                                         startRadius: 2, endRadius: Self.size))
                .shadow(color: style.accent, radius: 12)
        }
    }
}

/// A word, lit from the left as far as it's sung, rising a touch while it's being sung.
private struct WordView: View {
    let text: String
    let fill: Double
    let font: Font
    let style: KaraokeStyle

    var body: some View {
        let singing = fill > 0 && fill < 1
        Text(text)
            .font(font)
            .foregroundStyle(style.ink)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(style.accent)
                    .mask(alignment: .leading) {
                        // Past the word's frame at either end once lit: italic letters lean out of it.
                        GeometryReader { geometry in
                            Rectangle()
                                .frame(width: fill <= 0 ? 0 : fill >= 1 ? geometry.size.width + 48 : geometry.size.width * fill + 24)
                                .offset(x: -24)
                        }
                    }
                    .shadow(color: style.look == .glow ? style.accent.opacity(0.8) : .clear, radius: 10)
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .offset(y: singing ? -8 : 0)
            .animation(.spring(duration: 0.2), value: singing)
    }
}

/// Where a word is: its line, and its first character.
private struct Spot: Hashable {
    let line: Int
    let start: Int

    init(line: Int, start: Int) {
        self.line = line
        self.start = start
    }

    init(_ spot: LyricsTimeline.Spot) {
        self.init(line: spot.line, start: spot.range.lowerBound)
    }
}

/// Each word's bounds, for the ball.
private struct WordBounds: PreferenceKey {
    static let defaultValue: [Spot: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Spot: Anchor<CGRect>], nextValue: () -> [Spot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Words laid out left to right, wrapping onto new lines, each line centred.
private struct FlowLine: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = self.rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.height
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
