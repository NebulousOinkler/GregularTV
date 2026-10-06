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

    var body: some View {
        ZStack {
            if let karaoke {
                content(karaoke.model, karaoke.deck)
            }
        }
        .onAppear {
            guard karaoke == nil else { return }
            let deck = AVSongDeck(download: session.download)
            karaoke = (KaraokeModel(session: session, deck: deck), deck)
        }
        .onDisappear {
            karaoke?.model.stage.stop()
            KaraokeSynth.shared.play(nil)
        }
    }

    private func content(_ model: KaraokeModel, _ deck: AVSongDeck) -> some View {
        ZStack {
            KaraokeBackdrop(theme: model.shownTheme)
            KaraokeStageView(model: model, deck: deck)
                .blur(radius: model.place == nil ? 0 : 24)
                .brightness(model.place == nil ? 0 : -0.45)
                // The attract screen behind a menu would only be a blur.
                .opacity(model.place != nil && model.stage.state == .idle ? 0 : 1)
            if let place = model.place {
                KaraokeMenuView(place: place, model: model)
                    // A fresh menu for each place, so focus starts on its first item.
                    .id(model.places)
            }
            if let notice = model.notice ?? model.stage.notice {
                KaraokeNotice(text: notice, style: KaraokeStyle(model.shownTheme))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.shownTheme)
        .onChange(of: model.menuMusic, initial: true) { _, theme in KaraokeSynth.shared.play(theme) }
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
