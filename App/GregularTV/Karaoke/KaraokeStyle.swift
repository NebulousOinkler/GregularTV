import GregularScreens
import SwiftUI

/// How each karaoke theme looks on Apple TV: its colours, its lettering,
/// how a highlighted item shows, how menus come and go, and its animated
/// backdrop (`KaraokeBackdrop`). The web version's are in karaoke.css, to
/// match.
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
    /// The colours song pictures are made from (`KaraokeCover`).
    let palette: [Color]
    /// The initials on a song's picture.
    let coverInk: Color
    let design: Font.Design
    let weight: Font.Weight
    let uppercase: Bool
    let italic: Bool
    let look: Look
    /// How round a row's corners are.
    let corner: CGFloat

    /// How a highlighted item shows.
    enum Look {
        /// Neon: lit in the accent, glowing, with a flicker as it lights.
        case glow
        /// 80s: a square-cornered bar with a ► beside it.
        case block
        /// Bubblegum: a springy bounce.
        case squish
        /// Vegas: gold edged, with a glint running across.
        case gilt
    }

    init(_ theme: KaraokeTheme) {
        switch theme {
        case .neonDisco:
            background = [Color(red: 0.07, green: 0.04, blue: 0.14), Color(red: 0.18, green: 0.03, blue: 0.2)]
            ink = .white
            inkSoft = .white.opacity(0.78)
            accent = Color(red: 1, green: 0.18, blue: 0.82)
            accent2 = Color(red: 0.18, green: 0.95, blue: 1)
            card = Color(red: 0.07, green: 0.03, blue: 0.14).opacity(0.92)
            item = Color(red: 0.16, green: 0.08, blue: 0.24).opacity(0.94)
            palette = [Color(red: 1, green: 0.18, blue: 0.82), Color(red: 0.18, green: 0.95, blue: 1),
                       Color(red: 0.45, green: 0.2, blue: 1), Color(red: 1, green: 0.85, blue: 0.2)]
            coverInk = .white
            design = .rounded
            weight = .heavy
            uppercase = false
            italic = false
            look = .glow
            corner = 18
        case .karaokeBar:
            background = [Color(red: 0.02, green: 0.02, blue: 0.1), Color(red: 0.17, green: 0.1, blue: 0.48)]
            ink = .white
            inkSoft = .white.opacity(0.78)
            accent = Color(red: 1, green: 0.92, blue: 0.23)
            accent2 = Color(red: 1, green: 0.25, blue: 0.51)
            card = Color(red: 0.02, green: 0.02, blue: 0.16).opacity(0.94)
            item = Color(red: 0.08, green: 0.06, blue: 0.3).opacity(0.94)
            palette = [Color(red: 1, green: 0.25, blue: 0.51), Color(red: 0.1, green: 0.8, blue: 0.95),
                       Color(red: 1, green: 0.92, blue: 0.23), Color(red: 0.42, green: 0.18, blue: 0.85)]
            coverInk = .white
            design = .monospaced
            weight = .black
            uppercase = true
            italic = false
            look = .block
            corner = 4
        case .bubblegumPop:
            background = [Color(red: 1, green: 0.82, blue: 0.93), Color(red: 0.79, green: 0.95, blue: 1)]
            ink = Color(red: 0.23, green: 0.09, blue: 0.27)
            inkSoft = Color(red: 0.36, green: 0.18, blue: 0.42)
            accent = Color(red: 0.88, green: 0.13, blue: 0.48)
            accent2 = Color(red: 0.09, green: 0.47, blue: 0.79)
            card = Color.white.opacity(0.9)
            item = Color.white.opacity(0.78)
            palette = [Color(red: 1, green: 0.6, blue: 0.8), Color(red: 0.6, green: 0.85, blue: 1),
                       Color(red: 1, green: 0.92, blue: 0.55), Color(red: 0.78, green: 0.66, blue: 1)]
            coverInk = Color(red: 0.23, green: 0.09, blue: 0.27)
            design = .rounded
            weight = .bold
            uppercase = false
            italic = false
            look = .squish
            corner = 32
        case .vegasLounge:
            background = [Color(red: 0.48, green: 0.06, blue: 0.11), Color(red: 0.16, green: 0.01, blue: 0.04)]
            ink = Color(red: 1, green: 0.96, blue: 0.88)
            inkSoft = Color(red: 1, green: 0.96, blue: 0.88).opacity(0.8)
            accent = Color(red: 1, green: 0.8, blue: 0.3)
            accent2 = Color(red: 1, green: 0.42, blue: 0.42)
            card = Color(red: 0.16, green: 0.01, blue: 0.04).opacity(0.94)
            item = Color(red: 0.28, green: 0.03, blue: 0.07).opacity(0.94)
            palette = [Color(red: 0.55, green: 0.05, blue: 0.12), Color(red: 1, green: 0.8, blue: 0.3),
                       Color(red: 0.12, green: 0.1, blue: 0.12), Color(red: 0.95, green: 0.9, blue: 0.8)]
            coverInk = Color(red: 1, green: 0.96, blue: 0.88)
            design = .serif
            weight = .bold
            uppercase = false
            italic = true
            look = .gilt
            corner = 12
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

    /// Text on the accent: the card's colour, solid.
    var onAccent: Color { look == .gilt ? accent : card.opacity(1) }

    /// How a menu comes in.
    var transition: AnyTransition {
        switch look {
        case .glow: .asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity)
        case .block: .asymmetric(insertion: .modifier(active: Wipe(shown: 0), identity: Wipe(shown: 1)), removal: .opacity)
        case .squish: .asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity), removal: .opacity)
        case .gilt: .asymmetric(insertion: .modifier(active: Curtain(shown: 0), identity: Curtain(shown: 1)), removal: .opacity)
        }
    }

    /// How menus move: bubblegum's bounce.
    var animation: Animation {
        switch look {
        case .glow: .easeOut(duration: 0.3)
        case .block: .linear(duration: 0.25)
        case .squish: .bouncy(duration: 0.45, extraBounce: 0.15)
        case .gilt: .easeInOut(duration: 0.45)
        }
    }
}

/// The 80s menu wipe: shown from the left, like a colour wipe.
private struct Wipe: ViewModifier {
    let shown: CGFloat

    func body(content: Content) -> some View {
        content.mask(alignment: .leading) {
            GeometryReader { geometry in Rectangle().frame(width: geometry.size.width * shown) }
        }
    }
}

/// Vegas's: opening from the middle, like a curtain.
private struct Curtain: ViewModifier {
    let shown: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geometry in
                Rectangle().frame(width: geometry.size.width * shown).frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Backdrops

/// A theme's moving backdrop, drawn as it plays: a mirror ball over a lit
/// dance floor; a sunset over a neon grid; bubbles, stars and hearts over
/// candy stripes; or velvet curtains, spotlights and marquee bulbs. Still,
/// for viewers who ask for less motion. `pulse` (0 to 1, from the lyrics'
/// timings) makes it throb with the song.
struct KaraokeBackdrop: View {
    let theme: KaraokeTheme
    var pulse: () -> Double = { 0 }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let style = KaraokeStyle(theme)
        ZStack {
            LinearGradient(colors: style.background, startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    let time = reduceMotion ? 12 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000)
                    let beat = reduceMotion ? 0 : pulse()
                    switch theme {
                    case .neonDisco: Self.disco(&context, size, time, beat, style)
                    case .karaokeBar: Self.sunset(&context, size, time, beat, style)
                    case .bubblegumPop: Self.bubbles(&context, size, time, beat, style)
                    case .vegasLounge: Self.lounge(&context, size, time, beat, style)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    /// Where the `index`th thing sits, as a share of the width and height: spread about, the same every time.
    static func spot(_ index: Int) -> (x: Double, y: Double) {
        (Double((index * 37) % 100) / 100, Double((index * 61 + 13) % 100) / 100)
    }

    // MARK: Neon disco

    private static func disco(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double, _ beat: Double, _ style: KaraokeStyle) {
        let (w, h) = (size.width, size.height)
        let colours = [style.accent, style.accent2, Color(red: 0.45, green: 0.2, blue: 1)]
        // The dance floor: tiles in perspective, lighting up in turn.
        let horizon = h * 0.66
        let rows = 6, columns = 12
        let step = Int(time * 2)
        for row in 0..<rows {
            let y0 = horizon + (h - horizon) * pow(Double(row) / Double(rows), 1.6)
            let y1 = horizon + (h - horizon) * pow(Double(row + 1) / Double(rows), 1.6)
            let spread0 = 0.35 + 0.65 * Double(row) / Double(rows)
            let spread1 = 0.35 + 0.65 * Double(row + 1) / Double(rows)
            for column in 0..<columns {
                let lit = (column + row * 3 + step) % 5 == 0 || (column * 7 + row + step) % 11 == 0
                let colour = colours[(column + row + step / 2) % colours.count]
                func x(_ c: Int, _ spread: Double) -> Double { w / 2 + (Double(c) / Double(columns) - 0.5) * w * 1.3 * spread }
                var tile = Path()
                tile.move(to: CGPoint(x: x(column, spread0) + 2, y: y0 + 2))
                tile.addLine(to: CGPoint(x: x(column + 1, spread0) - 2, y: y0 + 2))
                tile.addLine(to: CGPoint(x: x(column + 1, spread1) - 2, y: y1 - 2))
                tile.addLine(to: CGPoint(x: x(column, spread1) + 2, y: y1 - 2))
                tile.closeSubpath()
                context.fill(tile, with: .color(colour.opacity(lit ? 0.38 + 0.4 * beat : 0.07)))
            }
        }
        // Beams from the ball, sweeping.
        let ball = CGPoint(x: w / 2, y: h * 0.1)
        for index in 0..<6 {
            let angle = .pi / 2 + sin(time * 0.45 + Double(index) * 1.1) * 0.75
            let reach = h * 1.1
            let spread = 0.07
            var beam = Path()
            beam.move(to: ball)
            beam.addLine(to: CGPoint(x: ball.x + cos(angle - spread) * reach, y: ball.y + sin(angle - spread) * reach))
            beam.addLine(to: CGPoint(x: ball.x + cos(angle + spread) * reach, y: ball.y + sin(angle + spread) * reach))
            beam.closeSubpath()
            let colour = colours[index % colours.count]
            context.fill(beam, with: .linearGradient(Gradient(colors: [colour.opacity(0.28 + 0.25 * beat), colour.opacity(0)]),
                                                      startPoint: ball, endPoint: CGPoint(x: ball.x, y: ball.y + reach)))
        }
        // Reflections, wheeling round the room.
        for index in 0..<16 {
            let spot = spot(index)
            let x = (spot.x + time * 0.02 * (index.isMultiple(of: 2) ? 1 : -1)).truncatingRemainder(dividingBy: 1)
            let twinkle = 0.5 + 0.5 * sin(time * 2.6 + Double(index))
            let radius = 4 + 8 * twinkle
            context.fill(Circle().path(in: CGRect(x: (x < 0 ? x + 1 : x) * w - radius, y: spot.y * horizon - radius,
                                                  width: radius * 2, height: radius * 2)),
                         with: .color(colours[index % 2].opacity(0.25 + 0.5 * twinkle)))
        }
        // The mirror ball: facets catching the light as it turns.
        let radius = h * 0.075
        let ballRect = CGRect(x: ball.x - radius, y: ball.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path { $0.move(to: CGPoint(x: ball.x, y: 0)); $0.addLine(to: CGPoint(x: ball.x, y: ball.y - radius)) },
                       with: .color(.white.opacity(0.4)), lineWidth: 2)
        context.fill(Circle().path(in: ballRect), with: .color(Color(white: 0.35)))
        var facets = context
        facets.clip(to: Circle().path(in: ballRect))
        let tile = radius / 4
        for row in -4..<4 {
            for column in -5..<5 {
                let shine = 0.5 + 0.5 * sin(time * 2.2 + Double(column) * 0.9 + Double(row) * 1.7)
                let x = ball.x + (Double(column) + (time * 0.8).truncatingRemainder(dividingBy: 1)) * tile
                let rect = CGRect(x: x, y: ball.y + Double(row) * tile, width: tile - 2, height: tile - 2)
                facets.fill(Path(rect), with: .color(Color(white: 0.55 + 0.45 * shine)))
            }
        }
        context.fill(Circle().path(in: ballRect.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.25 + 0.3 * beat), .clear]),
                                           center: ball, startRadius: radius * 0.8, endRadius: radius * 1.6))
    }

    // MARK: 80s karaoke bar

    private static func sunset(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double, _ beat: Double, _ style: KaraokeStyle) {
        let (w, h) = (size.width, size.height)
        let horizon = h * 0.62
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.12), Color(red: 0.25, green: 0.06, blue: 0.42),
                                                             Color(red: 0.75, green: 0.15, blue: 0.5)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        // Stars, twinkling.
        for index in 0..<30 {
            let spot = spot(index * 3 + 1)
            let twinkle = 0.5 + 0.5 * sin(time * 1.7 + Double(index) * 2.3)
            let radius = 1 + 1.5 * twinkle
            context.fill(Circle().path(in: CGRect(x: spot.x * w, y: spot.y * horizon * 0.6, width: radius * 2, height: radius * 2)),
                         with: .color(.white.opacity(0.3 + 0.6 * twinkle)))
        }
        // The sun, sliced, its slices sliding down.
        let sunRadius = h * 0.2
        let centre = CGPoint(x: w / 2, y: horizon - sunRadius * 0.3)
        context.drawLayer { layer in
            let sun = CGRect(x: centre.x - sunRadius, y: centre.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)
            layer.fill(Circle().path(in: sun), with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.4), Color(red: 1, green: 0.45, blue: 0.3), Color(red: 1, green: 0.15, blue: 0.55)]),
                startPoint: CGPoint(x: 0, y: sun.minY), endPoint: CGPoint(x: 0, y: sun.maxY)))
            layer.blendMode = .destinationOut
            let drift = (time * 0.25).truncatingRemainder(dividingBy: 1)
            for slice in 0..<7 {
                let along = (Double(slice) + drift) / 7
                let y = centre.y + sunRadius * along
                layer.fill(Path(CGRect(x: sun.minX, y: y, width: sun.width, height: 2 + 12 * along)), with: .color(.black))
            }
        }
        context.fill(Circle().path(in: CGRect(x: centre.x - sunRadius * 1.6, y: centre.y - sunRadius * 1.6,
                                              width: sunRadius * 3.2, height: sunRadius * 3.2)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.3, blue: 0.6).opacity(0.25 + 0.3 * beat), .clear]),
                                           center: centre, startRadius: sunRadius, endRadius: sunRadius * 1.6))
        // The grid, running towards us.
        context.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.02, blue: 0.25), Color(red: 0.02, green: 0.01, blue: 0.08)]),
                                           startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        let line = Color(red: 1, green: 0.25, blue: 0.75).opacity(0.55 + 0.4 * beat)
        var grid = Path()
        let lines = 10
        let run = (time * 0.5).truncatingRemainder(dividingBy: 1)
        for index in 0..<lines {
            let z = (Double(index) + run) / Double(lines)
            let y = horizon + (h - horizon) * z * z
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: w, y: y))
        }
        for index in -12...12 {
            grid.move(to: CGPoint(x: w / 2 + Double(index) * w * 0.012, y: horizon))
            grid.addLine(to: CGPoint(x: w / 2 + Double(index) * w * 0.16, y: h))
        }
        context.stroke(grid, with: .color(line), lineWidth: 2)
        context.fill(Path(CGRect(x: 0, y: horizon - 1, width: w, height: 3)), with: .color(Color(red: 1, green: 0.5, blue: 0.85)))
        // Scan lines, faintly.
        var scan = Path()
        for y in stride(from: 0.0, to: h, by: 6) { scan.addRect(CGRect(x: 0, y: y, width: w, height: 1.5)) }
        context.fill(scan, with: .color(.black.opacity(0.18)))
    }

    // MARK: Bubblegum pop

    private static func bubbles(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double, _ beat: Double, _ style: KaraokeStyle) {
        let (w, h) = (size.width, size.height)
        // Candy stripes, drifting.
        var stripes = Path()
        let gap = 140.0
        let shift = (time * 18).truncatingRemainder(dividingBy: gap * 2)
        for index in stride(from: -h, to: w + h, by: gap * 2) {
            let x = index + shift
            stripes.move(to: CGPoint(x: x, y: 0))
            stripes.addLine(to: CGPoint(x: x + gap, y: 0))
            stripes.addLine(to: CGPoint(x: x + gap - h, y: h))
            stripes.addLine(to: CGPoint(x: x - h, y: h))
            stripes.closeSubpath()
        }
        context.fill(stripes, with: .color(.white.opacity(0.2)))
        // Sprinkles.
        let sprinkleColours = [style.accent, style.accent2, Color(red: 1, green: 0.8, blue: 0.2), Color(red: 0.4, green: 0.8, blue: 0.4)]
        for index in 0..<26 {
            let spot = spot(index * 5 + 2)
            var sprinkle = context
            sprinkle.translateBy(x: spot.x * w, y: (spot.y + time * 0.01).truncatingRemainder(dividingBy: 1) * h)
            sprinkle.rotate(by: .radians(Double(index) + time * 0.3))
            sprinkle.fill(Path(roundedRect: CGRect(x: -9, y: -3, width: 18, height: 6), cornerRadius: 3),
                          with: .color(sprinkleColours[index % sprinkleColours.count].opacity(0.55)))
        }
        // Stars and hearts, bobbing and turning.
        for index in 0..<8 {
            let spot = spot(index * 11 + 4)
            var shape = context
            shape.translateBy(x: spot.x * w, y: spot.y * h + 18 * sin(time * 1.3 + Double(index)))
            shape.rotate(by: .degrees(14 * sin(time + Double(index))))
            let scale = (0.8 + 0.4 * spot.y) * (1 + 0.15 * beat)
            shape.scaleBy(x: scale, y: scale)
            let path = index.isMultiple(of: 2) ? Self.heart(30) : Self.star(32)
            shape.fill(path, with: .color(sprinkleColours[index % 3].opacity(0.75)))
            shape.stroke(path, with: .color(.white), lineWidth: 4)
        }
        // Bubbles rising, with a shine.
        for index in 0..<16 {
            let spot = spot(index)
            let rise = (time / 8 + Double(index) / 16).truncatingRemainder(dividingBy: 1)
            let radius = (22 + 34 * spot.y) * (1 + 0.12 * beat)
            let x = spot.x * w + 24 * sin(time * 0.9 + Double(index))
            let y = h * (1.1 - rise * 1.3)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Circle().path(in: rect), with: .color(.white.opacity(0.22)))
            context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.85)), lineWidth: 3)
            context.fill(Ellipse().path(in: CGRect(x: x - radius * 0.55, y: y - radius * 0.6, width: radius * 0.45, height: radius * 0.28)),
                         with: .color(.white.opacity(0.85)))
        }
    }

    static func star(_ radius: Double) -> Path {
        Path { path in
            for point in 0..<10 {
                let r = point.isMultiple(of: 2) ? radius : radius * 0.45
                let angle = Double(point) * .pi / 5 - .pi / 2
                let p = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
                if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }

    static func heart(_ size: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size * 0.9))
            path.addCurve(to: CGPoint(x: -size, y: -size * 0.1), control1: CGPoint(x: -size * 0.6, y: size * 0.5),
                          control2: CGPoint(x: -size, y: size * 0.25))
            path.addArc(center: CGPoint(x: -size * 0.5, y: -size * 0.15), radius: size * 0.5, startAngle: .degrees(180),
                        endAngle: .degrees(0), clockwise: false)
            path.addArc(center: CGPoint(x: size * 0.5, y: -size * 0.15), radius: size * 0.5, startAngle: .degrees(180),
                        endAngle: .degrees(0), clockwise: false)
            path.addCurve(to: CGPoint(x: 0, y: size * 0.9), control1: CGPoint(x: size, y: size * 0.25),
                          control2: CGPoint(x: size * 0.6, y: size * 0.5))
        }
    }

    // MARK: Vegas lounge

    private static func lounge(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double, _ beat: Double, _ style: KaraokeStyle) {
        let (w, h) = (size.width, size.height)
        // Spotlights, sweeping the stage.
        for index in 0..<2 {
            let x = w * (0.5 + (index == 0 ? -1 : 1) * 0.22 * sin(time * 0.5 + Double(index)))
            let pool = CGRect(x: x - w * 0.18, y: h * 0.55, width: w * 0.36, height: h * 0.5)
            context.fill(Ellipse().path(in: pool),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.75).opacity(0.22 + 0.25 * beat), .clear]),
                                               center: CGPoint(x: pool.midX, y: pool.midY), startRadius: 0, endRadius: w * 0.18))
            var beam = Path()
            beam.move(to: CGPoint(x: w * (index == 0 ? 0.2 : 0.8), y: 0))
            beam.addLine(to: CGPoint(x: pool.minX + pool.width * 0.15, y: pool.midY))
            beam.addLine(to: CGPoint(x: pool.maxX - pool.width * 0.15, y: pool.midY))
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.92, blue: 0.75).opacity(0.02),
                                                                       Color(red: 1, green: 0.92, blue: 0.75).opacity(0.1 + 0.1 * beat)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: pool.midY)))
        }
        // Gold glints.
        for index in 0..<12 {
            let spot = spot(index * 7 + 3)
            let twinkle = max(0, sin(time * 1.6 + Double(index) * 1.9))
            guard twinkle > 0.2 else { continue }
            var glint = context
            glint.translateBy(x: w * (0.15 + 0.7 * spot.x), y: h * 0.12 + spot.y * h * 0.7)
            glint.scaleBy(x: twinkle, y: twinkle)
            glint.fill(Self.sparkle(16), with: .color(style.accent.opacity(0.9)))
        }
        // Velvet curtains, swaying a little, under a scalloped pelmet.
        let drape = w * 0.13
        for side in [0.0, 1.0] {
            let folds = 6
            for fold in 0..<folds {
                let sway = 6 * sin(time * 0.7 + Double(fold))
                let x0 = side == 0 ? Double(fold) * drape / Double(folds) : w - drape + Double(fold) * drape / Double(folds)
                let rect = CGRect(x: x0 + sway, y: 0, width: drape / Double(folds) + 2, height: h)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.25, green: 0.01, blue: 0.04), Color(red: 0.62, green: 0.06, blue: 0.13),
                                      Color(red: 0.25, green: 0.01, blue: 0.04)]),
                    startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
            }
        }
        let pelmet = h * 0.08
        var valance = Path(CGRect(x: 0, y: 0, width: w, height: pelmet))
        let scallop = w / 16
        for index in 0..<16 {
            valance.addEllipse(in: CGRect(x: Double(index) * scallop, y: pelmet - scallop * 0.35, width: scallop, height: scallop * 0.7))
        }
        context.fill(valance, with: .linearGradient(Gradient(colors: [Color(red: 0.35, green: 0.02, blue: 0.06), Color(red: 0.55, green: 0.05, blue: 0.12)]),
                                                    startPoint: .zero, endPoint: CGPoint(x: 0, y: pelmet)))
        context.fill(Path(CGRect(x: 0, y: pelmet - 4, width: w, height: 4)), with: .color(style.accent.opacity(0.8)))
        // Bulbs along the foot, every other one lit, chasing.
        let gap = 48.0
        let lit = Int(time * 3) % 2
        var index = 0
        for x in stride(from: gap / 2, to: w, by: gap) {
            let on = index % 2 == lit
            let bulb = CGRect(x: x - 7, y: h - 31, width: 14, height: 14)
            if on {
                context.fill(Circle().path(in: bulb.insetBy(dx: -8, dy: -8)),
                             with: .radialGradient(Gradient(colors: [style.accent.opacity(0.6), .clear]),
                                                   center: CGPoint(x: bulb.midX, y: bulb.midY), startRadius: 0, endRadius: 15))
            }
            context.fill(Circle().path(in: bulb), with: .color(on ? Color(red: 1, green: 0.95, blue: 0.7) : style.accent.opacity(0.25)))
            index += 1
        }
    }

    /// A four-pointed glint.
    static func sparkle(_ radius: Double) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: -radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
            path.addQuadCurve(to: CGPoint(x: 0, y: radius), control: .zero)
            path.addQuadCurve(to: CGPoint(x: -radius, y: 0), control: .zero)
            path.addQuadCurve(to: CGPoint(x: 0, y: -radius), control: .zero)
        }
    }
}
