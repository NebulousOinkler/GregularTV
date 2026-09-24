import Foundation
import Testing
@testable import GregularTVCore

struct StreamingQualityTests {
    @Test func autoUsesSeventyPercentOfMeasuredBandwidth() {
        #expect(StreamingQuality.autoBitrate(measured: 20_000_000) == 14_000_000)
    }

    @Test func autoIsClampedToTheAvailableRange() {
        #expect(StreamingQuality.autoBitrate(measured: 100_000) == 1_500_000)
        #expect(StreamingQuality.autoBitrate(measured: 1_000_000_000) == StreamingQuality.maximumBitrate)
    }

    @Test func onlyAutoHasNoFixedCap() {
        #expect(StreamingQuality.allCases.filter { $0.fixedBitrate == nil } == [.auto])
    }

    @Test func fixedCapsDescendInMenuOrder() {
        let caps = StreamingQuality.allCases.compactMap(\.fixedBitrate)
        #expect(caps == caps.sorted(by: >))
    }
}

struct TranscodeReasonTests {
    private func source(_ method: PlaybackSource.Method, _ query: String) -> PlaybackSource {
        PlaybackSource(url: URL(string: "https://tv.invalid/videos/x/master.m3u8?\(query)")!, method: method, playSessionID: nil)
    }

    @Test func steppingDownGoesOneOptionAtATime() {
        #expect(StreamingQuality.bitrate(below: StreamingQuality.maximumBitrate) == 20_000_000)
        #expect(StreamingQuality.bitrate(below: 20_000_000) == 10_000_000)
        #expect(StreamingQuality.bitrate(below: 8_000_000) == 4_000_000, "Auto's cap falls to the next option below it")
        #expect(StreamingQuality.bitrate(below: 4_000_000) == StreamingQuality.lowestBitrate)
        #expect(StreamingQuality.bitrate(below: StreamingQuality.lowestBitrate) == nil)
    }

    @Test func onlyVideoReasonsMeanAReencode() {
        #expect(!source(.directPlay, "").reencodesVideo)
        #expect(!source(.hls, "TranscodeReasons=ContainerNotSupported").reencodesVideo)
        #expect(!source(.hls, "TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported").reencodesVideo)
        #expect(source(.hls, "TranscodeReasons=VideoCodecNotSupported").reencodesVideo)
        #expect(source(.hls, "TranscodeReasons=ContainerNotSupported,ContainerBitrateExceedsLimit").reencodesVideo)
    }
}
