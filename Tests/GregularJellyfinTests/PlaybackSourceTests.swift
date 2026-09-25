import Foundation
import Testing
@testable import GregularJellyfin

/// What Jellyfin's stream URL says about the work it's doing.
struct PlaybackSourceTests {
    private func source(_ method: PlaybackSource.Method, _ query: String) -> PlaybackSource {
        PlaybackSource(url: URL(string: "https://tv.invalid/videos/x/master.m3u8?\(query)")!, method: method, playSessionID: nil)
    }

    @Test func onlyVideoReasonsMeanAReencode() {
        #expect(!source(.directPlay, "").reencodesVideo)
        #expect(!source(.hls, "TranscodeReasons=ContainerNotSupported").reencodesVideo)
        #expect(!source(.hls, "TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported").reencodesVideo)
        #expect(source(.hls, "TranscodeReasons=VideoCodecNotSupported").reencodesVideo)
        #expect(source(.hls, "TranscodeReasons=ContainerNotSupported,ContainerBitrateExceedsLimit").reencodesVideo)
    }
}
