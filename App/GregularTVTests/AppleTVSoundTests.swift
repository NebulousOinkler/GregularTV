import AVFoundation
import Foundation
import Testing

/// What Apple TV's own player decodes beyond what it was first said to
/// play (`PlayableFormats.appleTV`): FLAC, and 7.1 sound. Each case makes
/// a second of tone in the format, in an MP4 file as a library holds it,
/// and plays it. In the simulator, these are the Mac's decoders; a real
/// Apple TV's are checked on the device (PLAN §7a).
@MainActor @Suite(.serialized)
struct AppleTVSoundTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let format: AudioFormatID
        let layout: AudioChannelLayoutTag
        var testDescription: String { name }
    }

    nonisolated static let cases = [
        Case(name: "FLAC stereo", format: kAudioFormatFLAC, layout: kAudioChannelLayoutTag_Stereo),
        Case(name: "FLAC 5.1", format: kAudioFormatFLAC, layout: kAudioChannelLayoutTag_MPEG_5_1_A),
        Case(name: "FLAC 7.1", format: kAudioFormatFLAC, layout: kAudioChannelLayoutTag_MPEG_7_1_C),
        Case(name: "AAC 5.1", format: kAudioFormatMPEG4AAC, layout: kAudioChannelLayoutTag_AAC_5_1),
        Case(name: "AAC 7.1", format: kAudioFormatMPEG4AAC, layout: kAudioChannelLayoutTag_AAC_7_1),
    ]

    @Test(arguments: cases)
    func applesPlayerPlaysIt(_ sound: Case) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try write(sound, to: url)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        let deadline = Date.now.addingTimeInterval(5)
        while Date.now < deadline, item.status != .failed, player.currentTime().seconds < 0.3 {
            try await Task.sleep(for: .milliseconds(50))
        }
        player.pause()
        #expect(item.status == .readyToPlay && player.currentTime().seconds >= 0.3,
                "\(sound.name) didn't play: \(item.error.map { String(describing: $0) } ?? "no error, it just didn't move")")
    }

    /// A second of a tone on every channel, encoded as `sound`.
    private func write(_ sound: Case, to url: URL) throws {
        let layout = try #require(AVAudioChannelLayout(layoutTag: sound.layout))
        var layoutData = AudioChannelLayout(mChannelLayoutTag: sound.layout, mChannelBitmap: [], mNumberChannelDescriptions: 0,
                                            mChannelDescriptions: AudioChannelDescription())
        let settings: [String: Any] = [
            AVFormatIDKey: sound.format,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: layout.channelCount,
            AVChannelLayoutKey: Data(bytes: &layoutData, count: MemoryLayout<AudioChannelLayout>.size),
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000))
        buffer.frameLength = 48_000
        for channel in 0..<Int(layout.channelCount) {
            let samples = try #require(buffer.floatChannelData?[channel])
            for frame in 0..<48_000 { samples[frame] = 0.2 * sin(2 * .pi * Float(220 * (channel + 1)) * Float(frame) / 48_000) }
        }
        try file.write(from: buffer)
    }
}
