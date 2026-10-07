import AVFoundation
import GregularScreens

/// Karaoke's menu tunes and sound effects on Apple TV: `KaraokeMusic`'s
/// notes and instruments, synthesized as they play by AVAudioEngine (no
/// sound files), as the web version does with the Web Audio API. The
/// sound is made by `KaraokeMixer`, on the audio thread.
@MainActor final class KaraokeSynth {
    static let shared = KaraokeSynth()
    private let engine = AVAudioEngine()
    private let mixer: KaraokeMixer
    private var playing: KaraokeTheme?

    private init() {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let mixer = KaraokeMixer(sampleRate: rate > 0 ? rate : 48_000)
        self.mixer = mixer
        let format = AVAudioFormat(standardFormatWithSampleRate: mixer.sampleRate, channels: 2)!
        let source = AVAudioSourceNode(format: format, renderBlock: Self.render(mixer))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    /// What the audio thread calls for each buffer. Made outside the main
    /// actor, so it isn't tied to it: the audio thread isn't the main thread.
    private nonisolated static func render(_ mixer: KaraokeMixer) -> AVAudioSourceNodeRenderBlock {
        { _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard list.count >= 2, let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(left: left, right: right, frames: Int(frames))
            return noErr
        }
    }

    /// `theme`'s tune, round and round (the same one carries on; another
    /// crossfades in), or quiet for nil.
    func play(_ theme: KaraokeTheme?) {
        guard theme != playing else { return }
        playing = theme
        if let theme {
            start()
            mixer.send(.loop(theme.music))
        } else {
            mixer.send(.quiet)
        }
    }

    /// How the tune sits: full, or soft under a title card.
    func setMood(_ mood: KaraokeMusic.Mood) {
        mixer.send(.mood(mood))
    }

    func effect(_ effect: KaraokeMusic.Effect, in theme: KaraokeTheme, step: Int = 0) {
        start()
        let music = theme.music
        mixer.send(.effect(music, music.notes(for: effect, step: step)))
    }

    private func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }
}

/// The sound itself, rendered a buffer at a time on the audio thread: each
/// note an instrument (`KaraokeMusic.Patch`) or a drum, through each group's
/// level (the mood), into the echo and the reverb, and out through a gentle
/// limiter. The main thread sends it commands under `lock`; the audio
/// thread only tries the lock, and plays on with what it has if it's busy.
///
/// It also renders without an engine, for tests (and for listening to the
/// tunes, written to files).
final class KaraokeMixer: @unchecked Sendable {
    enum Command {
        /// A tune: its intro, then round and round, crossfading from any other.
        case loop(KaraokeMusic)
        /// Every tune fades out.
        case quiet
        case mood(KaraokeMusic.Mood)
        /// Notes played once, now, with the instruments of `music`.
        case effect(KaraokeMusic, [KaraokeMusic.Event])
    }

    let sampleRate: Double
    private let lock = NSLock()
    private var commands: [Command] = []
    private var taken: [Command] = []

    /// Samples rendered so far: the audio thread's clock.
    private var now = 0
    private var voices: [Voice] = []
    private var tunes: [Tune] = []
    private var nextTuneID = 0
    /// Each group's level (by `Group.index`), moving towards its target.
    private var groupGains: [Float] = Array(repeating: 1, count: KaraokeMusic.Group.allCases.count)
    private var groupTargets: [Float] = Array(repeating: 1, count: KaraokeMusic.Group.allCases.count)
    /// Music dips under an effect until this sample.
    private var duckUntil = 0
    private var duck: Float = 1
    private let echo: Echo
    private let reverb: Reverb

    /// Most notes at once: past this, new ones are dropped (the audio thread mustn't allocate).
    private static let mostVoices = 240
    /// Envelopes, filters and wobbles are worked out once every this many samples.
    static let block = 32

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voices.reserveCapacity(Self.mostVoices)
        tunes.reserveCapacity(8)
        commands.reserveCapacity(64)
        taken.reserveCapacity(64)
        echo = Echo(sampleRate: sampleRate)
        reverb = Reverb(sampleRate: sampleRate)
    }

    func send(_ command: Command) {
        lock.withLock { commands.append(command) }
    }

    /// Fills `frames` samples of each channel.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        if lock.try() {
            swap(&commands, &taken)
            lock.unlock()
            for command in taken { take(command) }
            taken.removeAll(keepingCapacity: true)
        }
        var done = 0
        while done < frames {
            let count = min(Self.block, frames - done)
            renderBlock(left: left + done, right: right + done, frames: count)
            done += count
        }
    }

    // MARK: - Commands

    private func take(_ command: Command) {
        switch command {
        case .loop(let music):
            for index in tunes.indices { tunes[index].fadeTo(0, over: 0.6 * sampleRate) }
            var tune = Tune(id: nextTuneID, music: music, start: now + Int(0.05 * sampleRate))
            tune.fadeTo(1, over: 0.4 * sampleRate)
            nextTuneID += 1
            tunes.append(tune)
            echo.set(time: music.echoTime, feedback: music.echoFeedback)
            reverb.set(time: music.reverbTime)
        case .quiet:
            for index in tunes.indices { tunes[index].fadeTo(0, over: 1.2 * sampleRate) }
        case .mood(let mood):
            for group in KaraokeMusic.Group.allCases {
                groupTargets[group.index] = Float(KaraokeMusic.gain(of: group, in: mood))
            }
        case .effect(let music, let events):
            if tunes.isEmpty {
                echo.set(time: music.echoTime, feedback: music.echoFeedback)
                reverb.set(time: music.reverbTime)
            }
            let start = now + Int(0.005 * sampleRate)
            var end = start
            for event in events {
                let at = start + Int(event.at * sampleRate)
                startVoice(event, of: music, at: at, tune: -1)
                end = max(end, at + Int(event.length * sampleRate))
            }
            duckUntil = max(duckUntil, end + Int(0.15 * sampleRate))
        }
    }

    // MARK: - Rendering

    private func renderBlock(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        let end = now + frames
        for index in tunes.indices { schedule(&tunes[index], until: end) }

        // Levels, once a block.
        let smoothing = Float(1 - exp(-Double(frames) / (0.8 * sampleRate)))
        for index in groupGains.indices { groupGains[index] += (groupTargets[index] - groupGains[index]) * smoothing }
        let duckTarget: Float = now < duckUntil ? 0.55 : 1
        duck += (duckTarget - duck) * Float(1 - exp(-Double(frames) / ((duckTarget < duck ? 0.02 : 0.3) * sampleRate)))

        // Mix into the output, with sends gathered alongside.
        for frame in 0..<frames {
            left[frame] = 0
            right[frame] = 0
        }
        echo.clearSends(frames)
        reverb.clearSends(frames)
        for index in voices.indices {
            let tuneGain: Float = voices[index].tune < 0 ? 1 : (tunes.first { $0.id == voices[index].tune }?.gain ?? 0)
            let group = voices[index].group
            let level = tuneGain * groupGains[group] * (group == KaraokeMusic.Group.effects.index ? 1 : duck)
            voices[index].render(from: now, frames: frames, level: level, sampleRate: sampleRate,
                                 left: left, right: right, echo: echo.sends, reverb: reverb.sends)
        }
        echo.process(frames, intoLeft: left, right: right)
        reverb.process(frames, intoLeft: left, right: right)
        for frame in 0..<frames {
            left[frame] = Self.limit(left[frame] * 0.8)
            right[frame] = Self.limit(right[frame] * 0.8)
        }

        now = end
        voices.removeAll { $0.isDone(at: now) }
        // A tune faded right out goes, with its notes.
        for tune in tunes where tune.gain == 0 && tune.target == 0 {
            voices.removeAll { $0.tune == tune.id }
        }
        tunes.removeAll { $0.gain == 0 && $0.target == 0 }
        for index in tunes.indices { tunes[index].advanceFade(frames) }
    }

    /// Soft above about 0.7, never past 1.
    private static func limit(_ x: Float) -> Float {
        let clamped = max(-3, min(3, x))
        return clamped * (27 + clamped * clamped) / (27 + 9 * clamped * clamped)
    }

    /// Starts the notes of `tune` that start before `end`: the intro once, then the loop round and round.
    private func schedule(_ tune: inout Tune, until end: Int) {
        let music = tune.music
        while tune.nextIntro < music.intro.count {
            let event = music.intro[tune.nextIntro]
            let at = tune.start + Int(event.at * sampleRate)
            guard at < end else { return }
            startVoice(event, of: music, at: at, tune: tune.id)
            tune.nextIntro += 1
        }
        guard !music.loop.isEmpty, music.duration > 0 else { return }
        let loopStart = tune.start + Int(music.introDuration * sampleRate)
        while true {
            let round = tune.nextLoop / music.loop.count
            let event = music.loop[tune.nextLoop % music.loop.count]
            let at = loopStart + Int((Double(round) * music.duration + event.at) * sampleRate)
            guard at < end else { return }
            startVoice(event, of: music, at: at, tune: tune.id)
            tune.nextLoop += 1
        }
    }

    private func startVoice(_ event: KaraokeMusic.Event, of music: KaraokeMusic, at start: Int, tune: Int) {
        guard voices.count < Self.mostVoices else { return }
        switch event.sound {
        case .note(let part, let note):
            guard let patch = music.patches[part] else { return }
            voices.append(Voice(note: note, patch: patch, event: event, start: start, tune: tune, sampleRate: sampleRate))
        case .drum(let drum):
            voices.append(Voice(drum: drum, kit: music.kit, event: event, start: start, tune: tune, sampleRate: sampleRate))
        }
    }

    /// A tune playing, and how far through it is.
    private struct Tune {
        let id: Int
        let music: KaraokeMusic
        /// When its intro starts.
        let start: Int
        var nextIntro = 0
        /// Notes of the loop started so far, all rounds.
        var nextLoop = 0
        var gain: Float = 0
        var target: Float = 0
        var step: Float = 0

        init(id: Int, music: KaraokeMusic, start: Int) {
            self.id = id
            self.music = music
            self.start = start
        }

        mutating func fadeTo(_ level: Float, over samples: Double) {
            target = level
            step = Float(1 / max(samples, 1))
        }

        mutating func advanceFade(_ frames: Int) {
            let change = step * Float(frames)
            gain = gain < target ? min(target, gain + change) : max(target, gain - change)
        }
    }
}

extension KaraokeMusic.Group {
    var index: Int { Self.allCases.firstIndex(of: self)! }
}

// MARK: - Voices

/// One note or drum hit, rendered as it sounds.
private struct Voice {
    enum Kind {
        case tone
        case drum(KaraokeMusic.Drum)
    }

    let kind: Kind
    let tune: Int
    let group: Int
    let start: Int
    /// When it's silent and can go.
    let end: Int
    let gain: Float
    let panLeft: Float
    let panRight: Float
    let echoSend: Float
    let reverbSend: Float

    // A tone's.
    private let frequency: Double
    private let waves: (KaraokeMusic.Wave, KaraokeMusic.Wave, KaraokeMusic.Wave)
    private let waveCount: Int
    private let detunes: (Double, Double, Double)
    private let attack, decay, sustain, release, hold: Double
    private let cutoff, sweep, resonance: Double
    private let filtered: Bool
    private let fmRatio, fmDepth, vibrato, tremolo: Double
    private var phases: (Double, Double, Double) = (0, 0.31, 0.67)
    private var fmPhase = 0.0

    // A drum's: the kit's tuning and ring.
    private let pitch: Double
    private let ring: Double
    private var noise: UInt32

    // The filter (a state-variable filter), shared by tones and drums.
    private var ic1: Float = 0
    private var ic2: Float = 0

    init(note: Int, patch: KaraokeMusic.Patch, event: KaraokeMusic.Event, start: Int, tune: Int, sampleRate: Double) {
        kind = .tone
        self.tune = tune
        group = patch.group.index
        self.start = start
        frequency = 440 * pow(2, Double(note - 69) / 12)
        let waves = patch.waves.isEmpty ? [.sine] : patch.waves
        let count = min(3, waves.count)
        waveCount = count
        self.waves = (waves[0], waves[min(1, waves.count - 1)], waves[min(2, waves.count - 1)])
        func cents(_ index: Int) -> Double {
            count == 1 ? 0 : patch.detune * (Double(index) / Double(count - 1) - 0.5)
        }
        detunes = (pow(2, cents(0) / 1200), pow(2, cents(1) / 1200), pow(2, cents(2) / 1200))
        attack = patch.attack
        decay = patch.decay
        sustain = patch.sustain
        release = patch.release
        hold = max(event.length, patch.attack)
        cutoff = patch.cutoff
        sweep = patch.sweep
        resonance = max(patch.resonance, 0.5)
        filtered = patch.cutoff + patch.sweep < 0.4 * sampleRate
        fmRatio = patch.fmRatio
        fmDepth = patch.fmDepth
        vibrato = patch.vibrato
        tremolo = patch.tremolo
        gain = Float(patch.level * event.gain / Double(count).squareRoot())
        (panLeft, panRight) = Self.pan(patch.pan + event.pan)
        echoSend = Float(patch.echo)
        reverbSend = Float(patch.reverb)
        end = start + Int((max(event.length, patch.attack) + patch.release * 1.5 + 0.02) * sampleRate)
        pitch = 1
        ring = 1
        noise = 0x9E37_79B9 ^ UInt32(truncatingIfNeeded: start)
    }

    init(drum: KaraokeMusic.Drum, kit: KaraokeMusic.Kit, event: KaraokeMusic.Event, start: Int, tune: Int, sampleRate: Double) {
        kind = .drum(drum)
        self.tune = tune
        group = KaraokeMusic.Group.drums.index
        self.start = start
        pitch = kit.tune
        ring = kit.decay
        gain = Float(event.gain * kit.level)
        (panLeft, panRight) = Self.pan(event.pan)
        echoSend = 0
        switch drum {
        case .snare, .clap, .tomHigh, .tomLow, .rim, .brush: reverbSend = Float(kit.reverb)
        default: reverbSend = 0.05
        }
        let length: Double = switch drum {
        case .kick, .tomHigh, .tomLow, .openHat: 0.6
        case .snare, .clap, .brush: 0.4
        case .hat, .rim: 0.15
        case .shaker: 0.2
        case .crash: 2.5
        }
        end = start + Int(length * kit.decay * sampleRate)
        noise = 0x2545_F491 ^ UInt32(truncatingIfNeeded: start &* 2_654_435_761)
        frequency = 0
        waves = (.sine, .sine, .sine)
        waveCount = 0
        detunes = (1, 1, 1)
        attack = 0; decay = 1; sustain = 0; release = 0; hold = 0
        cutoff = 0; sweep = 0; resonance = 0.7; filtered = false
        fmRatio = 0; fmDepth = 0; vibrato = 0; tremolo = 0
    }

    /// Equal-power, from -1 (left) to 1 (right).
    private static func pan(_ pan: Double) -> (Float, Float) {
        let angle = (max(-1, min(1, pan)) + 1) * .pi / 4
        return (Float(cos(angle)), Float(sin(angle)))
    }

    func isDone(at sample: Int) -> Bool {
        sample >= end
    }

    /// Adds `frames` samples, from `now`, to the outputs and the sends.
    mutating func render(from now: Int, frames: Int, level: Float, sampleRate: Double,
                         left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                         echo: UnsafeMutablePointer<Float>, reverb: UnsafeMutablePointer<Float>) {
        guard now + frames > start, level > 0 else { return }
        let first = max(0, start - now)
        let out = gain * level
        switch kind {
        case .tone:
            renderTone(from: now, first: first, frames: frames, sampleRate: sampleRate, out: out,
                       left: left, right: right, echo: echo, reverb: reverb)
        case .drum(let drum):
            for frame in first..<frames {
                let t = Double(now + frame - start) / sampleRate
                let value = drumSample(drum, at: t, sampleRate: sampleRate) * out
                mix(value, at: frame, left: left, right: right, echo: echo, reverb: reverb)
            }
        }
    }

    private func mix(_ value: Float, at frame: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                     echo: UnsafeMutablePointer<Float>, reverb: UnsafeMutablePointer<Float>) {
        let l = value * panLeft
        let r = value * panRight
        left[frame] += l
        right[frame] += r
        if echoSend > 0 {
            echo[2 * frame] += l * echoSend
            echo[2 * frame + 1] += r * echoSend
        }
        reverb[frame] += value * reverbSend
    }

    // MARK: Tones

    /// The envelope `t` seconds in: attack, decay to the sustain, then the release.
    private func envelope(at t: Double) -> Double {
        if t < attack { return t / attack }
        let decayed = sustain + (1 - sustain) * exp(-(t - attack) * 4 / decay)
        if t < hold { return decayed }
        let atRelease = hold < attack ? hold / attack : sustain + (1 - sustain) * exp(-(hold - attack) * 4 / decay)
        return atRelease * exp(-(t - hold) * 5 / release)
    }

    private mutating func renderTone(from now: Int, first: Int, frames: Int, sampleRate: Double, out: Float,
                                     left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                                     echo: UnsafeMutablePointer<Float>, reverb: UnsafeMutablePointer<Float>) {
        let t0 = Double(now + first - start) / sampleRate
        let t1 = Double(now + frames - start) / sampleRate
        let from = Float(envelope(at: t0))
        let to = Float(envelope(at: t1))
        let wobble = tremolo > 0 ? Float(1 - tremolo * (0.5 + 0.5 * sin(2 * .pi * 5 * t0))) : 1
        let bend = vibrato > 0 ? pow(2, vibrato * sin(2 * .pi * 5.5 * t0) / 1200) : 1
        let base = frequency * bend / sampleRate
        let fmIndex = fmRatio > 0 ? fmDepth * exp(-t0 * 3 / decay) : 0
        // The filter, for this block.
        var a1: Float = 0, a2: Float = 0, a3: Float = 0
        if filtered {
            let fc = min(cutoff + sweep * exp(-t0 * 3 / decay), 0.45 * sampleRate)
            let g = tan(.pi * fc / sampleRate)
            let k = 1 / resonance
            a1 = Float(1 / (1 + g * (g + k)))
            a2 = Float(g) * a1
            a3 = Float(g) * a2
        }
        let count = Float(frames - first)
        for frame in first..<frames {
            let progress = Float(frame - first) / count
            let amplitude = (from + (to - from) * progress) * wobble
            var value: Double = 0
            if fmRatio > 0 {
                fmPhase += base * fmRatio
                fmPhase -= fmPhase.rounded(.down)
                let modulated = base * (1 + fmIndex * fmRatio * sin(2 * .pi * fmPhase))
                phases.0 += modulated
                phases.0 -= phases.0.rounded(.down)
                value = Self.wave(waves.0, phases.0, modulated)
            } else {
                let dt0 = base * detunes.0
                phases.0 += dt0
                phases.0 -= phases.0.rounded(.down)
                value = Self.wave(waves.0, phases.0, dt0)
                if waveCount > 1 {
                    let dt1 = base * detunes.1
                    phases.1 += dt1
                    phases.1 -= phases.1.rounded(.down)
                    value += Self.wave(waves.1, phases.1, dt1)
                }
                if waveCount > 2 {
                    let dt2 = base * detunes.2
                    phases.2 += dt2
                    phases.2 -= phases.2.rounded(.down)
                    value += Self.wave(waves.2, phases.2, dt2)
                }
            }
            var sample = Float(value)
            if filtered { sample = stateVariable(sample, a1, a2, a3).low }
            mix(sample * amplitude * out, at: frame, left: left, right: right, echo: echo, reverb: reverb)
        }
    }

    /// One sample of a wave at `phase` (0 to 1), smoothed at its jumps
    /// (PolyBLEP) so high notes don't fizz, as a browser's oscillators don't.
    private static func wave(_ wave: KaraokeMusic.Wave, _ phase: Double, _ step: Double) -> Double {
        switch wave {
        case .sine: return sin(2 * .pi * phase)
        case .triangle: return 4 * abs(phase - 0.5) - 1
        case .sawtooth: return 2 * phase - 1 - blep(phase, step)
        case .square:
            let shifted = phase + 0.5 - (phase + 0.5).rounded(.down)
            return (phase < 0.5 ? 1 : -1) + blep(phase, step) - blep(shifted, step)
        }
    }

    private static func blep(_ t: Double, _ dt: Double) -> Double {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    /// One step of the state-variable filter (Cytomic's, trapezoidal), with
    /// its coefficients: its low-pass and band-pass outputs.
    private mutating func stateVariable(_ input: Float, _ a1: Float, _ a2: Float, _ a3: Float) -> (low: Float, band: Float) {
        let v3 = input - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return (v2, v1)
    }

    // MARK: Drums

    private mutating func white() -> Float {
        noise ^= noise << 13
        noise ^= noise >> 17
        noise ^= noise << 5
        return Float(noise) / Float(UInt32.max) * 2 - 1
    }

    /// Noise through a state-variable filter: its high-pass (`band` false) or band-pass output.
    private mutating func filteredNoise(_ frequency: Double, q: Double, band: Bool, sampleRate: Double) -> Float {
        let g = Float(tan(.pi * min(frequency, 0.45 * sampleRate) / sampleRate))
        let k = Float(1 / q)
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2
        let input = white()
        let output = stateVariable(input, a1, a2, a3)
        return band ? output.band : input - k * output.band - output.low
    }

    /// A drum's sample `t` seconds after it's hit, from noise and falling tones.
    private mutating func drumSample(_ drum: KaraokeMusic.Drum, at t: Double, sampleRate: Double) -> Float {
        let d = ring
        func decay(_ seconds: Double) -> Double { exp(-t / (seconds * d)) }
        func tone(_ frequency: Double) -> Float {
            phases.0 += frequency / sampleRate
            phases.0 -= phases.0.rounded(.down)
            return Float(sin(2 * .pi * phases.0))
        }
        switch drum {
        case .kick:
            let body = tone(45 * pitch + 105 * pitch * exp(-t / 0.03)) * Float(decay(0.14))
            return body + white() * Float(exp(-t / 0.003)) * 0.25
        case .snare:
            let body = tone(185 * pitch) * Float(decay(0.05)) * 0.5
            return body + filteredNoise(1400 * pitch, q: 0.7, band: false, sampleRate: sampleRate) * Float(decay(0.09)) * 0.8
        case .clap:
            let burst = t < 0.03 ? exp(-t.truncatingRemainder(dividingBy: 0.01) / 0.003) : exp(-(t - 0.03) / (0.09 * d))
            return filteredNoise(1100 * pitch, q: 1.2, band: true, sampleRate: sampleRate) * Float(burst) * 2.2
        case .hat:
            return filteredNoise(7000 * pitch, q: 0.7, band: false, sampleRate: sampleRate) * Float(decay(0.018))
        case .openHat:
            return filteredNoise(6500 * pitch, q: 0.7, band: false, sampleRate: sampleRate) * Float(decay(0.14))
        case .shaker:
            let swell = min(1, t / 0.008)
            return filteredNoise(5000 * pitch, q: 0.7, band: false, sampleRate: sampleRate) * Float(swell * decay(0.035))
        case .crash:
            return filteredNoise(4000 * pitch, q: 0.7, band: false, sampleRate: sampleRate) * Float(decay(0.55))
        case .brush:
            let swell = t < 0.03 ? t / 0.03 : exp(-(t - 0.03) / (0.09 * d))
            return filteredNoise(2600 * pitch, q: 0.7, band: true, sampleRate: sampleRate) * Float(swell) * 1.6
        case .tomHigh:
            return tone(200 * pitch + 60 * pitch * exp(-t / 0.05)) * Float(decay(0.16))
        case .tomLow:
            return tone(120 * pitch + 40 * pitch * exp(-t / 0.05)) * Float(decay(0.2))
        case .rim:
            let click = tone(900 * pitch) * Float(exp(-t / 0.012))
            return click + filteredNoise(2000 * pitch, q: 1.5, band: true, sampleRate: sampleRate) * Float(exp(-t / 0.008))
        }
    }
}

// MARK: - Echo and reverb

/// A ping-pong echo: each repeat crosses to the other side, a little darker.
private final class Echo {
    private let sampleRate: Double
    private var left: [Float]
    private var right: [Float]
    private var position = 0
    private var delay = 1
    private var feedback: Float = 0.3
    private var tone: (Float, Float) = (0, 0)
    /// What the voices send it, two samples (left, right) a frame, for a block.
    private(set) var sends: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let length = Int(2 * sampleRate)
        left = Array(repeating: 0, count: length)
        right = Array(repeating: 0, count: length)
        sends = .allocate(capacity: 2 * KaraokeMixer.block)
        sends.initialize(repeating: 0, count: 2 * KaraokeMixer.block)
    }

    deinit {
        sends.deallocate()
    }

    func set(time: Double, feedback: Double) {
        delay = max(1, min(left.count - 1, Int(time * sampleRate)))
        self.feedback = Float(min(0.8, feedback))
    }

    func clearSends(_ frames: Int) {
        sends.update(repeating: 0, count: 2 * frames)
    }

    func process(_ frames: Int, intoLeft outLeft: UnsafeMutablePointer<Float>, right outRight: UnsafeMutablePointer<Float>) {
        let length = left.count
        for frame in 0..<frames {
            let read = (position - delay + length) % length
            let l = left[read]
            let r = right[read]
            outLeft[frame] += l * 0.6
            outRight[frame] += r * 0.6
            tone.0 += 0.35 * (r - tone.0)
            tone.1 += 0.35 * (l - tone.1)
            left[position] = sends[2 * frame] + tone.0 * feedback
            right[position] = sends[2 * frame + 1] + tone.1 * feedback
            position = (position + 1) % length
        }
    }
}

/// A small room: four damped combs into two all-passes a side (after Freeverb).
private final class Reverb {
    private var combs: [Comb]
    private var passes: [AllPass]
    private(set) var sends: UnsafeMutablePointer<Float>
    private let sampleRate: Double

    private struct Comb {
        var buffer: [Float]
        var position = 0
        var store: Float = 0
        var feedback: Float = 0.8

        mutating func process(_ input: Float) -> Float {
            let output = buffer[position]
            store = output * 0.7 + store * 0.3
            buffer[position] = input + store * feedback
            position = (position + 1) % buffer.count
            return output
        }
    }

    private struct AllPass {
        var buffer: [Float]
        var position = 0

        mutating func process(_ input: Float) -> Float {
            let delayed = buffer[position]
            let output = delayed - input
            buffer[position] = input + delayed * 0.5
            position = (position + 1) % buffer.count
            return output
        }
    }

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let scale = sampleRate / 44_100
        let combLengths = [1116, 1188, 1277, 1356]
        combs = (combLengths + combLengths.map { $0 + 23 }).map { Comb(buffer: Array(repeating: 0, count: Int(Double($0) * scale))) }
        let passLengths = [556, 441]
        passes = (passLengths + passLengths.map { $0 + 23 }).map { AllPass(buffer: Array(repeating: 0, count: Int(Double($0) * scale))) }
        sends = .allocate(capacity: KaraokeMixer.block)
        sends.initialize(repeating: 0, count: KaraokeMixer.block)
        set(time: 1.8)
    }

    deinit {
        sends.deallocate()
    }

    /// How long it rings, in seconds (to a thousandth).
    func set(time: Double) {
        for index in combs.indices {
            let length = Double(combs[index].buffer.count) / sampleRate
            combs[index].feedback = Float(pow(0.001, length / max(time, 0.2)))
        }
    }

    func clearSends(_ frames: Int) {
        sends.update(repeating: 0, count: frames)
    }

    func process(_ frames: Int, intoLeft outLeft: UnsafeMutablePointer<Float>, right outRight: UnsafeMutablePointer<Float>) {
        for frame in 0..<frames {
            let input = sends[frame] * 0.2
            var l: Float = 0
            var r: Float = 0
            for index in 0..<4 { l += combs[index].process(input) }
            for index in 4..<8 { r += combs[index].process(input) }
            for index in 0..<2 { l = passes[index].process(l) }
            for index in 2..<4 { r = passes[index].process(r) }
            outLeft[frame] += l * 0.35
            outRight[frame] += r * 0.35
        }
    }
}
