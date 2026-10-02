import AVFoundation
import GregularScreens
import SwiftUI

/// The last 15 seconds of a commercial break: the channel's own card, like a
/// TV station's "You're watching…" ident. The Gregular wordmark springs in
/// on the brand gradient, its colour bars hop to the music's beat, dots in
/// the bars' colours drift up behind, and what's up next fades in below.
/// The music (`station-card.m4a`, made by scripts/make-station-music.py)
/// starts from wherever the card is up to, so it always ends as the
/// programme starts. `WatchModel` decides when the card is up and what it
/// says; this only draws it and plays the music.
struct StationCard: View {
    let content: StationCardContent

    @State private var music = StationMusic()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? StationMusic.length : StationMusic.elapsed(at: context.date, endingAt: content.endsAt)
            ZStack {
                Brand.gradient
                DriftingDots(elapsed: elapsed)
                VStack(spacing: 26) {
                    Text(content.intro.uppercased()).font(.headline).tracking(8).foregroundStyle(.secondary)
                    Text("Gregular TV").font(.system(size: 130, weight: .heavy, design: .rounded))
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                        .scaleEffect(Self.spring(elapsed))
                    HoppingBars(elapsed: elapsed)
                    Text(content.channel).font(.title2).bold().padding(.top, 8)
                    VStack(spacing: 10) {
                        Text(content.heading).font(.title3).foregroundStyle(.secondary)
                        if let title = content.title {
                            Text(title).font(.largeTitle).bold().lineLimit(1).minimumScaleFactor(0.6)
                        }
                        Text(content.when).font(.title3)
                    }
                    .padding(.top, 70)
                    .opacity(min(1, max(0, (elapsed - 0.8) / 0.6)))
                }
                .opacity(min(1, max(0, elapsed / 0.35)))
                .padding(.horizontal, 120)
            }
        }
        .ignoresSafeArea()
        .onAppear { music.play(endingAt: content.endsAt) }
        .onDisappear { music.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { music.stop() }
        }
    }

    /// The wordmark's size as it arrives: a little small, overshooting, settling.
    private static func spring(_ t: Double) -> Double {
        guard t > 0 else { return 0.85 }
        return 1 - 0.15 * exp(-t * 5) * cos(t * 11)
    }
}

/// The colour bars as seven little blocks, a ripple running across them on
/// every beat of the music. They settle as it ends.
private struct HoppingBars: View {
    let elapsed: Double

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Brand.barColors.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6)
                    .fill(Brand.barColors[index])
                    .frame(width: 46, height: 16)
                    .offset(y: -hop(index))
            }
        }
    }

    /// How high bar `index` is: a quick hop, a little after the one to its left.
    private func hop(_ index: Int) -> Double {
        let beats = (elapsed - StationMusic.firstBeat) / StationMusic.beat
        guard beats >= 0 else { return 0 }
        let x = (beats - beats.rounded(.down)) - Double(index) * 0.07
        guard x > 0, x < 0.3 else { return 0 }
        let settle = min(1, max(0, (StationMusic.length - 1.5 - elapsed) / 1.0))
        return 14 * sin(.pi * x / 0.3) * settle
    }
}

/// Dots in the bars' colours, drifting up and swaying, faint, behind the card.
private struct DriftingDots: View {
    let elapsed: Double

    var body: some View {
        Canvas { context, size in
            for index in 0..<28 {
                let seed = Double(index)
                let x0 = Self.unit(seed * 12.9898) * size.width
                let speed = 30 + 50 * Self.unit(seed * 78.233)
                let radius = 8 + 22 * Self.unit(seed * 39.425)
                let span = size.height + 4 * radius
                let y = span - (Self.unit(seed * 4.1414) * span + speed * elapsed).truncatingRemainder(dividingBy: span) - 2 * radius
                let x = x0 + 24 * sin(elapsed * 0.9 + seed)
                let dot = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(dot, with: .color(Brand.barColors[index % Brand.barColors.count].opacity(0.22)))
            }
        }
    }

    /// A fixed pseudo-random number in 0..<1 for `seed`.
    private static func unit(_ seed: Double) -> Double {
        let x = sin(seed) * 43758.5453
        return x - x.rounded(.down)
    }
}

/// The station card's music. It starts from where the card is up to, so its
/// last chord always lands as the programme starts, and stops if the card
/// goes early (a channel change, pausing, leaving the app).
@MainActor
final class StationMusic {
    /// The music's length, the card's time (`WatchModel.stationCardTime`).
    static let length = WatchModel.stationCardTime
    /// Its tempo (104 bpm) and first beat, for drawing in time with it.
    static let beat = 60.0 / 104
    static let firstBeat = 0.05
    /// How loud, under a programme's usual level.
    static let level: Float = 0.35

    private var player: AVAudioPlayer?

    /// Seconds into the card (and the music) at `date`, for one ending at `end`.
    static func elapsed(at date: Date, endingAt end: Date) -> Double {
        length - end.timeIntervalSince(date)
    }

    func play(endingAt end: Date) {
        let offset = Self.elapsed(at: .now, endingAt: end)
        // Nearly over already: stay quiet rather than blip.
        guard offset < Self.length - 1,
              let url = Bundle.main.url(forResource: "station-card", withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.currentTime = max(0, offset)
        player.volume = Self.level
        player.play()
        self.player = player
    }

    func stop() {
        guard let player else { return }
        self.player = nil
        player.setVolume(0, fadeDuration: 0.3)
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            player.stop()
        }
    }
}
