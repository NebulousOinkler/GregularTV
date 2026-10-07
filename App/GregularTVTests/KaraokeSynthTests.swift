import Foundation
import Testing
@testable import GregularScreens
@testable import GregularTV

/// Karaoke's synthesizer, rendered without an engine: every theme's tune
/// and effects make sound, and never clip.
///
/// To listen to the tunes, run these with `TEST_RUNNER_KARAOKE_AUDITION_DIR`
/// set to a folder: each theme's intro and a whole loop, then its effects,
/// are written there as WAV files.
struct KaraokeSynthTests {
    static let sampleRate = 44_100.0

    /// `seconds` of sound from a mixer, left and right.
    private func render(_ mixer: KaraokeMixer, seconds: Double) -> (left: [Float], right: [Float]) {
        let frames = Int(seconds * Self.sampleRate)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        var done = 0
        while done < frames {
            let count = min(512, frames - done)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    mixer.render(left: l.baseAddress! + done, right: r.baseAddress! + done, frames: count)
                }
            }
            done += count
        }
        return (left, right)
    }

    @Test(arguments: KaraokeTheme.allCases)
    func eachTunePlaysWithoutClipping(theme: KaraokeTheme) {
        let mixer = KaraokeMixer(sampleRate: Self.sampleRate)
        mixer.send(.loop(theme.music))
        let (left, right) = render(mixer, seconds: 6)
        let samples = left + right
        #expect(!samples.contains { !$0.isFinite })
        let peak = samples.map(abs).max() ?? 0
        #expect(peak > 0.05, "Loud enough to hear")
        #expect(peak <= 1, "Never clips")
        let loud = samples.filter { abs($0) > 0.97 }.count
        #expect(Double(loud) / Double(samples.count) < 0.001, "Hardly ever on the limiter")
        #expect(zip(left, right).contains { abs($0 - $1) > 0.01 }, "Stereo")
    }

    @Test func aNewTuneCrossfadesAndQuietFadesOut() {
        let mixer = KaraokeMixer(sampleRate: Self.sampleRate)
        mixer.send(.loop(KaraokeTheme.neonDisco.music))
        _ = render(mixer, seconds: 1)
        mixer.send(.loop(KaraokeTheme.vegasLounge.music))
        let crossfade = render(mixer, seconds: 1).left
        #expect(crossfade.contains { abs($0) > 0.01 }, "No gap between them")
        mixer.send(.quiet)
        _ = render(mixer, seconds: 4)
        let after = render(mixer, seconds: 0.5).left
        #expect(after.allSatisfy { abs($0) < 0.001 }, "Silent once faded, echoes and all")
    }

    @Test(arguments: KaraokeMusic.Effect.allCases)
    func everyEffectSounds(effect: KaraokeMusic.Effect) {
        let mixer = KaraokeMixer(sampleRate: Self.sampleRate)
        let music = KaraokeTheme.karaokeBar.music
        mixer.send(.effect(music, music.notes(for: effect)))
        let samples = render(mixer, seconds: 1.5).left
        #expect(samples.contains { abs($0) > 0.02 } && samples.allSatisfy { abs($0) <= 1 })
    }

    /// Writes each theme's tune and effects to WAV files, when asked.
    @Test func audition() throws {
        guard let folder = ProcessInfo.processInfo.environment["KARAOKE_AUDITION_DIR"] else { return }
        for theme in KaraokeTheme.allCases {
            let music = theme.music
            let mixer = KaraokeMixer(sampleRate: Self.sampleRate)
            mixer.send(.loop(music))
            let tune = render(mixer, seconds: music.introDuration + music.duration + 1)
            try wav(tune, to: URL(fileURLWithPath: folder).appendingPathComponent("\(theme.rawValue)-tune.wav"))
            let effects = KaraokeMixer(sampleRate: Self.sampleRate)
            var sound: (left: [Float], right: [Float]) = ([], [])
            for effect in KaraokeMusic.Effect.allCases {
                let steps = effect == .move ? Array(0..<8) : [0]
                for step in steps {
                    effects.send(.effect(music, music.notes(for: effect, step: step)))
                    let part = render(effects, seconds: effect == .move ? 0.15 : effect == .encore ? 3.5 : 1.6)
                    sound.left += part.left
                    sound.right += part.right
                }
            }
            try wav(sound, to: URL(fileURLWithPath: folder).appendingPathComponent("\(theme.rawValue)-effects.wav"))
        }
    }

    /// 16-bit stereo PCM.
    private func wav(_ sound: (left: [Float], right: [Float]), to url: URL) throws {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let frames = sound.left.count
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + frames * 4))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2)); append(UInt32(Self.sampleRate))
        append(UInt32(Self.sampleRate * 4)); append(UInt16(4)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(frames * 4))
        for index in 0..<frames {
            append(Int16(max(-1, min(1, sound.left[index])) * 32_767))
            append(Int16(max(-1, min(1, sound.right[index])) * 32_767))
        }
        try data.write(to: url)
    }
}
