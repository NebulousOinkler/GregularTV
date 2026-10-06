import Foundation

/// A theme's menu tune and sound effects, as notes: each front end plays
/// them on a synthesizer of its own (the Web Audio API in a browser,
/// AVAudioEngine on Apple TV), so nothing is a sound file and the tunes are
/// written once, here.
///
/// A tune is a loop of `bars` (one chord each) of sixteen steps: a bass line,
/// an arpeggio over the chord, and a beat. `loop` turns it into timed notes.
public struct KaraokeMusic: Sendable, Equatable {
    public enum Wave: String, Sendable {
        case sine, square, sawtooth, triangle
    }

    /// What makes a note's sound.
    public enum Sound: Sendable, Equatable {
        case tone(Wave, note: Int)
        /// A falling thump.
        case kick
        /// A tick of noise.
        case hat
    }

    /// One note: when it starts (seconds from the loop's or effect's start),
    /// how long it rings, and how loud (0 to 1).
    public struct Event: Sendable, Equatable {
        public let at: Double
        public let sound: Sound
        public let length: Double
        public let gain: Double
    }

    /// The things that make a sound effect.
    public enum Effect: String, Sendable, CaseIterable {
        /// The highlight moved.
        case move
        /// Something chosen.
        case choose
        /// A step back.
        case back
        /// A song queued: ta-da.
        case queue
    }

    /// Beats a minute.
    let tempo: Double
    /// The key's root, as a MIDI note.
    let root: Int
    let lead: Wave
    let bass: Wave
    let leadGain: Double
    /// How late each off-beat step comes, as a share of a step.
    let swing: Double
    /// Each bar's chord, in semitones from the root.
    let chords: [[Int]]
    /// Sixteen steps of bass, in semitones over the chord's first note (nil: rest).
    let bassSteps: [Int?]
    /// Sixteen steps of arpeggio: which note of the chord (nil: rest).
    let arpeggio: [Int?]
    let kick: [Bool]
    let hat: [Bool]
    let blip: Wave
    let blipNotes: [Int]
    let fanfare: [Int]

    /// How long a step is: a sixteenth note.
    var step: Double { 60 / tempo / 4 }

    /// How long the loop is, in seconds.
    public var duration: Double { Double(chords.count * 16) * step }

    /// Every note in one time round the loop.
    public var loop: [Event] {
        var events: [Event] = []
        for bar in chords.indices {
            let chord = chords[bar]
            for index in 0..<16 {
                let at = Double(bar * 16 + index) * step + (index % 2 == 1 ? swing * step : 0)
                if let bass = bassSteps[index] {
                    events.append(Event(at: at, sound: .tone(self.bass, note: root - 12 + chord[0] + bass), length: step * 1.8, gain: 0.09))
                }
                if let note = arpeggio[index] {
                    events.append(Event(at: at, sound: .tone(lead, note: root + 12 + chord[note % chord.count]),
                                        length: step * 1.5, gain: leadGain))
                }
                if kick[index] { events.append(Event(at: at, sound: .kick, length: 0.2, gain: 0.35)) }
                if hat[index] { events.append(Event(at: at, sound: .hat, length: 0.05, gain: 0.05)) }
            }
        }
        return events
    }

    /// A sound effect's notes.
    public func notes(for effect: Effect) -> [Event] {
        let base = root + 12
        switch effect {
        case .move:
            return [Event(at: 0, sound: .tone(blip, note: base + blipNotes[0]), length: 0.06, gain: 0.05)]
        case .choose:
            return blipNotes.enumerated().map { Event(at: Double($0) * 0.06, sound: .tone(blip, note: base + $1), length: 0.12, gain: 0.07) }
        case .back:
            return blipNotes.reversed().enumerated().map {
                Event(at: Double($0) * 0.06, sound: .tone(blip, note: base + $1 - 5), length: 0.1, gain: 0.06)
            }
        case .queue:
            return fanfare.enumerated().map { Event(at: Double($0) * 0.07, sound: .tone(lead, note: base + $1), length: 0.3, gain: 0.07) }
        }
    }
}

extension KaraokeTheme {
    /// Its menu tune and sound effects.
    public var music: KaraokeMusic {
        switch self {
        case .neonDisco:
            // Four on the floor, octave-jumping bass, a bright saw arpeggio.
            KaraokeMusic(tempo: 120, root: 45, lead: .sawtooth, bass: .square, leadGain: 0.05, swing: 0,
                         chords: [[0, 3, 7, 10], [5, 8, 12, 15], [3, 7, 10, 14], [-2, 2, 5, 9]],
                         bassSteps: [0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12, 0, 12],
                         arpeggio: [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 3],
                         kick: Self.steps("x---x---x---x---"), hat: Self.steps("--x---x---x---x-"),
                         blip: .square, blipNotes: [12, 19], fanfare: [0, 7, 12, 16, 19, 24])
        case .karaokeBar:
            // Big square-wave synth pop, half-time drums, a long arpeggio.
            KaraokeMusic(tempo: 108, root: 48, lead: .square, bass: .sawtooth, leadGain: 0.04, swing: 0,
                         chords: [[0, 4, 7, 11], [9, 12, 16, 19], [5, 9, 12, 16], [7, 11, 14, 17]],
                         bassSteps: [0, nil, 0, nil, 0, nil, 0, 7, 0, nil, 0, nil, 0, nil, 12, 7],
                         arpeggio: [0, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1, 0, 3, 2, 1, 0],
                         kick: Self.steps("x-------x-x-----"), hat: Self.steps("--x---x---x---xx"),
                         blip: .square, blipNotes: [7, 12], fanfare: [0, 4, 7, 12, 7, 12, 16])
        case .bubblegumPop:
            // Bouncy triangle-wave pop in a major key, skipping rhythm.
            KaraokeMusic(tempo: 132, root: 53, lead: .triangle, bass: .triangle, leadGain: 0.09, swing: 0,
                         chords: [[0, 4, 7, 12], [7, 11, 14, 19], [9, 12, 16, 21], [5, 9, 12, 17]],
                         bassSteps: [0, nil, nil, 0, nil, nil, 7, nil, 0, nil, nil, 0, nil, 7, nil, nil],
                         arpeggio: [0, 2, 1, 3, 0, 2, 1, 3, 2, 3, 1, 2, 0, 1, 2, 3],
                         kick: Self.steps("x--x--x-x--x--x-"), hat: Self.steps("-x--x--x-x--x--x"),
                         blip: .triangle, blipNotes: [19, 24], fanfare: [0, 4, 7, 12, 16, 19, 24, 28])
        case .vegasLounge:
            // Slow lounge swing: sine-wave sevenths, walking bass, brushed hats.
            KaraokeMusic(tempo: 84, root: 43, lead: .sine, bass: .sine, leadGain: 0.08, swing: 0.18,
                         chords: [[0, 4, 7, 11, 14], [5, 9, 12, 16], [2, 5, 9, 12], [7, 11, 14, 17]],
                         bassSteps: [0, nil, nil, nil, 4, nil, nil, nil, 7, nil, nil, nil, 9, nil, nil, nil],
                         arpeggio: [0, nil, 2, nil, 1, nil, 3, nil, 2, nil, 4, nil, 3, nil, 1, nil],
                         kick: Self.steps("x-------x-------"), hat: Self.steps("----x--x----x--x"),
                         blip: .sine, blipNotes: [12, 16], fanfare: [0, 4, 7, 11, 14, 19])
        }
    }

    /// Sixteen steps, "x" for a hit.
    private static func steps(_ pattern: String) -> [Bool] {
        pattern.map { $0 == "x" }
    }
}
