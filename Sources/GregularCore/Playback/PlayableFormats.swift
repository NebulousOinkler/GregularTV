/// What a device's player can play, in the names media servers use. A
/// server sends a file that fits as it is, and converts anything else into
/// a stream made of `convertedVideoCodecs` and `convertedAudioCodecs`.
public struct PlayableFormats: Sendable, Equatable {
    /// Shown in the server's logs, such as "tvOS".
    public private(set) var name: String
    /// What a file must be to play as it is. No containers means any.
    public private(set) var containers: [String]
    public private(set) var videoCodecs: [String]
    public private(set) var audioCodecs: [String]
    /// What `videoCodecs` must be beyond their names, where the player is
    /// fussier than the codec: a file outside these is converted.
    public private(set) var codecLimits: [CodecLimit]
    /// What a converted stream may carry, in order of preference: when the
    /// video has to be re-encoded, the server makes the first.
    public private(set) var convertedVideoCodecs: [String]
    public private(set) var convertedAudioCodecs: [String]
    /// More sound channels than this are mixed down.
    public private(set) var mostAudioChannels: Int
    /// What a sound file (a song) must be to play as it is.
    public private(set) var audioFileContainers: [String]
    public private(set) var audioFileCodecs: [String]
    /// Files play as they are only from an https server. A web page on
    /// https can't play a video file from plain http (mixed content); only
    /// requests it makes itself (HLS, through hls.js) can be let through to
    /// the home network. So from an http server everything comes as HLS:
    /// usually only the container changes, which is cheap for the server.
    public private(set) var playsFilesOnlyOverHTTPS: Bool

    /// Whether a file in `container` (as `MediaItem.container` names it) could
    /// play as it is, judged by the container alone. True when it isn't
    /// known, or the player takes any container: only the server can say
    /// for sure (`WholeFiles`).
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

        /// 8-bit H.264, which Apple TV and every browser decode: 10-bit (High 10),
        /// and the 4:2:2 and 4:4:4 profiles, are converted.
        public static let eightBitH264 = CodecLimit(codec: "h264", profiles: [
            "high", "main", "baseline", "constrained baseline", "progressive high", "constrained high",
        ])

        /// HEVC up to Main 10 (10-bit), under `tags` if given.
        public static func hevc(tags: [String]? = nil) -> CodecLimit {
            CodecLimit(codec: "hevc", profiles: ["main", "main 10"], tags: tags)
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

    /// The same, with sound the server converts mixed down to stereo, which
    /// is less work for it to make.
    public var withStereoSound: PlayableFormats {
        var formats = self
        formats.mostAudioChannels = min(2, mostAudioChannels)
        return formats
    }

    /// The same, without `unplayable` (formats the player turned out not to
    /// decode), as it plays them as they are and as a conversion copies them:
    /// a video profile comes off its codec's limit where it has one, or else
    /// the whole codec goes; a sound codec goes. So the server converts them.
    public func without(_ unplayable: Set<MediaFormat>) -> PlayableFormats {
        var formats = self
        for format in unplayable {
            switch format.kind {
            case .sound:
                formats.audioCodecs.removeAll { $0 == format.codec }
                formats.convertedAudioCodecs.removeAll { $0 == format.codec }
            case .video:
                if let profile = format.profile, let limit = formats.codecLimits.firstIndex(where: { $0.codec == format.codec }),
                   let kept = formats.codecLimits[limit].profiles?.filter({ $0 != profile }), !kept.isEmpty {
                    formats.codecLimits[limit] = CodecLimit(codec: format.codec, profiles: kept, tags: formats.codecLimits[limit].tags)
                    continue
                }
                formats.videoCodecs.removeAll { $0 == format.codec }
                formats.convertedVideoCodecs.removeAll { $0 == format.codec }
                formats.codecLimits.removeAll { $0.codec == format.codec }
            }
        }
        return formats
    }

    /// What a conversion ends up as: its first video and sound codecs, which
    /// the player is surest of. Never left out (`without(_:)` is only asked to).
    public var safestFormats: Set<MediaFormat> {
        Set([convertedVideoCodecs.first.map { MediaFormat(.video, $0) }, convertedAudioCodecs.first.map { MediaFormat(.sound, $0) }]
            .compactMap { $0 })
    }

    /// Apple TV's own player (AVFoundation). A re-encode makes H.264, far
    /// less work for a small server than HEVC (a Raspberry Pi can't make HEVC
    /// in real time); HEVC is only ever copied as it is. It can't decode
    /// 10-bit H.264, or HEVC beyond Main 10, and plays HEVC only tagged
    /// `hvc1` (or `dvh1`, Dolby Vision) in the file.
    ///
    /// FLAC plays as it is in a file, and a conversion keeps up to 7.1
    /// sound (decided 2026-10-26, A4; `AppleTVSoundTests`, in the
    /// simulator). FLAC isn't copied into a conversion: that's untested.
    public static let appleTV = PlayableFormats(
        name: "tvOS",
        containers: ["mp4", "m4v", "mov"],
        videoCodecs: ["hevc", "h264"],
        audioCodecs: ["aac", "ac3", "eac3", "alac", "mp3", "flac"],
        codecLimits: [.eightBitH264, .hevc(tags: ["hvc1", "dvh1"])],
        convertedVideoCodecs: ["h264", "hevc"],
        convertedAudioCodecs: ["aac", "ac3", "eac3"],
        mostAudioChannels: 8,
        audioFileContainers: ["mp3", "m4a", "mp4", "aac", "flac", "wav"],
        audioFileCodecs: ["mp3", "aac", "alac", "flac", "pcm_s16le", "pcm_s24le"])

    /// VLC on Apple TV, the fallback for a file Apple TV's own player can't
    /// play as it is: VLC plays it as it is (as Swiftfin's does), so the
    /// server only sends it, with no conversion. It's asked about first for
    /// a programme the viewer asks to play in VLC (Settings). Not AV1: no
    /// Apple TV decodes it in hardware.
    ///
    /// Only the containers and codecs a video library really holds. VLC
    /// reads whatever it's sent, and the rarer a format, the less its reader
    /// has been tested, so anything rarer is converted by the server for
    /// Apple TV's own player instead.
    public static let vlcOnAppleTV = PlayableFormats(
        name: "tvOS VLC",
        containers: ["mkv", "webm", "avi", "ts", "mpegts", "m2ts", "mp4", "m4v", "mov", "wmv", "asf", "mpeg", "mpg",
                     "vob", "flv", "ogv", "ogg", "3gp"],
        videoCodecs: ["h264", "hevc", "mpeg4", "mpeg2video", "mpeg1video", "vc1", "vp8", "vp9", "msmpeg4v3",
                      "wmv1", "wmv2", "wmv3", "mjpeg", "theora", "prores", "dv"],
        audioCodecs: ["aac", "ac3", "eac3", "alac", "flac", "mp3", "mp2", "mp1", "dts", "truehd", "opus", "vorbis",
                      "wmalossless", "wmapro", "wmav1", "wmav2", "pcm_alaw", "pcm_mulaw", "pcm_bluray", "pcm_dvd",
                      "pcm_s16be", "pcm_s16le", "pcm_s24be", "pcm_s24le", "pcm_u8"],
        convertedVideoCodecs: ["h264"],
        convertedAudioCodecs: ["aac"],
        mostAudioChannels: 8)

    /// The formats a browser may say it decodes beyond H.264 and AAC, which
    /// every browser plays: HEVC by profile, AV1, and the sound formats films
    /// carry. The app asks the browser about each (`GregularWeb`), and only
    /// what it confirms goes into `browser(alsoPlays:)`.
    public static let browserMayPlay: [MediaFormat] = [
        MediaFormat(.video, "hevc", profile: "main"), MediaFormat(.video, "hevc", profile: "main 10"), MediaFormat(.video, "av1"),
        MediaFormat(.sound, "ac3"), MediaFormat(.sound, "eac3"), MediaFormat(.sound, "opus"), MediaFormat(.sound, "flac"),
    ]

    /// A web browser: H.264 and AAC in MP4 play everywhere, but not 10-bit
    /// H.264, which no browser reliably decodes. Beyond those, only what the
    /// browser says it decodes (`alsoPlays`, from `browserMayPlay`): played
    /// as they are, and copied into a conversion as they are rather than
    /// converted. Converted sound has at most 6 channels where the browser
    /// plays a surround format (AC-3, E-AC-3), so surround copies as it is;
    /// otherwise it's mixed down to stereo, which every browser plays.
    public static func browser(alsoPlays: Set<MediaFormat>) -> PlayableFormats {
        let hevcProfiles = (["main", "main 10"] as [String]).filter { alsoPlays.contains(MediaFormat(.video, "hevc", profile: $0)) }
        let video = (hevcProfiles.isEmpty ? [] : ["hevc"]) + (alsoPlays.contains(MediaFormat(.video, "av1")) ? ["av1"] : [])
        let sound = ["ac3", "eac3", "opus", "flac"].filter { alsoPlays.contains(MediaFormat(.sound, $0)) }
        return PlayableFormats(
            name: "Web",
            containers: ["mp4", "m4v"],
            videoCodecs: ["h264"] + video,
            audioCodecs: ["aac", "mp3"] + sound,
            codecLimits: [.eightBitH264] + (hevcProfiles.isEmpty ? [] : [CodecLimit(codec: "hevc", profiles: hevcProfiles)]),
            convertedVideoCodecs: ["h264"] + video,
            convertedAudioCodecs: ["aac"] + sound,
            mostAudioChannels: sound.contains("ac3") || sound.contains("eac3") ? 6 : 2,
            audioFileContainers: ["mp3", "m4a", "mp4", "aac", "flac", "wav"],
            audioFileCodecs: ["mp3", "aac", "flac", "pcm_s16le"],
            playsFilesOnlyOverHTTPS: true)
    }
}
