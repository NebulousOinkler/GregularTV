import GregularScreens
import JavaScriptKit

/// Karaoke's menu tunes and sound effects (`KaraokeMusic`), played by
/// `js/karaoke-sound.js` with the Web Audio API: no sound files.
@MainActor enum KaraokeSound {
    private static var sound: JSObject { JSObject.global.gregularKaraokeSound.object! }

    /// `theme`'s tune, or quiet for nil (fading out, before a song).
    static func play(_ theme: KaraokeTheme?) {
        guard let theme else { return _ = sound.stop!() }
        let music = theme.music
        _ = sound.play!(theme.rawValue, music.duration, notes(music.loop))
    }

    static func effect(_ effect: KaraokeMusic.Effect, in theme: KaraokeTheme) {
        _ = sound.effect!(notes(theme.music.notes(for: effect)))
    }

    /// The notes as the script takes them.
    private static func notes(_ events: [KaraokeMusic.Event]) -> JSValue {
        let list = JSObject.global.Array.function!.new()
        for event in events {
            let note = JSObject()
            note["at"] = .number(event.at)
            note["length"] = .number(event.length)
            note["gain"] = .number(event.gain)
            switch event.sound {
            case .tone(let wave, let midi):
                note["wave"] = .string(wave.rawValue)
                note["note"] = .number(Double(midi))
            case .kick: note["drum"] = "kick"
            case .hat: note["drum"] = "hat"
            }
            _ = list.push!(note)
        }
        return list.jsValue
    }
}
