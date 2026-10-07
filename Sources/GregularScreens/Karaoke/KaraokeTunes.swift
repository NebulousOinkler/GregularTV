/// Each theme's menu tune, instruments and effects (`KaraokeMusic`), written
/// as scores (`Score`'s notation). Each loop is four sections of four bars:
/// a groove, a verse with the tune, a chorus, and a breakdown that fills
/// back round to the top, so it's half a minute or more before it repeats.
extension KaraokeTheme {
    /// Its menu tune and sound effects.
    public var music: KaraokeMusic {
        KaraokeTunes.byTheme[self]!
    }
}

enum KaraokeTunes {
    /// Written once: effects ask for a theme's music on every move.
    static let byTheme = Dictionary(uniqueKeysWithValues: KaraokeTheme.allCases.map { ($0, written(for: $0)) })

    static func written(for theme: KaraokeTheme) -> KaraokeMusic {
        switch theme {
        case .neonDisco: neonDisco
        case .karaokeBar: karaokeBar
        case .bubblegumPop: bubblegumPop
        case .vegasLounge: vegasLounge
        }
    }

    typealias Part = KaraokeMusic.Part
    typealias Drum = KaraokeMusic.Drum
    typealias Patch = KaraokeMusic.Patch

    static let wholeBar = "x - - - - - - - - - - - - - - -"
    static let rest = ". . . . . . . . . . . . . . . ."

    /// Bars for `chords`, each with `parts` (one line for every bar, or one
    /// line a bar) and `drums`; the last bar's drums can differ (a fill).
    static func section(_ chords: [[Int]], parts: [Part: [String]], drums: [Drum: String],
                        fill: [Drum: String] = [:], first: [Drum: String] = [:]) -> [Score.Bar] {
        Score.bars(chords) { index, chord in
            var bar = Score.Bar(chord: chord)
            for (part, lines) in parts {
                bar.parts[part] = lines.count == 1 ? lines[0] : lines[index % lines.count]
            }
            bar.drums = drums
            if index == 0 { bar.drums.merge(first) { $1 } }
            if index == chords.count - 1 { bar.drums.merge(fill) { $1 } }
            return bar
        }
    }

    static func music(_ score: Score, intro: [Score.Bar], loop: [Score.Bar], patches: [Part: Patch], kit: KaraokeMusic.Kit,
                      echoSteps: Double, echoFeedback: Double, reverbTime: Double, blipScale: [Int], fanfare: [Int]) -> KaraokeMusic {
        KaraokeMusic(tempo: score.tempo, root: score.root, patches: patches, kit: kit, echoTime: echoSteps * score.step,
                     echoFeedback: echoFeedback, reverbTime: reverbTime, intro: score.events(intro),
                     introDuration: Double(intro.count * 16) * score.step, loop: score.events(loop),
                     duration: Double(loop.count * 16) * score.step, blipScale: blipScale, fanfare: fanfare)
    }

    static let crash: [Drum: String] = [.crash: "X..............."]

    // MARK: - Neon Disco

    /// Nu-disco in A minor: octave-jumping bass, four on the floor with
    /// claps and open hats, string stabs and a filtered saw arpeggio.
    static var neonDisco: KaraokeMusic {
        let score = Score(tempo: 118, root: 45)
        let verse = [[0, 3, 7, 10], [5, 8, 12, 15], [3, 7, 10, 14], [-2, 2, 5, 9]]
        let chorus = [[8, 12, 15, 19], [10, 14, 17, 21], [7, 10, 14, 17], [0, 3, 7, 12]]
        let octaves = "0 - 12 - 0 - 12 - 0 - 12 - 0 - 12 -"
        let arp = "0 1 2 3 2 1 2 3 0 1 2 3 2 1 2 3"
        let floor: [Drum: String] = [.kick: "X...x...X...x...", .clap: "....X.......X...", .openHat: "..x...x...x...x.",
                                     .shaker: "oxoooxoooxoooxoo"]
        let groove = section(verse, parts: [.bass: [octaves], .arp: [arp], .pad: [wholeBar]], drums: floor, first: crash)
        let tune = section(verse, parts: [
            .bass: [octaves], .pad: [wholeBar], .keys: [". . x . . . . . . . x . . . . ."],
            .lead: [". . 12 - 12 - 10 - 12 - - - 15 - 14 -", "12 - - - 10 - 8 - 10 - - - . . . .",
                    ". . 7 - 10 - 12 - 14 - - - 12 - 10 -", "10 - - - - - - - 7 - 9 - 10 - 12 -"],
        ], drums: floor, fill: [.clap: "....X.......X.xx"])
        let hook = section(chorus, parts: [
            .bass: [octaves], .pad: [wholeBar], .keys: ["x . . x . . x . . . x . . x . ."],
            .lead: ["15 - 15 - 17 - 15 - 12 - - - 12 - 15 -", "17 - - - 14 - 17 - 19 - - - 17 - 14 -",
                    "14 - 12 - 10 - 7 - 10 - - - 12 - 14 -", "12 - - - - - - - - - - - . . . ."],
        ], drums: floor.merging([.hat: "o.o.o.o.o.o.o.o."]) { $1 }, first: crash)
        let breakdown = section(verse, parts: [.bass: ["0 - - - . . . . 0 - - - . . . ."], .arp: [arp], .pad: [wholeBar]],
                                drums: [.shaker: "oxoooxoooxoooxoo", .clap: "....x.......x..."],
                                fill: [.snare: "........x.x.xxXX", .tomHigh: "............x...", .tomLow: "..............x.",
                                       .kick: "X.......X......."])
        let intro = [Score.Bar(chord: verse[0], drums: [.kick: "X...x...X...x...", .snare: "........x.x.xxXX"])]
        return music(score, intro: intro, loop: groove + tune + hook + breakdown, patches: [
            .bass: Patch(waves: [.sawtooth, .square], detune: 6, decay: 0.18, sustain: 0.35, release: 0.08, cutoff: 380, sweep: 1600,
                         resonance: 3, level: 0.42, group: .bass),
            .pad: Patch(waves: [.sawtooth, .sawtooth, .sawtooth], detune: 14, attack: 0.35, decay: 1, sustain: 0.8, release: 0.9,
                        cutoff: 2000, vibrato: 6, echo: 0.1, reverb: 0.35, level: 0.07, group: .pad),
            .arp: Patch(waves: [.sawtooth, .square], detune: 8, attack: 0.003, decay: 0.12, sustain: 0, release: 0.08, cutoff: 900,
                        sweep: 3500, resonance: 4, pan: 0.3, echo: 0.35, reverb: 0.2, level: 0.12, group: .lead),
            .keys: Patch(waves: [.sawtooth, .sawtooth], detune: 10, decay: 0.15, sustain: 0.2, release: 0.15, cutoff: 1800,
                         sweep: 2500, pan: -0.2, echo: 0.2, reverb: 0.3, level: 0.06, group: .pad),
            .lead: Patch(waves: [.square, .sawtooth], detune: 10, attack: 0.01, decay: 0.3, sustain: 0.6, release: 0.2, cutoff: 2600,
                         sweep: 1800, resonance: 1.5, vibrato: 12, pan: -0.1, echo: 0.3, reverb: 0.3, level: 0.14, group: .lead),
            .blip: Patch(waves: [.square], attack: 0.002, decay: 0.05, sustain: 0, release: 0.03, cutoff: 6000, level: 0.16, group: .effects),
            .fanfare: Patch(waves: [.sawtooth, .square], detune: 8, decay: 0.25, sustain: 0.3, release: 0.2, cutoff: 3000, sweep: 3000,
                            echo: 0.3, reverb: 0.3, level: 0.16, group: .effects),
        ], kit: KaraokeMusic.Kit(tune: 1, decay: 1, reverb: 0.15), echoSteps: 3, echoFeedback: 0.35, reverbTime: 1.8,
        blipScale: [0, 3, 5, 7, 10, 12, 15, 17], fanfare: [0, 7, 12, 15, 19, 24])
    }

    // MARK: - 80s Karaoke Bar

    /// Synth-pop in C: an eighth-note bass, a big snare in a big room,
    /// strings swelling under a bell-like FM lead.
    static var karaokeBar: KaraokeMusic {
        let score = Score(tempo: 112, root: 48)
        let verse = [[0, 4, 7, 11], [9, 12, 16, 19], [5, 9, 12, 16], [7, 11, 14, 17]]
        let chorus = [[5, 9, 12, 16], [7, 11, 14, 17], [4, 7, 11, 14], [9, 12, 16, 21]]
        let pulse = "0 . 0 . 0 . 0 . 0 . 0 . 0 . 0 12"
        let arp = "0 1 2 3 0 1 2 3 3 2 1 0 3 2 1 0"
        let beat: [Drum: String] = [.kick: "X.......X.x.....", .snare: "....X.......X...", .hat: "x.x.x.x.x.x.x.xx"]
        let groove = section(verse, parts: [.bass: [pulse], .arp: [arp], .pad: [wholeBar]], drums: beat, first: crash)
        let tune = section(verse, parts: [
            .bass: [pulse], .pad: [wholeBar],
            .lead: ["16 - - - 14 - 12 - 11 - 12 - - - . .", "9 - - - 12 - - - 16 - - - 14 - 12 -",
                    "12 - - - 9 - - - 12 - 14 - 16 - 17 -", "19 - - - 17 - 16 - 14 - - - 11 - - -"],
        ], drums: beat, fill: [.snare: "....X.......X.xx"])
        let hook = section(chorus, parts: [
            .bass: [pulse], .pad: [wholeBar], .arp: [arp],
            .lead: ["21 - - - 19 - - - 17 - 16 - 17 - 19 -", "19 - - - 14 - - - 19 - 21 - 19 - 17 -",
                    "16 - - - 14 - 12 - 11 - - - 12 - 14 -", "12 - - - - - - - 16 - 14 - 12 - 9 -"],
        ], drums: beat.merging([.clap: "....x.......x..."]) { $1 }, first: crash)
        let breakdown = section(verse, parts: [.pad: [wholeBar], .arp: [arp], .bass: ["0 - - - - - - - 0 - - - - - - -"]],
                                drums: [.hat: "x.x.x.x.x.x.x.x.", .kick: "X..............."],
                                fill: [.tomHigh: "........X.x.....", .tomLow: "............X.x.", .snare: "..............XX"])
        let intro = [Score.Bar(chord: verse[0], drums: [.kick: "X.......X.......", .tomHigh: "........X.x.....",
                                                        .tomLow: "............X.X.", .snare: "..............XX"])]
        return music(score, intro: intro, loop: groove + tune + hook + breakdown, patches: [
            .bass: Patch(waves: [.sawtooth], attack: 0.003, decay: 0.12, sustain: 0.4, release: 0.05, cutoff: 500, sweep: 1400,
                         resonance: 5, level: 0.38, group: .bass),
            .pad: Patch(waves: [.sawtooth, .sawtooth], detune: 18, attack: 0.4, decay: 1, sustain: 0.85, release: 1, cutoff: 1500,
                        vibrato: 4, reverb: 0.45, level: 0.08, group: .pad),
            .arp: Patch(waves: [.square], attack: 0.002, decay: 0.1, sustain: 0.1, release: 0.05, cutoff: 2500, sweep: 1500,
                        resonance: 2, pan: -0.35, echo: 0.4, level: 0.07, group: .lead),
            .lead: Patch(waves: [.sine], attack: 0.003, decay: 0.6, sustain: 0.25, release: 0.4, fmRatio: 3.5, fmDepth: 2.5,
                         pan: 0.15, echo: 0.35, reverb: 0.4, level: 0.24, group: .lead),
            .blip: Patch(waves: [.square], attack: 0.002, decay: 0.05, sustain: 0, release: 0.03, cutoff: 4000, level: 0.16, group: .effects),
            .fanfare: Patch(waves: [.square, .sawtooth], detune: 6, decay: 0.25, sustain: 0.3, release: 0.2, cutoff: 3000, sweep: 2000,
                            echo: 0.3, reverb: 0.4, level: 0.15, group: .effects),
        ], kit: KaraokeMusic.Kit(tune: 0.9, decay: 1.1, reverb: 0.6), echoSteps: 2, echoFeedback: 0.3, reverbTime: 2.4,
        blipScale: [0, 2, 4, 7, 9, 12, 14, 16], fanfare: [0, 4, 7, 12, 7, 12, 16])
    }

    // MARK: - Bubblegum Pop

    /// Bright pop in F: a bouncy bass, plucks, claps and shakers, and a
    /// glockenspiel doubling the chorus.
    static var bubblegumPop: KaraokeMusic {
        let score = Score(tempo: 128, root: 53)
        let verse = [[0, 4, 7, 12], [7, 11, 14, 19], [9, 12, 16, 21], [5, 9, 12, 17]]
        let chorus = [[5, 9, 12, 17], [7, 11, 14, 19], [4, 7, 11, 16], [9, 12, 16, 21]]
        let bounce = "0 . . 12 . . 0 . 0 . . 12 . 7 . ."
        let pluck = "0 2 1 3 0 2 1 3 2 3 1 2 0 1 2 3"
        let skip: [Drum: String] = [.kick: "X..x..x.X..x..x.", .clap: "....X.......X...", .shaker: "oxoxoxoxoxoxoxox"]
        let groove = section(verse, parts: [.bass: [bounce], .arp: [pluck], .pad: [wholeBar]], drums: skip, first: crash)
        let verseTune = ["12 - 12 - 14 - 16 - - - 14 - 12 - - -", "11 - - - 14 - - - 19 - - - 16 - - -",
                         "16 - 16 - 17 - 16 - 14 - - - 12 - 9 -", "14 - - - 12 - 14 - 17 - - - 16 - - -"]
        let chorusTune = ["17 - - - 17 - 16 - 17 - 19 - - - 21 -", "19 - - - 16 - - - 14 - 16 - 19 - - -",
                          "16 - - - 14 - 12 - 11 - - - 12 - 14 -", "12 - - - - - - - . . 12 - 14 - 16 -"]
        let tune = section(verse, parts: [.bass: [bounce], .pad: [wholeBar], .lead: verseTune],
                           drums: skip, fill: [.clap: "....X.......X.XX"])
        let hook = section(chorus, parts: [.bass: [bounce], .pad: [wholeBar], .lead: chorusTune, .bell: chorusTune],
                           drums: skip.merging([.hat: "..x...x...x...x."]) { $1 }, first: crash)
        let breakdown = section(verse, parts: [.arp: [pluck], .pad: [wholeBar], .bell: [". . 12 . . . 16 . . . 19 . . . 16 ."],
                                               .bass: ["0 - - - . . . . 0 - - - . . . ."]],
                                drums: [.clap: "....x.......x...", .shaker: "o.o.o.o.o.o.o.o."],
                                fill: [.clap: "....x...x.x.xxxx", .kick: "X.......X...X..."])
        let intro = [Score.Bar(chord: verse[0], drums: [.clap: "....x...x.x.xxXX", .kick: "X.......X......."])]
        return music(score, intro: intro, loop: groove + tune + hook + breakdown, patches: [
            .bass: Patch(waves: [.triangle, .sine], decay: 0.2, sustain: 0.3, release: 0.06, cutoff: 1200, level: 0.55, group: .bass),
            .pad: Patch(waves: [.triangle, .sawtooth], detune: 10, attack: 0.2, decay: 0.8, sustain: 0.6, release: 0.6, cutoff: 1800,
                        reverb: 0.3, level: 0.06, group: .pad),
            .arp: Patch(waves: [.square, .triangle], detune: 5, attack: 0.002, decay: 0.14, sustain: 0, release: 0.06, cutoff: 2400,
                        sweep: 2400, resonance: 2, pan: 0.3, echo: 0.25, level: 0.1, group: .lead),
            .lead: Patch(waves: [.square, .triangle], detune: 6, decay: 0.2, sustain: 0.5, release: 0.12, cutoff: 3200, sweep: 1500,
                         resonance: 1, vibrato: 10, echo: 0.2, reverb: 0.2, level: 0.13, group: .lead),
            .bell: Patch(waves: [.sine], attack: 0.001, decay: 0.5, sustain: 0, release: 0.5, fmRatio: 7, fmDepth: 1.2,
                         pan: -0.3, echo: 0.25, reverb: 0.35, level: 0.12, group: .lead),
            .blip: Patch(waves: [.triangle], attack: 0.002, decay: 0.06, sustain: 0, release: 0.04, level: 0.24, group: .effects),
            .fanfare: Patch(waves: [.sine], attack: 0.001, decay: 0.4, sustain: 0, release: 0.3, fmRatio: 7, fmDepth: 1.2,
                            echo: 0.2, reverb: 0.3, level: 0.2, group: .effects),
        ], kit: KaraokeMusic.Kit(tune: 1.15, decay: 0.85, reverb: 0.15), echoSteps: 2, echoFeedback: 0.25, reverbTime: 1.4,
        blipScale: [7, 9, 12, 14, 16, 19, 21, 24], fanfare: [0, 4, 7, 12, 16, 19, 24, 28])
    }

    // MARK: - Vegas Lounge

    /// A lounge swing in G: walking bass, electric piano comping, a
    /// vibraphone on the tune, and brushes.
    static var vegasLounge: KaraokeMusic {
        let score = Score(tempo: 92, root: 43, swing: 0.33, swingSteps: 2)
        let verse = [[0, 4, 7, 11, 14], [9, 12, 16, 19], [2, 5, 9, 12], [7, 11, 14, 17]]
        let bridge = [[5, 9, 12, 16], [4, 7, 11, 14], [2, 5, 9, 12], [7, 11, 14, 17]]
        let walk = ["0 - - - 4 - - - 7 - - - 9 - - -", "0 - - - 3 - - - 7 - - - 5 - - -",
                    "0 - - - 3 - - - 5 - - - 6 - - -", "0 - - - 4 - - - 7 - - - 6 - - -"]
        let comp = ["x - . . . . x - . . . . . . . .", ". . . . x - . . . . x - . . . .",
                    "x - . . . . x - . . . . x . . .", ". . . . x - . . . . . . x - . ."]
        let brushes: [Drum: String] = [.hat: "x...x.x.x...x.x.", .brush: "....x.......x...", .kick: "o.......o......."]
        let groove = section(verse, parts: [.bass: walk, .keys: comp, .pad: [wholeBar]], drums: brushes)
        let tune = ["14 - - - 11 - 12 - 14 - - - . . . .", "16 - - - 14 - 12 - 11 - - - . . . .",
                    "12 - - - 9 - 12 - 16 - - - 14 - 12 -", "11 - - - - - 9 - 7 - - - . . . ."]
        let verseTune = section(verse, parts: [.bass: walk, .keys: comp, .lead: tune], drums: brushes)
        let bridgeTune = section(bridge, parts: [.bass: walk, .keys: comp, .pad: [wholeBar],
                                                 .lead: ["16 - - - 19 - 16 - 14 - - - 12 - - -", "14 - - - 11 - - - 7 - 9 - 11 - - -",
                                                         "12 - - - 16 - - - 14 - 12 - 9 - - -", "11 - - - 12 - 14 - 17 - - - 14 - - -"]],
                                 drums: brushes.merging([.rim: "....x.......x..."]) { $1 })
        let last = section(verse, parts: [.bass: walk, .keys: comp, .lead: tune], drums: brushes,
                           fill: [.brush: "....x.....x.x.xx", .tomLow: "..............x."])
        let intro = [Score.Bar(chord: verse[3], parts: [.bass: "7 - - - 6 - - - 5 - - - 1 - - -"],
                               drums: [.brush: "....x.......x.x.", .hat: "x...x.x.x...x.x."])]
        return music(score, intro: intro, loop: groove + verseTune + bridgeTune + last, patches: [
            .bass: Patch(waves: [.sine, .triangle], decay: 0.35, sustain: 0.25, release: 0.12, cutoff: 900, level: 0.95, group: .bass),
            .keys: Patch(waves: [.sine], attack: 0.003, decay: 0.9, sustain: 0.35, release: 0.5, cutoff: 4000, fmRatio: 1,
                         fmDepth: 1.8, tremolo: 0.25, pan: -0.2, reverb: 0.35, level: 0.22, group: .pad),
            .lead: Patch(waves: [.sine], attack: 0.002, decay: 1.2, sustain: 0.15, release: 0.8, fmRatio: 4, fmDepth: 0.6,
                         tremolo: 0.45, pan: 0.2, echo: 0.1, reverb: 0.45, level: 0.42, group: .lead),
            .pad: Patch(waves: [.triangle, .sine], detune: 6, attack: 0.5, decay: 1, sustain: 0.7, release: 1, cutoff: 1600,
                        reverb: 0.5, level: 0.09, group: .pad),
            .blip: Patch(waves: [.sine], attack: 0.002, decay: 0.08, sustain: 0, release: 0.05, fmRatio: 4, fmDepth: 0.5,
                         level: 0.34, group: .effects),
            .fanfare: Patch(waves: [.sine], attack: 0.002, decay: 0.8, sustain: 0.1, release: 0.5, fmRatio: 4, fmDepth: 0.6,
                            tremolo: 0.4, reverb: 0.45, level: 0.32, group: .effects),
        ], kit: KaraokeMusic.Kit(tune: 0.8, decay: 1.4, reverb: 0.3, level: 1.6), echoSteps: 4, echoFeedback: 0.2, reverbTime: 2.2,
        blipScale: [0, 4, 7, 9, 11, 14, 16, 19], fanfare: [0, 4, 7, 11, 14, 19])
    }
}
