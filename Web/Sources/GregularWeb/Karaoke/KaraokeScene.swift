import GregularScreens

/// A theme's moving backdrop in a browser, as plain elements karaoke.css
/// draws and moves: a mirror ball over a lit dance floor, a sunset over a
/// neon grid, bubbles and candy, or velvet curtains and marquee bulbs. Every
/// theme's layers are here; the nearest `data-theme` shows its own, so a
/// theme box's miniature and the page can differ. It throbs with
/// `--k-pulse` (0 to 1) on the page, from the lyrics' timings.
@MainActor enum KaraokeScene {
    static func element() -> El {
        // Spread about, the same every time, as on Apple TV (`KaraokeBackdrop.spot`).
        func place(_ index: Int) -> String {
            "--i: \(index); --x: \((index * 37) % 100)%; --y: \((index * 61 + 13) % 100)%"
        }
        func spans(_ count: Int, _ classes: String = "") -> [El] {
            (0..<count).map { El("span", classes).styled(place($0)) }
        }
        return El("div", "k-scene", [
            El("div", "k-disco", [
                El("span", "k-floor"),
                El("div", "k-beams", spans(6)),
                El("div", "k-glints", spans(14)),
                El("span", "k-mirror"),
            ]),
            El("div", "k-synth", [
                El("div", "k-stars", spans(16)),
                El("span", "k-sun"),
                El("span", "k-grid"),
                El("span", "k-scan"),
            ]),
            El("div", "k-pop", [
                El("span", "k-stripes"),
                El("div", "k-shapes", (0..<8).map { El("span", $0.isMultiple(of: 2) ? "k-heart" : "k-star").styled(place($0 * 11 + 4)) }),
                El("div", "k-bubbles", spans(14)),
            ]),
            El("div", "k-lounge", [
                El("div", "k-spots", spans(2)),
                El("div", "k-sparkles", spans(8)),
                El("span", "k-curtain k-curtain-left"),
                El("span", "k-curtain k-curtain-right"),
                El("span", "k-pelmet"),
                El("span", "k-footlights"),
            ]),
        ]).attribute("aria-hidden", "true")
    }
}
