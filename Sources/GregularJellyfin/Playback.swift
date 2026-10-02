import Foundation
import GregularCore

/// A URL that AVPlayer can play for one item.
///
/// The player always seeks to the live offset itself. Jellyfin's HLS
/// transcoder restarts at whichever segment the player asks for, so seeking
/// works for both methods.
public struct PlaybackSource: Sendable, Equatable {
    public enum Method: Sendable, Equatable {
        /// The original file, played as-is.
        case directPlay
        /// HLS from Jellyfin: a remux, or a full transcode for formats Apple TV can't play.
        case hls
    }

    public let url: URL
    public let method: Method
    /// Pass to `JellyfinClient.stopTranscoding` when leaving this item, so
    /// the server stops the transcode straight away rather than timing it out.
    public let playSessionID: String?

    public init(url: URL, method: Method, playSessionID: String?) {
        self.url = url
        self.method = method
        self.playSessionID = playSessionID
    }

    /// Why Jellyfin is sending HLS rather than the original file, from the
    /// stream URL. Empty for direct play.
    public var transcodeReasons: [String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "TranscodeReasons" }?.value?
            .split(separator: ",").map(String.init) ?? []
    }

    /// True when the server has to re-encode the video, the expensive kind of
    /// transcode. Changing only the container (a remux) or the audio is cheap.
    public var reencodesVideo: Bool {
        guard method == .hls else { return false }
        return transcodeReasons.contains { $0 != "ContainerNotSupported" && !$0.hasPrefix("Audio") }
    }

    /// "SubtitleCodecNotSupported" → "subtitle codec not supported".
    static func plainWords(_ reason: String) -> String {
        reason.reduce(into: "") { text, character in
            if character.isUppercase, !text.isEmpty { text.append(" ") }
            text.append(character.lowercased())
        }
    }

    /// The same stream, as the schedule's player sees it. Only an HLS
    /// session has a transcode for `StreamSource.release(_:)` to stop.
    public var mediaStream: MediaStream {
        MediaStream(url: url,
                    delivery: method == .directPlay ? .original : .converted,
                    reencodes: reencodesVideo,
                    conversionReasons: transcodeReasons.map(Self.plainWords),
                    sessionID: method == .hls ? playSessionID : nil)
    }
}

/// What Apple TV can play natively. Jellyfin uses this to decide between
/// direct play and transcoding.
struct DeviceProfile: Encodable {
    struct DirectPlayProfile: Encodable {
        let container: String
        let type = "Video"
        let videoCodec: String
        let audioCodec: String
    }

    struct TranscodingProfile: Encodable {
        let container = "mp4"           // fMP4 HLS, which carries HEVC as well as H.264
        let type = "Video"
        /// Either is copied as it is. When the video has to be re-encoded,
        /// Jellyfin makes the first: H.264, far less work for a small server
        /// (a Raspberry Pi can't make HEVC in real time).
        let videoCodec = "h264,hevc"
        let audioCodec = "aac,ac3,eac3"
        let `protocol` = "hls"
        let context = "Streaming"
        let maxAudioChannels = "6"
        let minSegments = 2
        let breakOnNonKeyFrames = true
    }

    struct SubtitleProfile: Encodable {
        let format: String
        let method = "External"
    }

    let name = "Gregular TV (tvOS)"
    let maxStreamingBitrate: Int
    let maxStaticBitrate: Int
    let directPlayProfiles = [
        DirectPlayProfile(container: "mp4,m4v,mov", videoCodec: "hevc,h264", audioCodec: "aac,ac3,eac3,alac,mp3"),
    ]
    let transcodingProfiles = [TranscodingProfile()]
    /// Every subtitle format is declared as "External", meaning the client
    /// fetches it separately. The app never does, so no subtitles show, and
    /// Jellyfin has no reason to *burn* them into the video. Burning in
    /// forces a full video transcode ("SubtitleCodecNotSupported"), which a
    /// Raspberry Pi can't do in real time. A second line of defence behind
    /// `PlaybackInfoRequest.subtitleStreamIndex`: a format missing from this
    /// list would still be burned in if a subtitle track were chosen.
    let subtitleProfiles = [
        "srt", "subrip", "ass", "ssa", "vtt", "webvtt", "sub", "smi", "ttml", "mov_text",
        "pgs", "pgssub", "dvdsub", "dvbsub", "vobsub", "idx",
    ].map { SubtitleProfile(format: $0) }

    /// `maxBitrate` is the quality cap. A file over it can't be played
    /// directly, and transcodes are limited to it.
    init(maxBitrate: Int) {
        maxStreamingBitrate = maxBitrate
        maxStaticBitrate = maxBitrate
    }
}

// MARK: - DTOs

struct PlaybackInfoRequest: Encodable {
    let userId: String
    let deviceProfile: DeviceProfile
    let maxStreamingBitrate: Int
    let enableDirectPlay = true
    let enableDirectStream = true
    let enableTranscoding = true
    let allowVideoStreamCopy = true
    let allowAudioStreamCopy = true
    let autoOpenLiveStream = false
    /// The item's own media source, which has the item's ID. Jellyfin only
    /// honours `subtitleStreamIndex` for a request that names its media source.
    let mediaSourceId: String
    /// -1 means "no subtitles". Without it (or without `mediaSourceId`),
    /// Jellyfin picks the file's default subtitle track and may burn it into
    /// the video. That forces a full video transcode, which low-power servers
    /// such as a Raspberry Pi can't sustain.
    let subtitleStreamIndex = -1

    init(itemID: String, userId: String, maxBitrate: Int) {
        mediaSourceId = itemID
        self.userId = userId
        deviceProfile = DeviceProfile(maxBitrate: maxBitrate)
        maxStreamingBitrate = maxBitrate
    }
}

struct PlaybackInfoResponse: Decodable {
    struct MediaSource: Decodable {
        let id: String
        let container: String?
        let supportsDirectPlay: Bool
        let transcodingUrl: String?
    }

    let mediaSources: [MediaSource]
    let playSessionId: String?
}
