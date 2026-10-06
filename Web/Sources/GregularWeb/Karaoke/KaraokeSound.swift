import GregularScreens
import JavaScriptKit

/// Karaoke's menu tunes and sound effects, synthesized as they play
/// (`js/karaoke-sound.js`): no sound files.
@MainActor enum KaraokeSound {
    enum Effect: String {
        /// The highlight moved.
        case move
        /// Something chosen.
        case choose
        /// A step back.
        case back
        /// A song queued: ta-da.
        case queue
    }

    private static var sound: JSObject { JSObject.global.gregularKaraokeSound.object! }

    /// `theme`'s tune, or quiet for nil (fading out, before a song).
    static func play(_ theme: KaraokeTheme?) {
        if let theme { _ = sound.play!(theme.rawValue) } else { _ = sound.stop!() }
    }

    static func effect(_ effect: Effect, in theme: KaraokeTheme) {
        _ = sound.effect!(effect.rawValue, theme.rawValue)
    }
}
