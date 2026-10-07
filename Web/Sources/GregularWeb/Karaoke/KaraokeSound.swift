import GregularScreens
import JavaScriptKit

/// Karaoke's menu tunes and sound effects (`KaraokeMusic`), played by
/// `js/karaoke-sound.js` with the Web Audio API: no sound files.
@MainActor enum KaraokeSound {
    private static var sound: JSObject { JSObject.global.gregularKaraokeSound.object! }
    /// Each theme's tune, as the script takes it: made once, as effects ask on every move.
    private static var tunes: [KaraokeTheme: JSValue] = [:]
    private static var ladder = BlipLadder()

    /// `theme`'s tune, or quiet for nil (fading out, before a song).
    static func play(_ theme: KaraokeTheme?) {
        guard let theme else { return _ = sound.stop!() }
        _ = sound.play!(theme.rawValue, tune(theme))
    }

    /// How the tune sits: soft under a title card, full otherwise.
    static func setMood(_ mood: KaraokeMusic.Mood) {
        let gains = JSObject()
        for group in KaraokeMusic.Group.allCases where group != .effects {
            gains[group.rawValue] = .number(KaraokeMusic.gain(of: group, in: mood))
        }
        _ = sound.mood!(gains)
    }

    static func effect(_ effect: KaraokeMusic.Effect, in theme: KaraokeTheme) {
        // The highlight's blip climbs its scale as it runs down a list.
        let step = effect == .move ? ladder.step(at: JSObject.global.performance.object!.now!().number! / 1000) : 0
        _ = sound.effect!(theme.rawValue, tune(theme), notes(theme.music.notes(for: effect, step: step)))
    }

    private static func tune(_ theme: KaraokeTheme) -> JSValue {
        if let made = tunes[theme] { return made }
        let music = theme.music
        let tune = JSObject()
        let patches = JSObject()
        for (part, patch) in music.patches {
            let object = JSObject()
            let waves = JSObject.global.Array.function!.new()
            for wave in patch.waves { _ = waves.push!(wave.rawValue) }
            object["waves"] = waves.jsValue
            for (name, value) in [("detune", patch.detune), ("attack", patch.attack), ("decay", patch.decay), ("sustain", patch.sustain),
                                  ("release", patch.release), ("cutoff", patch.cutoff), ("sweep", patch.sweep),
                                  ("resonance", patch.resonance), ("fmRatio", patch.fmRatio), ("fmDepth", patch.fmDepth),
                                  ("vibrato", patch.vibrato), ("tremolo", patch.tremolo), ("pan", patch.pan), ("echo", patch.echo),
                                  ("reverb", patch.reverb), ("level", patch.level)] {
                object[name] = .number(value)
            }
            object["group"] = .string(patch.group.rawValue)
            patches[part.rawValue] = object.jsValue
        }
        tune["patches"] = patches.jsValue
        let kit = JSObject()
        kit["tune"] = .number(music.kit.tune)
        kit["decay"] = .number(music.kit.decay)
        kit["reverb"] = .number(music.kit.reverb)
        kit["level"] = .number(music.kit.level)
        tune["kit"] = kit.jsValue
        tune["echoTime"] = .number(music.echoTime)
        tune["echoFeedback"] = .number(music.echoFeedback)
        tune["reverbTime"] = .number(music.reverbTime)
        tune["intro"] = notes(music.intro)
        tune["introDuration"] = .number(music.introDuration)
        tune["loop"] = notes(music.loop)
        tune["duration"] = .number(music.duration)
        tunes[theme] = tune.jsValue
        return tune.jsValue
    }

    /// The notes as the script takes them.
    private static func notes(_ events: [KaraokeMusic.Event]) -> JSValue {
        let list = JSObject.global.Array.function!.new()
        for event in events {
            let note = JSObject()
            note["at"] = .number(event.at)
            note["length"] = .number(event.length)
            note["gain"] = .number(event.gain)
            note["pan"] = .number(event.pan)
            switch event.sound {
            case .note(let part, let midi):
                note["part"] = .string(part.rawValue)
                note["note"] = .number(Double(midi))
            case .drum(let drum):
                note["drum"] = .string(drum.rawValue)
            }
            _ = list.push!(note)
        }
        return list.jsValue
    }
}
