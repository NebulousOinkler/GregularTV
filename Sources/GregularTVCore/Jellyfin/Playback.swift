import Foundation

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
        let videoCodec = "hevc,h264"
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
    /// Jellyfin never has a reason to *burn* them into the video. Burning in
    /// forces a full video transcode ("SubtitleCodecNotSupported"), which a
    /// Raspberry Pi can't do in real time. Jellyfin 10.11 ignored
    /// `SubtitleStreamIndex=-1` on its own; this makes it reliable.
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
    /// -1 means "no subtitles". Otherwise Jellyfin picks the file's default
    /// subtitle track and burns it into the video. That forces a full video
    /// transcode, which low-power servers such as a Raspberry Pi can't sustain.
    let subtitleStreamIndex = -1

    init(userId: String, maxBitrate: Int) {
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
