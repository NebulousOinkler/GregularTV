import Foundation
import GregularScreens
import JavaScriptKit

/// The last 15 seconds of a commercial break: the channel's own card, like
/// a TV station's "You're watching…" ident, as on Apple TV. The wordmark
/// springs in on the brand gradient, its colour bars hop to the music's
/// beat, and what's up next fades in below. The animation is CSS
/// (`app.css`, `.station-card`), started partway in when the card is joined
/// late, and the music (`station-card.m4a`) starts from the same point, so
/// its last chord always lands as the programme starts. `WatchModel`
/// decides when the card is up and what it says.
@MainActor final class StationCard {
    /// The music's length, the card's time.
    static let length = WatchModel.stationCardTime
    /// How loud, under a programme's usual level.
    static let level = 0.35

    let content: StationCardContent
    let element: El
    private let music = El("audio")

    init(content: StationCardContent) {
        self.content = content
        let next = El("div", "next", [El("p", "heading", text: content.heading)])
        if let title = content.title { next.append(El("p", "title", text: title)) }
        next.append(El("p", "when", text: content.when))
        element = El("div", "station-card", [
            El("div", "station-dots", (0..<14).map { El("span", "dot dot-\($0)") }),
            El("p", "intro", text: content.intro.uppercased()),
            El("p", "station-wordmark", text: "Gregular TV"),
            Parts.colourBars("bars hopping"),
            El("p", "station-channel", text: content.channel),
            next,
        ])
        // Joined late: start the animation as far in as the card is.
        let elapsed = Self.length - content.endsAt.timeIntervalSinceNow
        element.style("--elapsed", "\(max(0, elapsed))s")
        play(from: elapsed)
    }

    /// Plays the music from `offset` seconds in. Nearly over already: stays
    /// quiet rather than blip.
    private func play(from offset: TimeInterval) {
        guard offset < Self.length - 1 else { return }
        music.attribute("src", "station-card.m4a")
        music.object.volume = .number(Self.level)
        music.object.muted = .boolean(SoundUnlock.isMuted)
        music.on("loadedmetadata") { [music] _ in music.object.currentTime = .number(max(0, offset)) }
        _ = music.object.play!().object?.catch!(JSOneshotClosure { _ in .undefined })
    }

    /// The card has gone (or the channel changed): the music fades out.
    func close() {
        let music = music
        let steps = 6
        for step in 1...steps {
            _ = JSObject.global.setTimeout!(JSOneshotClosure { _ in
                music.object.volume = .number(Self.level * Double(steps - step) / Double(steps))
                if step == steps { _ = music.object.pause!() }
                return .undefined
            }, step * 50)
        }
    }
}
