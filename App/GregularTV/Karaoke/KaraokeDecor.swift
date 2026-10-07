import GregularScreens
import SwiftUI

// Karaoke's decorations on Apple TV, in each theme's style: headings,
// song pictures, the loading animation, countdown dots and confetti.

/// A heading in its theme's lettering: a neon tube that flickers on, 80s
/// chrome, bouncing bubble letters, or Vegas gold (in a frame of bulbs,
/// when `framed`).
struct KaraokeTitle: View {
    let text: String
    let size: CGFloat
    let theme: KaraokeTheme
    var framed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lit = false

    var body: some View {
        let style = KaraokeStyle(theme)
        let text = style.cased(self.text)
        Group {
            switch theme {
            case .neonDisco:
                Text(text).font(style.font(size)).foregroundStyle(.white)
                    .shadow(color: style.accent, radius: 2)
                    .shadow(color: style.accent, radius: size * 0.1)
                    .shadow(color: style.accent.opacity(0.7), radius: size * 0.3)
                    .keyframeAnimator(initialValue: 1.0, trigger: lit) { view, opacity in view.opacity(opacity) } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0.15, duration: 0.05)
                            LinearKeyframe(1, duration: 0.05)
                            LinearKeyframe(0.35, duration: 0.08)
                            LinearKeyframe(1, duration: 0.1)
                        }
                    }
            case .karaokeBar:
                Text(text).font(style.font(size)).italic()
                    .foregroundStyle(LinearGradient(stops: [
                        .init(color: .white, location: 0), .init(color: Color(red: 0.7, green: 0.85, blue: 1), location: 0.47),
                        .init(color: Color(red: 0.2, green: 0.12, blue: 0.5), location: 0.5), .init(color: Color(red: 1, green: 0.45, blue: 0.8), location: 0.56),
                        .init(color: .white, location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .shadow(color: style.accent2, radius: 0, x: size * 0.04, y: size * 0.04)
                    .shadow(color: .black, radius: 0, x: size * 0.07, y: size * 0.07)
            case .bubblegumPop:
                BubbleLetters(text: text, size: size, style: style, still: reduceMotion)
            case .vegasLounge:
                Text(text).font(style.font(size))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.7), style.accent,
                                                             Color(red: 0.72, green: 0.52, blue: 0.1), Color(red: 1, green: 0.88, blue: 0.55)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(red: 0.2, green: 0, blue: 0.03), radius: 0, x: 0, y: size * 0.05)
                    .padding(.horizontal, framed ? size * 0.5 : 0)
                    .padding(.vertical, framed ? size * 0.25 : 0)
                    .overlay { if framed { BulbFrame(colour: style.accent, still: reduceMotion) } }
                    .padding(.horizontal, framed ? -size * 0.5 : 0)
            }
        }
        // Room for Vegas's frame in every theme, so sampling one never moves what's below.
        .padding(.vertical, framed && theme != .vegasLounge ? size * 0.25 : 0)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .onAppear { if !reduceMotion { lit.toggle() } }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Bubblegum's letters, each bobbing a moment after the one before.
private struct BubbleLetters: View {
    let text: String
    let size: CGFloat
    let style: KaraokeStyle
    let still: Bool

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                ForEach(Array(text.enumerated()), id: \.offset) { index, letter in
                    Text(String(letter))
                        .offset(y: still ? 0 : sin(time * 3 + Double(index) * 0.55) * size * 0.05)
                }
            }
            .font(style.font(size))
            .foregroundStyle(style.accent)
            .shadow(color: .white, radius: 0, x: 3, y: 3)
            .shadow(color: .white, radius: 0, x: -3, y: -3)
            .shadow(color: .white, radius: 0, x: 3, y: -3)
            .shadow(color: .white, radius: 0, x: -3, y: 3)
            .shadow(color: style.ink.opacity(0.25), radius: 0, x: 0, y: size * 0.08)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Marquee bulbs round a rounded frame, chasing.
struct BulbFrame: View {
    let colour: Color
    var still = false

    var body: some View {
        TimelineView(.animation(paused: still)) { timeline in
            Canvas { context, size in
                let lit = Int(timeline.date.timeIntervalSinceReferenceDate * 4) % 3
                let inset = 10.0
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                context.stroke(Path(roundedRect: rect, cornerRadius: 12), with: .color(colour.opacity(0.7)), lineWidth: 3)
                var points: [CGPoint] = []
                for x in stride(from: rect.minX, to: rect.maxX, by: 34) {
                    points.append(CGPoint(x: x, y: rect.minY))
                }
                for y in stride(from: rect.minY, to: rect.maxY, by: 34) {
                    points.append(CGPoint(x: rect.maxX, y: y))
                }
                for x in stride(from: rect.maxX, to: rect.minX, by: -34) {
                    points.append(CGPoint(x: x, y: rect.maxY))
                }
                for y in stride(from: rect.maxY, to: rect.minY, by: -34) {
                    points.append(CGPoint(x: rect.minX, y: y))
                }
                for (index, point) in points.enumerated() {
                    let on = index % 3 == lit
                    let bulb = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                    if on {
                        context.fill(Circle().path(in: bulb.insetBy(dx: -6, dy: -6)),
                                     with: .radialGradient(Gradient(colors: [colour.opacity(0.7), .clear]),
                                                           center: CGPoint(x: bulb.midX, y: bulb.midY), startRadius: 0, endRadius: 12))
                    }
                    context.fill(Circle().path(in: bulb), with: .color(on ? Color(red: 1, green: 0.97, blue: 0.8) : colour.opacity(0.35)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A song's, album's or artist's picture (`KaraokeCover`): a pattern in the
/// theme's colours with its initials, round for an artist.
struct KaraokeCoverView: View {
    let cover: KaraokeCover
    let style: KaraokeStyle
    var size: CGFloat = 84
    var round = false

    var body: some View {
        let shape = round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: min(style.corner, size * 0.16)))
        Canvas { context, canvas in
            let back = style.palette[cover.back]
            let front = style.palette[cover.front]
            let rect = CGRect(origin: .zero, size: canvas)
            let s = canvas.width
            context.fill(Path(rect), with: .color(back))
            var pattern = context
            pattern.translateBy(x: s / 2, y: s / 2)
            pattern.rotate(by: .degrees(Double(cover.angle)))
            switch cover.pattern {
            case .stripes:
                for x in stride(from: -s, to: s, by: s / 4) {
                    pattern.fill(Path(CGRect(x: x, y: -s, width: s / 8, height: s * 2)), with: .color(front))
                }
            case .rings:
                for radius in stride(from: s * 0.9, to: 0, by: -s / 7) {
                    pattern.stroke(Circle().path(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)),
                                   with: .color(front), lineWidth: s / 18)
                }
            case .dots:
                for row in -3...3 {
                    for column in -3...3 {
                        let x = Double(column) * s / 4 + (row.isMultiple(of: 2) ? 0 : s / 8)
                        let r = s / 14
                        pattern.fill(Circle().path(in: CGRect(x: x - r, y: Double(row) * s / 4 - r, width: r * 2, height: r * 2)),
                                     with: .color(front))
                    }
                }
            case .sunburst:
                for ray in 0..<12 where ray.isMultiple(of: 2) {
                    var wedge = Path()
                    wedge.move(to: CGPoint(x: -s / 2, y: -s / 2))
                    let a0 = Double(ray) / 24 * .pi
                    let a1 = Double(ray + 1) / 24 * .pi
                    wedge.addLine(to: CGPoint(x: -s / 2 + cos(a0) * s * 2, y: -s / 2 + sin(a0) * s * 2))
                    wedge.addLine(to: CGPoint(x: -s / 2 + cos(a1) * s * 2, y: -s / 2 + sin(a1) * s * 2))
                    wedge.closeSubpath()
                    pattern.fill(wedge, with: .color(front))
                }
            case .checks:
                let cell = s / 4
                for row in -4..<4 {
                    for column in -4..<4 where (row + column).isMultiple(of: 2) {
                        pattern.fill(Path(CGRect(x: Double(column) * cell, y: Double(row) * cell, width: cell, height: cell)),
                                     with: .color(front))
                    }
                }
            case .split:
                pattern.fill(Path(CGRect(x: 0, y: -s, width: s, height: s * 2)), with: .color(front))
            }
            // A sheen, like a printed sleeve.
            context.fill(Path(rect), with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.15)]),
                                                           startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
            if !cover.initials.isEmpty {
                let initials = context.resolve(Text(cover.initials).font(style.font(s * 0.36)).foregroundStyle(style.coverInk))
                var label = context
                label.addFilter(.shadow(color: .black.opacity(0.45), radius: 3, y: 2))
                label.draw(initials, at: CGPoint(x: s / 2, y: s / 2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

/// "Get ready!"'s animation, in the theme's style: a turning mirror ball's
/// glints, 80s blocks filling, bubbles bouncing, or bulbs chasing round.
struct KaraokeLoader: View {
    let theme: KaraokeTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = KaraokeStyle(theme)
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                switch theme {
                case .neonDisco:
                    for ring in 0..<3 {
                        let radius = 22.0 + Double(ring) * 16
                        var arc = Path()
                        let start = time * (2.4 - Double(ring) * 0.6) * (ring == 1 ? -1 : 1)
                        arc.addArc(center: centre, radius: radius, startAngle: .radians(start), endAngle: .radians(start + 2.2), clockwise: false)
                        context.stroke(arc, with: .color(ring == 1 ? style.accent2 : style.accent), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    }
                case .karaokeBar:
                    let blocks = 10
                    let filled = Int(time * 8) % (blocks + 3)
                    for index in 0..<blocks {
                        let rect = CGRect(x: centre.x - 150 + Double(index) * 30, y: centre.y - 14, width: 24, height: 28)
                        context.fill(Path(rect), with: .color(index < filled ? style.accent : style.ink.opacity(0.15)))
                    }
                case .bubblegumPop:
                    for index in 0..<3 {
                        let hop = abs(sin(time * 4 - Double(index) * 0.6))
                        let rect = CGRect(x: centre.x - 70 + Double(index) * 50 - 18, y: centre.y + 10 - hop * 40 - 18, width: 36, height: 36)
                        context.fill(Circle().path(in: rect), with: .color(style.palette[index].opacity(0.8)))
                        context.stroke(Circle().path(in: rect), with: .color(style.accent), lineWidth: 4)
                    }
                case .vegasLounge:
                    let count = 12
                    let lit = Int(time * 10) % count
                    for index in 0..<count {
                        let angle = Double(index) / Double(count) * 2 * .pi
                        let point = CGPoint(x: centre.x + cos(angle) * 48, y: centre.y + sin(angle) * 48)
                        let near = (index - lit + count) % count < 3
                        context.fill(Circle().path(in: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)),
                                     with: .color(near ? Color(red: 1, green: 0.95, blue: 0.7) : style.accent.opacity(0.3)))
                    }
                }
            }
        }
        .frame(width: 320, height: 120)
        .accessibilityLabel(KaraokeText.getReady)
    }
}

/// The countdown before singing: a dot a second, in the theme's style.
struct CountdownDots: View {
    let count: Int?
    let style: KaraokeStyle

    var body: some View {
        HStack(spacing: 36) {
            ForEach(0..<(count ?? 0), id: \.self) { _ in
                dot.transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(height: 56)
        .animation(.spring(duration: 0.35), value: count)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var dot: some View {
        switch style.look {
        case .glow:
            Circle().fill(.white).frame(width: 40, height: 40)
                .shadow(color: style.accent, radius: 6).shadow(color: style.accent, radius: 16)
        case .block:
            Rectangle().fill(style.accent).frame(width: 40, height: 40)
                .shadow(color: .black, radius: 0, x: 5, y: 5)
        case .squish:
            Circle().fill(.white.opacity(0.5)).frame(width: 46, height: 46)
                .overlay(Circle().stroke(style.accent, lineWidth: 5))
        case .gilt:
            Circle().fill(Color(red: 1, green: 0.95, blue: 0.7)).frame(width: 34, height: 34)
                .shadow(color: style.accent, radius: 12)
        }
    }
}

/// Confetti bursting from a point and falling: one burst for each date in
/// `bursts`, each gone after a few seconds.
struct Confetti: View {
    struct Burst: Identifiable, Equatable {
        let id: Int
        let start: Date
        /// Where it bursts from, as a share of the width and height.
        let from: UnitPoint
        let pieces: Int
    }

    let bursts: [Burst]
    let style: KaraokeStyle
    static let lasts: TimeInterval = 3

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let colours = style.palette + [style.accent, style.accent2]
                for burst in bursts {
                    let t = now.timeIntervalSince(burst.start)
                    guard t >= 0, t < Self.lasts else { continue }
                    for piece in 0..<burst.pieces {
                        let seed = Double(piece * 7919 + burst.id * 104_729)
                        let angle = -(.pi / 2) + (seed.truncatingRemainder(dividingBy: 1000) / 1000 - 0.5) * 2.4
                        let speed = 600 + seed.truncatingRemainder(dividingBy: 700)
                        let x = burst.from.x * size.width + cos(angle) * speed * t * 0.9
                        let y = burst.from.y * size.height + sin(angle) * speed * t + 900 * t * t
                        var bit = context
                        bit.opacity = max(0, 1 - t / Self.lasts)
                        bit.translateBy(x: x, y: y)
                        bit.rotate(by: .radians(t * (4 + seed.truncatingRemainder(dividingBy: 5)) + seed))
                        bit.scaleBy(x: cos(t * 6 + seed), y: 1)
                        bit.fill(Path(CGRect(x: -8, y: -5, width: 16, height: 10)), with: .color(colours[piece % colours.count]))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A row's little label ("Video", "No lyrics"), readable on a row lit or not.
struct KaraokeBadge: View {
    let text: String
    let style: KaraokeStyle
    var quiet = false

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(quiet ? style.inkSoft : style.accent2)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(style.card.opacity(1), in: Capsule())
            .overlay(Capsule().stroke(quiet ? style.inkSoft.opacity(0.6) : style.accent2, lineWidth: 2))
    }
}

extension View {
    /// On a pill of the theme's accent (for Vegas, gold-edged velvet): Press Play, the queue's count.
    func accentCapsule(_ style: KaraokeStyle) -> some View {
        background(style.look == .gilt ? style.card.opacity(1) : style.accent, in: Capsule())
            .overlay { if style.look == .gilt { Capsule().stroke(style.accent, lineWidth: 3) } }
    }
}

/// Rows sliding in, one a moment after another, as a menu opens.
struct RowEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(x: shown || reduceMotion ? 0 : 40)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3).delay(Double(min(index, 10)) * 0.035)) { shown = true }
            }
    }
}
