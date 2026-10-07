import Foundation

/// A theme's menu tune and sound effects, as notes and instruments: each
/// front end plays them on a synthesizer of its own (the Web Audio API in a
/// browser, AVAudioEngine on Apple TV), so nothing is a sound file and the
/// tunes are written once, here.
///
/// - **Instruments** (`Patch`): layered oscillators, slightly detuned, through
///   a low-pass filter that can sweep down as each note starts; an
///   attack-decay-sustain-release envelope; optional FM (bells, electric
///   piano), vibrato and tremolo; a place in the stereo field; and how much
///   goes to the echo and the reverb. Drums (`Drum`) are made from noise and
///   falling tones, coloured by the theme's `Kit`.
/// - **Tunes**: a short `intro` (a drum pickup), then `loop` round and round:
///   sixteen bars or so, in sections, so it doesn't sound like a loop.
/// - **Mixing**: every sound belongs to a `Group`; `Mood.waiting` (a title
///   card waiting for Play) turns the drums and lead down under the chords.
public struct KaraokeMusic: Sendable, Equatable {
    public enum Wave: String, Sendable, CaseIterable {
        case sine, square, sawtooth, triangle
    }

    /// The instruments a tune or effect plays.
    public enum Part: String, Sendable, CaseIterable {
        case bass, pad, keys, lead, arp, bell
        /// The effects' instruments.
        case blip, fanfare
    }

    /// Sounds mixed together: the mood turns each up or down.
    public enum Group: String, Sendable, CaseIterable {
        case drums, bass, pad, lead, effects
    }

    public enum Drum: String, Sendable, CaseIterable {
        case kick, snare, clap, hat, openHat, shaker, crash, brush, tomHigh, tomLow, rim
    }

    /// How the tune sits: everything (menus, the attract screen), or soft
    /// under a title card waiting for Play.
    public enum Mood: String, Sendable {
        case full, waiting
    }

    /// An instrument.
    public struct Patch: Sendable, Equatable {
        /// Oscillators layered for each note.
        public var waves: [Wave]
        /// How far apart the layers are tuned, in cents (spread evenly round the note).
        public var detune: Double = 0
        public var attack: Double = 0.005
        public var decay: Double = 0.2
        /// The level held after the decay (0 to 1) while the note lasts.
        public var sustain: Double = 0.5
        public var release: Double = 0.1
        /// The filter's cutoff, in hertz.
        public var cutoff: Double = 8000
        /// Hertz added to the cutoff as a note starts, falling away over `decay`.
        public var sweep: Double = 0
        /// The filter's resonance (Q).
        public var resonance: Double = 0.7
        /// FM: a sine at this multiple of the note bends the first wave (0: none).
        public var fmRatio: Double = 0
        /// FM's strength as the note starts (the modulation index), falling away over `decay`.
        public var fmDepth: Double = 0
        /// Pitch wobble, in cents, five and a half times a second.
        public var vibrato: Double = 0
        /// Volume wobble (0 to 1), five times a second.
        public var tremolo: Double = 0
        /// Left (-1) to right (1).
        public var pan: Double = 0
        /// How much goes to the echo and the reverb (0 to 1).
        public var echo: Double = 0
        public var reverb: Double = 0
        /// Its loudness (0 to 1), times each note's.
        public var level: Double = 0.2
        public var group: Group
    }

    /// The drums' character.
    public struct Kit: Sendable, Equatable {
        /// Multiplies the drums' pitches and filters: higher is brighter.
        public var tune: Double = 1
        /// Multiplies how long they ring.
        public var decay: Double = 1
        /// How much of the snare, clap and toms goes to the reverb.
        public var reverb: Double = 0.15
        public var level: Double = 1
    }

    public enum Sound: Sendable, Hashable {
        /// A part playing a MIDI note.
        case note(Part, Int)
        case drum(Drum)
    }

    /// One sound: when it starts (seconds from the start of the loop, intro
    /// or effect), how long it's held (a drum just rings), how loud (0 to 1),
    /// and where, added to its instrument's place (-1 to 1).
    public struct Event: Sendable, Equatable {
        public let at: Double
        public let sound: Sound
        public let length: Double
        public let gain: Double
        public let pan: Double

        public init(at: Double, sound: Sound, length: Double, gain: Double, pan: Double = 0) {
            self.at = at
            self.sound = sound
            self.length = length
            self.gain = gain
            self.pan = pan
        }
    }

    /// The things that make a sound effect.
    public enum Effect: String, Sendable, CaseIterable {
        /// The highlight moved (`notes(for:step:)` climbs a scale with `step`).
        case move
        /// Something chosen.
        case choose
        /// A step back.
        case back
        /// A song queued: ta-da.
        case queue
        /// A theme chosen: a little jingle.
        case theme
        /// Play pressed on a title card: a drum roll into the song.
        case start
        /// A song sung to its end: applause and a fanfare.
        case encore
    }

    /// Beats a minute.
    public let tempo: Double
    /// The key's root, as a MIDI note.
    public let root: Int
    public let patches: [Part: Patch]
    public let kit: Kit
    /// The echo's delay, and how much of each echo comes round again (0 to 1).
    public let echoTime: Double
    public let echoFeedback: Double
    /// How long the reverb rings, in seconds.
    public let reverbTime: Double
    /// The intro's notes, played once before the loop, and how long it is.
    public let intro: [Event]
    public let introDuration: Double
    /// Every note in one time round the loop, by when it starts.
    public let loop: [Event]
    /// How long the loop is, in seconds.
    public let duration: Double
    /// The notes the highlight's blip climbs through, from `root` an octave up.
    let blipScale: [Int]
    /// The fanfare's notes, from `root` an octave up.
    let fanfare: [Int]

    /// How long a step is: a sixteenth note.
    public var step: Double { 60 / tempo / 4 }

    /// How loud a group is in a mood (0 to 1).
    public static func gain(of group: Group, in mood: Mood) -> Double {
        switch (mood, group) {
        case (.full, _), (.waiting, .effects), (.waiting, .pad): 1
        case (.waiting, .bass): 0.6
        case (.waiting, .drums): 0.3
        case (.waiting, .lead): 0.2
        }
    }

    /// Which group a sound is mixed in.
    public func group(of sound: Sound) -> Group {
        switch sound {
        case .drum: .drums
        case .note(let part, _): patches[part]?.group ?? .effects
        }
    }

    /// A sound effect's notes. `step` (for `.move`) is how many moves in a
    /// row: the blip climbs the scale as the highlight runs down a list.
    public func notes(for effect: Effect, step: Int = 0) -> [Event] {
        let base = root + 12
        switch effect {
        case .move:
            let note = blipScale[min(max(step, 0), blipScale.count - 1)]
            return [Event(at: 0, sound: .note(.blip, base + note), length: 0.05, gain: 0.5)]
        case .choose:
            return [blipScale[2], blipScale[4], blipScale[7]].enumerated().map {
                Event(at: Double($0) * 0.055, sound: .note(.blip, base + $1), length: 0.08, gain: 0.6)
            }
        case .back:
            return [blipScale[4], blipScale[0]].enumerated().map {
                Event(at: Double($0) * 0.07, sound: .note(.blip, base + $1 - 12), length: 0.08, gain: 0.55)
            }
        case .queue:
            return fanfare.enumerated().map {
                Event(at: Double($0) * 0.07, sound: .note(.fanfare, base + $1), length: 0.22, gain: 0.7)
            } + [Event(at: 0, sound: .drum(.clap), length: 0.2, gain: 0.5)]
        case .theme:
            let beat = 60 / tempo
            return [
                Event(at: 0, sound: .drum(.kick), length: 0.3, gain: 0.8),
                Event(at: 0, sound: .drum(.crash), length: 1.2, gain: 0.5),
            ] + fanfare.prefix(4).enumerated().map {
                Event(at: Double($0) * beat / 4, sound: .note(.fanfare, base + $1), length: beat / 4, gain: 0.6)
            } + [Event(at: beat, sound: .note(.fanfare, base + fanfare.last!), length: beat, gain: 0.7)]
        case .start:
            // A snare roll swelling over a second, a tom run, and a crash.
            var events = (0..<14).map { hit in
                Event(at: Double(hit) * 0.06, sound: .drum(.snare), length: 0.1, gain: 0.25 + 0.5 * Double(hit) / 13)
            }
            events += [Event(at: 0.84, sound: .drum(.tomHigh), length: 0.2, gain: 0.7),
                       Event(at: 0.92, sound: .drum(.tomLow), length: 0.25, gain: 0.8),
                       Event(at: 1.0, sound: .drum(.kick), length: 0.3, gain: 0.9),
                       Event(at: 1.0, sound: .drum(.crash), length: 1.5, gain: 0.6)]
            return events
        case .encore:
            // A crowd's claps, thick at first and thinning out, under a fanfare.
            var random = Scatter(seed: 7)
            var events: [Event] = []
            for _ in 0..<90 {
                let at = 2.8 * pow(random.next(), 1.6)
                events.append(Event(at: at, sound: .drum(.clap), length: 0.15,
                                    gain: (0.15 + 0.2 * random.next()) * (1 - at / 3.2), pan: random.next() * 1.6 - 0.8))
            }
            events += fanfare.enumerated().map {
                Event(at: 0.1 + Double($0) * 0.09, sound: .note(.fanfare, base + $1), length: 0.3, gain: 0.6)
            }
            events.append(Event(at: 0.1, sound: .drum(.crash), length: 1.5, gain: 0.45))
            return events.sorted { $0.at < $1.at }
        }
    }
}

// MARK: - Writing tunes

/// A tune as it's written: bars, each a chord and what each part and drum
/// plays over its sixteen steps.
///
/// A part's line is sixteen tokens, one a step, separated by spaces: a
/// number starts a note, "-" holds the one before, "." rests, and "x"
/// plays the bar's chord. What a number means depends on the part:
/// - bass: semitones above the chord's first note, an octave below `root`;
/// - arp: which of the chord's notes (past the last, an octave up);
/// - lead: semitones above `root`, an octave up (bell: two octaves up).
///
/// A drum's line is sixteen characters: "X" a loud hit, "x" a hit, "o" a
/// soft one, anything else a rest.
struct Score {
    struct Bar {
        /// Semitones above the root.
        var chord: [Int]
        var parts: [KaraokeMusic.Part: String] = [:]
        var drums: [KaraokeMusic.Drum: String] = [:]
    }

    var tempo: Double
    var root: Int
    /// How late each off-beat comes, as a share of the swung note.
    var swing: Double = 0
    /// What's swung: sixteenths (1) or eighths (2).
    var swingSteps = 1

    var step: Double { 60 / tempo / 4 }

    static let drumGains: [KaraokeMusic.Drum: Double] = [
        .kick: 0.9, .snare: 0.6, .clap: 0.55, .hat: 0.22, .openHat: 0.2, .shaker: 0.16,
        .crash: 0.35, .brush: 0.35, .tomHigh: 0.5, .tomLow: 0.55, .rim: 0.35,
    ]
    static let drumPans: [KaraokeMusic.Drum: Double] = [
        .hat: 0.3, .openHat: 0.3, .shaker: -0.35, .crash: -0.2, .tomHigh: 0.25, .tomLow: -0.25, .rim: 0.15, .brush: 0.1,
    ]

    /// When step `index` of bar `bar` starts, swung.
    func time(bar: Int, step index: Int) -> Double {
        let offbeat = swing > 0 && index % (2 * swingSteps) == swingSteps
        return (Double(bar * 16 + index) + (offbeat ? swing * Double(swingSteps) : 0)) * step
    }

    /// Every sound in `bars`, by when it starts.
    func events(_ bars: [Bar]) -> [KaraokeMusic.Event] {
        var events: [KaraokeMusic.Event] = []
        for (number, bar) in bars.enumerated() {
            for (part, line) in bar.parts {
                for note in Self.notes(in: line) {
                    let at = time(bar: number, step: note.step)
                    let length = Double(note.steps) * step
                    for pitch in pitches(note.value, part: part, chord: bar.chord) {
                        events.append(KaraokeMusic.Event(at: at, sound: .note(part, pitch), length: length, gain: 1))
                    }
                }
            }
            for (drum, line) in bar.drums {
                for (index, character) in line.filter({ $0 != " " }).prefix(16).enumerated() {
                    let accent: Double = switch character {
                    case "X": 1
                    case "x": 0.75
                    case "o": 0.4
                    default: 0
                    }
                    guard accent > 0 else { continue }
                    // A little life in the hats: no two in a row quite the same.
                    let lilt = drum == .hat || drum == .shaker ? 0.85 + 0.15 * Double((index * 7) % 5) / 4 : 1
                    events.append(KaraokeMusic.Event(at: time(bar: number, step: index), sound: .drum(drum), length: step,
                                                      gain: Self.drumGains[drum]! * accent * lilt, pan: Self.drumPans[drum] ?? 0))
                }
            }
        }
        return events.sorted { $0.at < $1.at }
    }

    /// The notes a token plays, as MIDI notes.
    private func pitches(_ value: Int?, part: KaraokeMusic.Part, chord: [Int]) -> [Int] {
        guard let value else {
            // "x": the chord.
            return chord.map { root + 12 + $0 }
        }
        switch part {
        case .bass: return [root - 12 + chord[0] + value]
        case .arp: return [root + 12 + chord[value % chord.count] + 12 * (value / chord.count)]
        case .bell: return [root + 24 + value]
        case .lead, .pad, .keys, .blip, .fanfare: return [root + 12 + value]
        }
    }

    /// The notes in a part's line: the step each starts on, how many steps
    /// it lasts, and its number (nil for "x").
    static func notes(in line: String) -> [(step: Int, steps: Int, value: Int?)] {
        var notes: [(step: Int, steps: Int, value: Int?)] = []
        for (index, token) in line.split(separator: " ").prefix(16).enumerated() {
            switch token {
            case "-":
                if !notes.isEmpty, notes[notes.count - 1].step + notes[notes.count - 1].steps == index {
                    notes[notes.count - 1].steps += 1
                }
            case ".":
                continue
            case "x":
                notes.append((index, 1, nil))
            default:
                if let value = Int(token) { notes.append((index, 1, value)) }
            }
        }
        return notes
    }

    /// The same bar for each chord.
    static func bars(_ chords: [[Int]], _ make: (Int, [Int]) -> Bar) -> [Bar] {
        chords.enumerated().map { make($0, $1) }
    }
}

/// Numbers that look random, the same every time: for a crowd's applause.
struct Scatter {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
    }

    /// The next, from 0 up to 1.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
}

/// How far up its scale the highlight's blip goes: a step for each move
/// soon after the last, back to the bottom after a pause.
public struct BlipLadder: Sendable {
    private var last = -Double.infinity
    private var rung = 0
    /// A pause this long starts again at the bottom.
    static let pause = 0.6

    public init() {}

    /// The step for a move at `time` (seconds, on any steady clock).
    public mutating func step(at time: Double) -> Int {
        rung = time - last < Self.pause ? min(rung + 1, 7) : 0
        last = time
        return rung
    }
}
