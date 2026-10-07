/// What a device's player can play, in the names media servers use. A
/// server sends a file that fits as it is, and converts anything else into
/// a stream made of `convertedVideoCodecs` and `convertedAudioCodecs`.
public struct PlayableFormats: Sendable, Equatable {
    /// Shown in the server's logs, such as "tvOS".
    public let name: String
    /// What a file must be to play as it is.
    public let containers: [String]
    public let videoCodecs: [String]
    public let audioCodecs: [String]
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
    /// known: only the server can say for sure (`OriginalFiles`).
    public func mightPlayAsIs(_ kind: MediaItem.Kind, container: String?) -> Bool {
        guard let container else { return true }
        let playable = kind == .song ? audioFileContainers : containers
        return container.lowercased().split(separator: ",").contains { playable.contains(String($0)) }
    }

    public init(name: String, containers: [String], videoCodecs: [String], audioCodecs: [String],
                convertedVideoCodecs: [String], convertedAudioCodecs: [String], mostAudioChannels: Int,
                audioFileContainers: [String] = [], audioFileCodecs: [String] = [], playsFilesOnlyOverHTTPS: Bool = false) {
        self.name = name
        self.containers = containers
        self.videoCodecs = videoCodecs
        self.audioCodecs = audioCodecs
        self.convertedVideoCodecs = convertedVideoCodecs
        self.convertedAudioCodecs = convertedAudioCodecs
        self.mostAudioChannels = mostAudioChannels
        self.audioFileContainers = audioFileContainers
        self.audioFileCodecs = audioFileCodecs
        self.playsFilesOnlyOverHTTPS = playsFilesOnlyOverHTTPS
    }

    /// Apple TV. A re-encode makes H.264, far less work for a small server
    /// than HEVC (a Raspberry Pi can't make HEVC in real time); HEVC is
    /// only ever copied as it is.
    public static let appleTV = PlayableFormats(
        name: "tvOS",
        containers: ["mp4", "m4v", "mov"],
        videoCodecs: ["hevc", "h264"],
        audioCodecs: ["aac", "ac3", "eac3", "alac", "mp3"],
        convertedVideoCodecs: ["h264", "hevc"],
        convertedAudioCodecs: ["aac", "ac3", "eac3"],
        mostAudioChannels: 6,
        audioFileContainers: ["mp3", "m4a", "mp4", "aac", "flac", "wav"],
        audioFileCodecs: ["mp3", "aac", "alac", "flac", "pcm_s16le", "pcm_s24le"])

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
