/// What a device's player can play, in the names media servers use. A
/// server sends a file that fits as it is, and converts anything else into
/// a stream made of `convertedVideoCodecs` and `convertedAudioCodecs`.
public struct PlayableFormats: Sendable, Equatable {
    /// Shown in the server's logs, such as "tvOS".
    public let name: String
    /// What a file must be to play as it is. No containers means any.
    public let containers: [String]
    public let videoCodecs: [String]
    public let audioCodecs: [String]
    /// What `videoCodecs` must be beyond their names, where the player is
    /// fussier than the codec: a file outside these is converted.
    public let codecLimits: [CodecLimit]
    /// What a converted stream may carry, in order of preference: when the
    /// video has to be re-encoded, the server makes the first.
    public let convertedVideoCodecs: [String]
    public let convertedAudioCodecs: [String]
    /// More sound channels than this are mixed down.
    public let mostAudioChannels: Int
    /// What a sound file (a song) must be to play as it is.
    public let audioFileContainers: [String]
    public let audioFileCodecs: [String]
    /// Files play as they are only from an https server. A web page on
    /// https can't play a video file from plain http (mixed content); only
    /// requests it makes itself (HLS, through hls.js) can be let through to
    /// the home network. So from an http server everything comes as HLS:
    /// usually only the container changes, which is cheap for the server.
    public let playsFilesOnlyOverHTTPS: Bool

    /// Whether a file in `container` (as `MediaItem.container` names it) could
    /// play as it is, judged by the container alone. True when it isn't
    /// known, or the player takes any container: only the server can say
    /// for sure (`OriginalFiles`).
    public func mightPlayAsIs(_ kind: MediaItem.Kind, container: String?) -> Bool {
        let playable = kind == .song ? audioFileContainers : containers
        guard let container, !playable.isEmpty else { return true }
        return container.lowercased().split(separator: ",").contains { playable.contains(String($0)) }
    }

    /// The forms of one video codec a player plays as it is.
    public struct CodecLimit: Sendable, Equatable {
        public let codec: String
        /// Its profiles the player plays, such as "high", or nil for any.
        public let profiles: [String]?
        /// The tags (in the file) the player plays it under, such as "hvc1",
        /// or nil for any. A file with another tag is repackaged, not re-encoded.
        public let tags: [String]?

        public init(codec: String, profiles: [String]? = nil, tags: [String]? = nil) {
            self.codec = codec
            self.profiles = profiles
            self.tags = tags
        }
    }

    public init(name: String, containers: [String], videoCodecs: [String], audioCodecs: [String],
                codecLimits: [CodecLimit] = [],
                convertedVideoCodecs: [String], convertedAudioCodecs: [String], mostAudioChannels: Int,
                audioFileContainers: [String] = [], audioFileCodecs: [String] = [], playsFilesOnlyOverHTTPS: Bool = false) {
        self.name = name
        self.containers = containers
        self.videoCodecs = videoCodecs
        self.audioCodecs = audioCodecs
        self.codecLimits = codecLimits
        self.convertedVideoCodecs = convertedVideoCodecs
        self.convertedAudioCodecs = convertedAudioCodecs
        self.mostAudioChannels = mostAudioChannels
        self.audioFileContainers = audioFileContainers
        self.audioFileCodecs = audioFileCodecs
        self.playsFilesOnlyOverHTTPS = playsFilesOnlyOverHTTPS
    }

    /// Apple TV's own player (AVFoundation). A re-encode makes H.264, far
    /// less work for a small server than HEVC (a Raspberry Pi can't make HEVC
    /// in real time); HEVC is only ever copied as it is. It can't decode
    /// 10-bit H.264, or HEVC beyond Main 10, and plays HEVC only tagged
    /// `hvc1` (or `dvh1`, Dolby Vision) in the file.
    public static let appleTV = PlayableFormats(
        name: "tvOS",
        containers: ["mp4", "m4v", "mov"],
        videoCodecs: ["hevc", "h264"],
        audioCodecs: ["aac", "ac3", "eac3", "alac", "mp3"],
        codecLimits: [
            CodecLimit(codec: "h264", profiles: ["high", "main", "baseline", "constrained baseline",
                                                 "progressive high", "constrained high"]),
            CodecLimit(codec: "hevc", profiles: ["main", "main 10"], tags: ["hvc1", "dvh1"]),
        ],
        convertedVideoCodecs: ["h264", "hevc"],
        convertedAudioCodecs: ["aac", "ac3", "eac3"],
        mostAudioChannels: 6,
        audioFileContainers: ["mp3", "m4a", "mp4", "aac", "flac", "wav"],
        audioFileCodecs: ["mp3", "aac", "alac", "flac", "pcm_s16le", "pcm_s24le"])

    /// VLC on Apple TV, the fallback for a file Apple TV's own player can't
    /// play as it is: VLC plays almost any file as it is (as Swiftfin's
    /// does), so the server only sends it, with no conversion. Any
    /// container. Not AV1: no Apple TV decodes it in hardware.
    public static let vlcOnAppleTV = PlayableFormats(
        name: "tvOS VLC",
        containers: [],
        videoCodecs: ["h264", "hevc", "mpeg4", "mpeg2video", "mpeg1video", "vc1", "vp8", "vp9", "h263", "h261",
                      "msmpeg4v1", "msmpeg4v2", "msmpeg4v3", "wmv1", "wmv2", "wmv3", "mjpeg", "theora", "prores",
                      "dv", "dirac", "ffv1", "flv1"],
        audioCodecs: ["aac", "ac3", "eac3", "alac", "flac", "mp3", "mp2", "mp1", "dts", "opus", "vorbis",
                      "amr_nb", "amr_wb", "nellymoser", "speex", "wavpack", "wmalossless", "wmapro", "wmav1", "wmav2",
                      "pcm_alaw", "pcm_mulaw", "pcm_bluray", "pcm_dvd", "pcm_s16be", "pcm_s16le", "pcm_s24be",
                      "pcm_s24le", "pcm_u8"],
        convertedVideoCodecs: ["h264"],
        convertedAudioCodecs: ["aac"],
        mostAudioChannels: 8)

    /// A web browser: H.264 and AAC in MP4 play everywhere. HEVC only where
    /// the browser says it can (`playsHEVC`). Surround sound is mixed down
    /// to stereo, which every browser plays.
    public static func browser(playsHEVC: Bool) -> PlayableFormats {
        PlayableFormats(
            name: "Web",
            containers: ["mp4", "m4v"],
            videoCodecs: playsHEVC ? ["h264", "hevc"] : ["h264"],
            audioCodecs: ["aac", "mp3"],
            convertedVideoCodecs: playsHEVC ? ["h264", "hevc"] : ["h264"],
            convertedAudioCodecs: ["aac"],
            mostAudioChannels: 2,
            audioFileContainers: ["mp3", "m4a", "mp4", "aac", "flac", "wav"],
            audioFileCodecs: ["mp3", "aac", "flac", "pcm_s16le"],
            playsFilesOnlyOverHTTPS: true)
    }
}
