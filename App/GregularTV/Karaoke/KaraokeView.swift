import GregularScreens
import SwiftUI

/// Karaoke on Apple TV: `KaraokeModel` drawn in its theme. Layers, from the
/// back: the theme's backdrop, the stage (`KaraokeStageView`), and
/// karaoke's menus over it (`KaraokeMenuView`). The Siri Remote works
/// `RemoteControls.karaokeStage` and `.karaokeMenus`.
struct KaraokeView: View {
    let session: SpecialModeSession
    /// Made once, as the view first appears: SwiftUI may make this view
    /// many times over, but there's one model and one player per visit.
    @State private var karaoke: (model: KaraokeModel, deck: AVSongDeck)?
    /// Serves the song picker to phones, while they may add songs.
    @State private var phones = LocalPageServer()
    /// A queued song's picture on its way to the queue.
    @State private var flying: (id: Int, song: Songbook.Song)?
    /// The song just sung to its end, cheered for a moment.
    @State private var encore: (id: Int, song: Songbook.Song)?
    @State private var bursts: [Confetti.Burst] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let karaoke {
                content(karaoke.model, karaoke.deck)
            }
        }
        .onAppear {
            guard karaoke == nil else { return }
            let deck = AVSongDeck(download: session.download)
            karaoke = (KaraokeModel(session: session, deck: deck, offersPhones: true), deck)
        }
        .onDisappear {
            phones.stop()
            karaoke?.model.stage.stop()
            KaraokeSynth.shared.play(nil)
        }
    }

    private func content(_ model: KaraokeModel, _ deck: AVSongDeck) -> some View {
        let style = KaraokeStyle(model.shownTheme)
        return ZStack {
            KaraokeBackdrop(theme: model.shownTheme) {
                // Throbbing with the singing, while there are lyrics to follow.
                guard case .singing = model.stage.state, let lyrics = model.stage.lyrics else { return 0 }
                return lyrics.pulse(at: deck.position)
            }
            KaraokeStageView(model: model, deck: deck)
                .blur(radius: model.place == nil ? 0 : 24)
                .brightness(model.place == nil ? 0 : -0.45)
                // The attract screen behind a menu would only be a blur; behind the cheer, a muddle.
                .opacity(model.place != nil && model.stage.state == .idle || encore != nil ? 0 : 1)
            if model.phonesAllowed, model.place == nil, case .ready(let addresses) = phones.status, let page = phones.page,
               let address = addresses.first {
                PhonesBadge(text: KaraokeText.phonesBadge(address: address, code: page.code), style: style)
            }
            if let place = model.place {
                KaraokeMenuView(place: place, model: model, phones: phones)
                    // A fresh menu for each place, so focus starts on its first item.
                    .id(model.places)
                    .transition(style.transition)
            }
            if model.place != nil, model.place != .themes {
                QueueChip(count: model.stage.queue.count + (model.stage.state.song == nil ? 0 : 1), bounces: model.songsQueued,
                          style: style)
            }
            if let flying {
                FlyingCover(song: flying.song, style: style).id(flying.id)
            }
            if let encore {
                EncoreCard(song: encore.song, theme: model.shownTheme).id(encore.id)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Confetti(bursts: bursts, style: style)
            if let notice = model.notice ?? model.stage.notice {
                KaraokeNotice(text: notice, style: style)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.shownTheme)
        .animation(style.animation, value: model.places)
        .animation(.bouncy, value: encore?.id)
        .onChange(of: model.menuMusic, initial: true) { _, theme in KaraokeSynth.shared.play(theme) }
        .onChange(of: model.musicMood, initial: true) { _, mood in KaraokeSynth.shared.setMood(mood) }
        .onChange(of: model.phonesAllowed) { _, allowed in
            if allowed { phones.start { LocalPage.songPicker(karaoke: model, hosts: $0) } } else { phones.stop() }
        }
        .onChange(of: model.songsQueued) { _, count in
            guard let song = model.lastQueued else { return }
            flying = (count, song)
            burst(from: UnitPoint(x: 0.5, y: 0.55), pieces: 50)
        }
        .onChange(of: model.stage.state) { old, new in
            // Play on a title card: a drum roll into the song.
            if case .ready = old, case .singing = new { KaraokeSynth.shared.effect(.start, in: model.shownTheme) }
        }
        .onChange(of: model.stage.songsFinished) { _, count in
            guard let song = model.stage.lastFinished else { return }
            KaraokeSynth.shared.effect(.encore, in: model.shownTheme)
            encore = (count, song)
            burst(from: UnitPoint(x: 0.3, y: 0.4), pieces: 90)
            burst(from: UnitPoint(x: 0.7, y: 0.4), pieces: 90)
            Task {
                try? await Task.sleep(for: .seconds(3.2))
                if encore?.id == count { encore = nil }
            }
        }
    }

    /// Starts a burst of confetti, and clears away ones long over.
    private func burst(from point: UnitPoint, pieces: Int) {
        guard !reduceMotion else { return }
        let now = Date.now
        bursts.removeAll { now.timeIntervalSince($0.start) > Confetti.lasts }
        bursts.append(Confetti.Burst(id: (bursts.last?.id ?? 0) + 1, start: now, from: point, pieces: pieces))
    }
}

/// How many songs are on and queued, at the top right of the menus,
/// bouncing as each joins.
private struct QueueChip: View {
    let count: Int
    let bounces: Int
    let style: KaraokeStyle

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if count > 0 {
                    Label("\(count)", systemImage: "music.note.list")
                        .font(style.font(30))
                        .foregroundStyle(style.onAccent)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .accentCapsule(style)
                        .keyframeAnimator(initialValue: 1.0, trigger: bounces) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(1.35, duration: 0.15)
                                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
                            }
                        }
                        .accessibilityLabel(KaraokeModel.HomeItem.queue.title + ": \(count)")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 70)
        .allowsHitTesting(false)
    }
}

/// A queued song's picture, flying from the middle of the screen up to the queue.
private struct FlyingCover: View {
    let song: Songbook.Song
    let style: KaraokeStyle
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 180)
                .shadow(color: .black.opacity(0.4), radius: 20)
                .scaleEffect(landed ? 0.2 : 1)
                .opacity(landed ? 0 : 1)
                .position(x: landed ? geometry.size.width - 160 : geometry.size.width / 2,
                          y: landed ? 100 : geometry.size.height * 0.55)
        }
        .opacity(reduceMotion ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeIn(duration: 0.8)) { landed = true } }
    }
}

/// A song sung to its end: "Encore!", and what it was.
private struct EncoreCard: View {
    let song: Songbook.Song
    let theme: KaraokeTheme

    var body: some View {
        let style = KaraokeStyle(theme)
        VStack(spacing: 28) {
            KaraokeTitle(text: KaraokeText.encore, size: 150, theme: theme, framed: true)
            HStack(spacing: 20) {
                KaraokeCoverView(cover: KaraokeCover(song), style: style, size: 72)
                Text(KaraokeText.nowSinging(song)).font(style.font(36)).foregroundStyle(style.ink).lineLimit(1)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(style.card, in: RoundedRectangle(cornerRadius: style.corner))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Where guests' phones go to add songs, in a corner of the stage.
private struct PhonesBadge: View {
    let text: String
    let style: KaraokeStyle

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Label(text, systemImage: "iphone")
                    .font(style.font(26))
                    .foregroundStyle(style.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(style.card, in: Capsule())
                Spacer()
            }
        }
        .padding(60)
        .allowsHitTesting(false)
    }
}

/// Something karaoke says, such as a song queued, at the foot of the screen.
private struct KaraokeNotice: View {
    let text: String
    let style: KaraokeStyle

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(style.font(30))
                .foregroundStyle(style.ink)
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
                .background(style.card, in: Capsule())
                .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }
}
