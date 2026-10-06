import GregularScreens
import SwiftUI

/// How each karaoke theme looks on Apple TV: its colours, its lettering,
/// and its animated backdrop (`KaraokeBackdrop`). The web version's are in
/// karaoke.css, to match.
struct KaraokeStyle {
    let background: [Color]
    let ink: Color
    let inkSoft: Color
    /// Lyrics as they're sung, headings, the highlight.
    let accent: Color
    /// The bouncing ball, badges, sparkles.
    let accent2: Color
    let card: Color
    let item: Color
    let design: Font.Design
    let weight: Font.Weight
    let uppercase: Bool
    let italic: Bool

    init(_ theme: KaraokeTheme) {
        switch theme {
        case .neonDisco:
            background = [Color(red: 0.07, green: 0.04, blue: 0.14), Color(red: 0.18, green: 0.03, blue: 0.2)]
            ink = .white
            inkSoft = .white.opacity(0.78)
            accent = Color(red: 1, green: 0.18, blue: 0.82)
            accent2 = Color(red: 0.18, green: 0.95, blue: 1)
            card = Color(red: 0.07, green: 0.03, blue: 0.14).opacity(0.85)
            item = .white.opacity(0.08)
            design = .rounded
            weight = .heavy
            uppercase = false
            italic = false
        case .karaokeBar:
            background = [Color(red: 0.02, green: 0.02, blue: 0.1), Color(red: 0.17, green: 0.1, blue: 0.48)]
            ink = .white
            inkSoft = .white.opacity(0.78)
            accent = Color(red: 1, green: 0.92, blue: 0.23)
            accent2 = Color(red: 1, green: 0.25, blue: 0.51)
            card = Color(red: 0.02, green: 0.02, blue: 0.16).opacity(0.88)
            item = .white.opacity(0.08)
            design = .monospaced
            weight = .black
            uppercase = true
            italic = false
        case .bubblegumPop:
            background = [Color(red: 1, green: 0.82, blue: 0.93), Color(red: 0.79, green: 0.95, blue: 1)]
            ink = Color(red: 0.23, green: 0.09, blue: 0.27)
            inkSoft = Color(red: 0.36, green: 0.18, blue: 0.42)
            accent = Color(red: 0.88, green: 0.13, blue: 0.48)
            accent2 = Color(red: 0.09, green: 0.47, blue: 0.79)
            card = .white.opacity(0.82)
            item = Color(red: 0.23, green: 0.09, blue: 0.27).opacity(0.08)
            design = .rounded
            weight = .bold
            uppercase = false
            italic = false
        case .vegasLounge:
            background = [Color(red: 0.48, green: 0.06, blue: 0.11), Color(red: 0.16, green: 0.01, blue: 0.04)]
            ink = Color(red: 1, green: 0.96, blue: 0.88)
            inkSoft = Color(red: 1, green: 0.96, blue: 0.88).opacity(0.8)
            accent = Color(red: 1, green: 0.8, blue: 0.3)
            accent2 = Color(red: 1, green: 0.42, blue: 0.42)
            card = Color(red: 0.16, green: 0.01, blue: 0.04).opacity(0.88)
            item = .white.opacity(0.07)
            design = .serif
            weight = .bold
            uppercase = false
            italic = true
        }
    }

    func font(_ size: CGFloat) -> Font {
        let font = Font.system(size: size, weight: weight, design: design)
        return italic ? font.italic() : font
    }

    /// Text as the theme shows it (the 80s bar's is all capitals).
    func cased(_ text: String) -> String {
        uppercase ? text.uppercased() : text
    }
}

/// A theme's moving backdrop: a mirror ball's sparkles, a starfield, rising
/// bubbles, or chasing marquee bulbs. Still, for viewers who ask for less motion.
struct KaraokeBackdrop: View {
    let theme: KaraokeTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = KaraokeStyle(theme)
        ZStack {
            LinearGradient(colors: style.background, startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    draw(in: &context, size: size, time: timeline.date.timeIntervalSinceReferenceDate, style: style)
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Where the `index`th sparkle sits, as a share of the width and height: spread about, the same every time.
    private static func spot(_ index: Int) -> (x: Double, y: Double) {
        let x = Double((index * 37) % 100) / 100
        let y = Double((index * 61 + 13) % 100) / 100
        return (x, y)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: Double, style: KaraokeStyle) {
        let spots = (0..<14).map(Self.spot)
        switch theme {
        case .neonDisco:
            for (index, spot) in spots.enumerated() {
                let twinkle = 0.5 + 0.5 * sin(time * 2.6 + Double(index))
                let radius = 6 + 10 * twinkle
                let colour = index.isMultiple(of: 2) ? style.accent : style.accent2
                context.fill(Circle().path(in: CGRect(x: spot.x * size.width - radius, y: spot.y * size.height - radius,
                                                      width: radius * 2, height: radius * 2)),
                             with: .color(colour.opacity(0.25 + 0.6 * twinkle)))
            }
        case .karaokeBar:
            for (index, spot) in spots.enumerated() {
                let travel = (time / 6 + Double(index) / 14).truncatingRemainder(dividingBy: 1)
                let y = (spot.y + travel * 0.5).truncatingRemainder(dividingBy: 1) * size.height
                let radius = 1.5 + 3 * travel
                context.fill(Circle().path(in: CGRect(x: spot.x * size.width, y: y, width: radius * 2, height: radius * 2)),
                             with: .color(.white.opacity(sin(travel * .pi))))
            }
        case .bubblegumPop:
            for (index, spot) in spots.enumerated() {
                let rise = (time / 7 + Double(index) / 14).truncatingRemainder(dividingBy: 1)
                let y = size.height * (1.1 - rise * 1.3)
                let radius = 24 + 30 * spot.y
                let rect = CGRect(x: spot.x * size.width + 20 * sin(time + Double(index)), y: y, width: radius * 2, height: radius * 2)
                context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.3)))
                context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.8)), lineWidth: 3)
            }
        case .vegasLounge:
            // Bulbs round the edge, every other one lit, the lit ones chasing round.
            let gap = 48.0
            let lit = Int(time * 2.5) % 2
            var index = 0
            func bulb(_ x: Double, _ y: Double) {
                let on = index % 2 == lit
                context.fill(Circle().path(in: CGRect(x: x - 7, y: y - 7, width: 14, height: 14)),
                             with: .color(on ? style.accent : style.accent.opacity(0.25)))
                index += 1
            }
            for x in stride(from: gap / 2, to: size.width, by: gap) { bulb(x, 24); bulb(x, size.height - 24) }
            for y in stride(from: gap * 1.5, to: size.height - gap, by: gap) { bulb(24, y); bulb(size.width - 24, y) }
        }
    }
}
