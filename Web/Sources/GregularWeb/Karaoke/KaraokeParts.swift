import Foundation
import GregularScreens
import JavaScriptKit

/// Karaoke's decorations in a browser, each drawn by karaoke.css in the
/// theme on the page (`data-theme`): headings in the theme's lettering, song
/// pictures, the loading animation and confetti.
@MainActor enum KaraokeParts {
    /// A heading in the theme's lettering. Each letter is its own span, for
    /// bubblegum's bounce; `framed` puts Vegas's bulbs round it.
    static func title(_ text: String, _ tag: String = "h1", framed: Bool = false) -> El {
        // Named as a whole: read letter by letter, the spans would spell it out.
        let title = El(tag, "k-title" + (framed ? " k-framed" : "")).attribute("aria-label", text)
        for (index, letter) in text.enumerated() {
            title.append(El("span", "k-letter", text: String(letter)).styled("--i: \(index)").attribute("aria-hidden", "true"))
        }
        return title
    }

    /// A song's, album's or artist's picture (`KaraokeCover`): a pattern in two
    /// of the theme's cover colours with its initials; round for an artist.
    static func cover(_ cover: KaraokeCover, round: Bool = false, size: String = "") -> El {
        El("span", "k-cover" + (round ? " k-cover-round" : "") + (size.isEmpty ? "" : " k-cover-\(size)"), [
            El("span", "k-cover-initials", text: cover.initials),
        ])
        .attribute("data-pattern", cover.pattern.rawValue)
        .styled("--back: var(--k-cover-\(cover.back)); --front: var(--k-cover-\(cover.front)); --angle: \(cover.angle)deg")
        .attribute("aria-hidden", "true")
    }

    /// A row's little label ("Video", "No lyrics").
    static func badge(_ text: String, quiet: Bool = false) -> El {
        El("span", "k-badge" + (quiet ? " k-badge-quiet" : ""), text: text)
    }

    /// "Get ready!"'s animation: twelve pieces the theme arranges its own way.
    static func loader() -> El {
        El("div", "k-loader", (0..<12).map { El("span").styled("--i: \($0)") })
            .attribute("role", "progressbar").attribute("aria-label", KaraokeText.getReady)
    }

    /// Confetti bursting from `x`, `y` (shares of the page's width and
    /// height), cleared away once it's fallen.
    static func confetti(into page: El, x: Double, y: Double, pieces: Int) {
        guard !reducedMotion else { return }
        let burst = El("div", "k-confetti").attribute("aria-hidden", "true")
        burst.styled("left: \(x * 100)%; top: \(y * 100)%")
        for piece in 0..<pieces {
            let angle = -Double.pi / 2 + (Double((piece * 7919) % 1000) / 1000 - 0.5) * 2.4
            let speed = 35 + Double((piece * 104_729) % 40)
            let style = "--dx: \(cos(angle) * speed)vmin; --dy: \(sin(angle) * speed)vmin; --spin: \((piece * 37) % 720 - 360)deg; "
                + "--delay: \(Double(piece % 7) * 0.02)s; background: var(--k-cover-\(piece % KaraokeCover.colourCount))"
            burst.append(El("span").styled(style))
        }
        page.append(burst)
        Task {
            try? await Task.sleep(for: .seconds(3.2))
            burst.remove()
        }
    }

    /// The reader asked for less motion.
    static var reducedMotion: Bool {
        JSObject.global.matchMedia!("(prefers-reduced-motion: reduce)").object?.matches.boolean ?? false
    }
}
