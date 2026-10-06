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
            if case .singing(let song) = state, song.isVideo { video }
            if case .paused(let song) = state, song.isVideo { video }
            if let lyrics = shownLyrics {
                TimelineView(.animation) { _ in
                    LyricsLinesView(timeline: lyrics, moment: lyrics.moment(at: deck.position), style: style)
                }
                .padding(.horizontal, 120)
            }
            card(for: state)
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

    private var video: some View {
        VideoSurface(player: deck.player).ignoresSafeArea()
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
                Text(style.cased(KaraokeText.getReady)).font(style.font(96)).foregroundStyle(style.accent)
                    .shadow(color: style.accent.opacity(0.7), radius: 20)
                songTitle(song)
                ProgressView()
            }
        case .ready(let song):
            KaraokeCard(style: style) {
                songTitle(song)
                Text(style.cased(KaraokeText.pressPlay)).font(style.font(40)).foregroundStyle(style.card.opacity(1))
                    .padding(.horizontal, 40).padding(.vertical, 16)
                    .background(style.accent, in: Capsule())
                let upNext = model.stage.queue.prefix(3)
                if !upNext.isEmpty {
                    VStack(spacing: 6) {
                        Text(KaraokeText.upNext.uppercased()).font(.caption.bold()).foregroundStyle(style.accent2)
                        ForEach(upNext) { Text("\($0.title) \u{2014} \($0.credit)").foregroundStyle(style.inkSoft) }
                    }
                }
            }
        case .singing(let song), .paused(let song):
            if !song.isVideo && model.stage.lyrics == nil {
                KaraokeCard(style: style) { songTitle(song) }
            }
        }
    }

    private func songTitle(_ song: Songbook.Song) -> some View {
        VStack(spacing: 10) {
            Text(style.cased(song.title)).font(style.font(64)).foregroundStyle(style.ink).multilineTextAlignment(.center)
            Text(song.credit).font(style.font(34)).foregroundStyle(style.inkSoft)
            if let album = song.album { Text(album).italic().foregroundStyle(style.inkSoft) }
            if !song.hasLyrics {
                Text(KaraokeText.noLyrics).font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 4)
                    .overlay(Capsule().stroke(style.inkSoft))
                    .foregroundStyle(style.inkSoft)
            }
        }
    }

    /// "Pick a song!", with artists going by.
    private var attract: some View {
        let artists = model.songbook.artists.prefix(24).map(\.name).joined(separator: "     \u{2605}     ")
        return KaraokeCard(style: style) {
            TimelineView(.animation) { timeline in
                let wobble = sin(timeline.date.timeIntervalSinceReferenceDate * 2.4)
                Text(style.cased(KaraokeText.pickASong)).font(style.font(110)).foregroundStyle(style.accent)
                    .shadow(color: style.accent.opacity(0.7), radius: 24)
                    .rotationEffect(.degrees(wobble * 2))
                    .scaleEffect(1 + 0.03 * wobble)
            }
            Marquee(text: style.cased(artists), style: style)
            Text(KaraokeText.anyButton).foregroundStyle(style.inkSoft)
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
/// the line being sung lighting up word by word, the next line below, and
/// the bouncing ball over the words, placed from where each word is drawn.
private struct LyricsLinesView: View {
    let timeline: LyricsTimeline
    let moment: LyricsTimeline.Moment
    let style: KaraokeStyle

    var body: some View {
        VStack(spacing: 44) {
            Text(moment.countdown.map { String(repeating: "\u{25CF}", count: $0) } ?? " ")
                .font(style.font(56))
                .tracking(24)
                .foregroundStyle(style.accent)
            line(moment.line, size: 84, sung: moment.sung)
            line(moment.next, size: 56, sung: 0)
                .opacity(0.6)
        }
        .overlayPreferenceValue(WordBounds.self) { words in
            GeometryReader { geometry in
                if let ball = moment.ball, let from = words[Spot(ball.from)].map({ geometry[$0] }) {
                    let to = ball.to.flatMap { words[Spot($0)] }.map { geometry[$0] } ?? from
                    let p = ball.progress
                    let x = from.midX + (to.midX - from.midX) * p
                    let y = from.minY + (to.minY - from.minY) * p - sin(.pi * p) * 0.7 * max(from.height, to.height)
                    Circle()
                        .fill(style.accent2)
                        .shadow(color: style.accent2, radius: 10)
                        .frame(width: 28, height: 28)
                        .position(x: x, y: y - 20)
                }
            }
        }
    }

    @ViewBuilder private func line(_ index: Int?, size: CGFloat, sung: Double) -> some View {
        if let index {
            FlowLine {
                ForEach(timeline.segments(ofLine: index)) { segment in
                    WordView(text: style.cased(segment.text), fill: segment.fill(sung: sung), font: style.font(size), style: style)
                        .anchorPreference(key: WordBounds.self, value: .bounds) { [Spot(line: index, start: segment.range.lowerBound): $0] }
                }
            }
        } else {
            Text(" ").font(style.font(size))
        }
    }
}

/// A word, lit from the left as far as it's sung.
private struct WordView: View {
    let text: String
    let fill: Double
    let font: Font
    let style: KaraokeStyle

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(style.ink)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(style.accent)
                    .mask(alignment: .leading) {
                        GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * fill) }
                    }
            }
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
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
