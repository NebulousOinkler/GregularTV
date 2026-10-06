import AVFoundation
import GregularScreens

/// Karaoke's menu tunes and sound effects on Apple TV: `KaraokeMusic`'s
/// notes, synthesized as they play by AVAudioEngine (no sound files), as
/// the web version does with the Web Audio API.
@MainActor final class KaraokeSynth {
    static let shared = KaraokeSynth()
    private let engine = AVAudioEngine()
    private let voices: Voices
    private var playing: KaraokeTheme?

    private init() {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let voices = Voices(sampleRate: rate > 0 ? rate : 48_000)
        self.voices = voices
        let format = AVAudioFormat(standardFormatWithSampleRate: voices.sampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: format, renderBlock: Self.render(voices))
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    /// What the audio thread calls for each buffer. Made outside the main
    /// actor, so it isn't tied to it: the audio thread isn't the main thread.
    private nonisolated static func render(_ voices: Voices) -> AVAudioSourceNodeRenderBlock {
        { _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let samples = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            voices.render(into: samples, frames: Int(frames))
            return noErr
        }
    }

    /// `theme`'s tune, round and round (the same one carries on), or quiet for nil.
    func play(_ theme: KaraokeTheme?) {
        guard theme != playing else { return }
        playing = theme
        if let theme {
            start()
            voices.loop(theme.music.loop, every: theme.music.duration)
        } else {
            voices.fadeOutLoop()
        }
    }

    func effect(_ effect: KaraokeMusic.Effect, in theme: KaraokeTheme) {
        start()
        voices.once(theme.music.notes(for: effect))
    }

    private func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }
}

/// The notes sounding, rendered a buffer at a time on the audio thread. The
/// main thread hands it tunes and effects under `lock`; the audio thread
/// only tries the lock, and plays on with what it has if it's busy.
private final class Voices: @unchecked Sendable {
    let sampleRate: Double
    private let lock = NSLock()

    private struct Voice {
        let sound: KaraokeMusic.Sound
        let start: Int
        let length: Int
        let gain: Float
        let looped: Bool
        var phase: Double = 0
        var noise: UInt32 = 0x9E37_79B9
        var high: Float = 0
        var last: Float = 0
    }

    /// Samples rendered so far: the audio thread's clock.
    private var now = 0
    private var voices: [Voice] = []
    /// Effects' notes, waiting for the audio thread, which starts them as it takes them.
    private var pending: [KaraokeMusic.Event] = []
    private var loopNotes: [KaraokeMusic.Event] = []
    private var loopLength = 0
    private var loopStart = 0
    private var loopNext = 0
    private var newLoop: (notes: [KaraokeMusic.Event], length: Double)?
    /// The tune's volume, moving towards `loopTarget` (a fade).
    private var loopGain: Float = 0
    private var loopTarget: Float = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        voices.reserveCapacity(64)
    }

    func loop(_ notes: [KaraokeMusic.Event], every seconds: Double) {
        lock.withLock { newLoop = (notes, seconds) }
    }

    func fadeOutLoop() {
        lock.withLock { newLoop = ([], 0) }
    }

    func once(_ notes: [KaraokeMusic.Event]) {
        lock.withLock { pending += notes }
    }

    func render(into samples: UnsafeMutablePointer<Float>, frames: Int) {
        if lock.try() {
            takeNew()
            lock.unlock()
        }
        scheduleLoop(until: now + frames)
        let fadeStep = Float(1 / (0.4 * sampleRate))
        for frame in 0..<frames {
            let time = now + frame
            if loopGain < loopTarget { loopGain = min(loopTarget, loopGain + fadeStep) }
            if loopGain > loopTarget { loopGain = max(loopTarget, loopGain - fadeStep) }
            var sum: Float = 0
            for index in voices.indices where time >= voices[index].start {
                sum += sample(&voices[index], at: time - voices[index].start) * (voices[index].looped ? loopGain : 1)
            }
            samples[frame] = max(-1, min(1, sum * 0.6))
        }
        now += frames
        voices.removeAll { now >= $0.start + $0.length + Int(0.05 * sampleRate) }
        if loopTarget == 0, loopGain == 0 { voices.removeAll(where: \.looped) }
    }

    /// Takes what the main thread handed over: effects start now; a new tune
    /// fades in (and the old one's notes go), or the tune fades out.
    private func takeNew() {
        for note in pending {
            voices.append(Voice(sound: note.sound, start: now + Int(note.at * sampleRate), length: Int(note.length * sampleRate),
                                gain: Float(note.gain), looped: false))
        }
        pending.removeAll(keepingCapacity: true)
        guard let (notes, seconds) = newLoop else { return }
        newLoop = nil
        if notes.isEmpty {
            loopTarget = 0
            loopNotes = []
        } else {
            voices.removeAll(where: \.looped)
            loopNotes = notes.sorted { $0.at < $1.at }
            loopLength = Int(seconds * sampleRate)
            loopStart = now
            loopNext = 0
            loopGain = 0
            loopTarget = 1
        }
    }

    /// The tune's notes that start before `end`, round and round.
    private func scheduleLoop(until end: Int) {
        guard !loopNotes.isEmpty, loopLength > 0 else { return }
        while true {
            let round = loopNext / loopNotes.count
            let note = loopNotes[loopNext % loopNotes.count]
            let start = loopStart + round * loopLength + Int(note.at * sampleRate)
            guard start < end else { return }
            voices.append(Voice(sound: note.sound, start: start, length: Int(note.length * sampleRate), gain: Float(note.gain), looped: true))
            loopNext += 1
        }
    }

    /// One sample of a voice, `elapsed` samples in: its wave through a quick
    /// attack and an exponential decay, as the web version's are.
    private func sample(_ voice: inout Voice, at elapsed: Int) -> Float {
        let seconds = Double(elapsed) / sampleRate
        let length = Double(voice.length) / sampleRate
        guard seconds < length + 0.05 else { return 0 }
        switch voice.sound {
        case .tone(let wave, let note):
            let attack = 0.01
            let envelope = seconds < attack ? seconds / attack : pow(0.0001, min(1, (seconds - attack) / max(length - attack, 0.001)))
            voice.phase += 440 * pow(2, Double(note - 69) / 12) / sampleRate
            voice.phase -= voice.phase.rounded(.down)
            let p = voice.phase
            let value: Double = switch wave {
            case .sine: sin(2 * .pi * p)
            case .square: p < 0.5 ? 1 : -1
            case .sawtooth: 2 * p - 1
            case .triangle: 4 * abs(p - 0.5) - 1
            }
            return Float(value * envelope) * voice.gain
        case .kick:
            let frequency = 140 * pow(45.0 / 140, min(1, seconds / 0.12))
            voice.phase += frequency / sampleRate
            voice.phase -= voice.phase.rounded(.down)
            return Float(sin(2 * .pi * voice.phase) * pow(0.0001, min(1, seconds / length))) * voice.gain
        case .hat:
            voice.noise ^= voice.noise << 13
            voice.noise ^= voice.noise >> 17
            voice.noise ^= voice.noise << 5
            let white = Float(voice.noise) / Float(UInt32.max) * 2 - 1
            voice.high = 0.85 * (voice.high + white - voice.last)   // a simple high-pass: just the hiss
            voice.last = white
            return voice.high * Float(pow(0.0001, min(1, seconds / length))) * voice.gain
        }
    }
}
