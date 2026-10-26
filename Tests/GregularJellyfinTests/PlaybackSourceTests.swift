import Foundation
import GregularCore
import Testing
@testable import GregularJellyfin

/// What Jellyfin's stream URL says about the work it's doing.
struct PlaybackSourceTests {
    private func source(_ method: PlaybackSource.Method, _ query: String) -> PlaybackSource {
        PlaybackSource(url: URL(string: "https://tv.invalid/videos/x/master.m3u8?\(query)")!, method: method, playSessionID: nil)
    }

    /// The original; only the container; the sound; the video, for any other reason.
    @Test func theReasonsSayHowMuchWorkItIs() {
        let deliveries: [(PlaybackSource.Method, String, MediaStream.Delivery)] = [
            (.directPlay, "", .original),
            (.hls, "", .repackaged),
            (.hls, "TranscodeReasons=ContainerNotSupported", .repackaged),
            (.hls, "TranscodeReasons=ContainerNotSupported,SecondaryAudioNotSupported", .repackaged),
            (.hls, "TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported", .soundConverted),
            (.hls, "TranscodeReasons=AudioChannelsNotSupported", .soundConverted),
            (.hls, "TranscodeReasons=UnknownAudioStreamInfo", .soundConverted),
            (.hls, "TranscodeReasons=VideoCodecNotSupported", .reencoded),
            (.hls, "TranscodeReasons=AudioCodecNotSupported,VideoBitDepthNotSupported", .reencoded),
            (.hls, "TranscodeReasons=ContainerNotSupported,ContainerBitrateExceedsLimit", .reencoded),
            (.hls, "TranscodeReasons=SubtitleCodecNotSupported", .reencoded),
        ]
        for (method, query, delivery) in deliveries {
            let source = source(method, query)
            #expect(source.delivery == delivery, "\(query)")
            #expect(source.mediaStream.delivery == delivery && source.mediaStream.reencodes == (delivery == .reencoded))
        }
    }

    /// Tone mapping, 10-bit to 8-bit and deinterlacing make the heaviest re-encodes.
    @Test func theHeaviestReencodesAreToldApart() {
        let heavy: [(PlaybackSource.Method, String, Bool)] = [
            (.hls, "TranscodeReasons=VideoRangeTypeNotSupported", true),
            (.hls, "TranscodeReasons=ContainerNotSupported,VideoBitDepthNotSupported", true),
            (.hls, "TranscodeReasons=InterlacedVideoNotSupported", true),
            (.hls, "TranscodeReasons=VideoCodecNotSupported", false),
            (.hls, "TranscodeReasons=ContainerBitrateExceedsLimit", false),
            (.hls, "TranscodeReasons=AudioCodecNotSupported", false),
            (.directPlay, "TranscodeReasons=VideoRangeTypeNotSupported", false),
        ]
        for (method, query, isHeavy) in heavy {
            #expect(source(method, query).mediaStream.isHeavyReencode == isHeavy, "\(query)")
        }
    }
}
