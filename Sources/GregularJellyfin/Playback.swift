import Foundation
import GregularCore

/// A URL the platform's player can play for one item.
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
    /// The device's own player, or the add-on player it has (VLC on Apple TV).
    public let player: MediaStream.Player
    /// Pass to `JellyfinClient.stopTranscoding` when leaving this item, so
    /// the server stops the transcode straight away rather than timing it out.
    public let playSessionID: String?
    /// The file's own video and sound, as Jellyfin describes them.
    public let source: StreamContents

    public init(url: URL, method: Method, player: MediaStream.Player = .builtIn, playSessionID: String?,
                source: StreamContents = StreamContents()) {
        self.url = url
        self.method = method
        self.player = player
        self.playSessionID = playSessionID
        self.source = source
    }

    /// Why Jellyfin is sending HLS rather than the original file, from the
    /// stream URL. Empty for direct play.
    public var transcodeReasons: [String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "TranscodeReasons" }?.value?
            .split(separator: ",").map(String.init) ?? []
    }

    /// How much work the server does, from Jellyfin's reasons: none for the
    /// original; the video re-encoded for any reason that isn't the
    /// container's or the sound's (the codec, the bitrate cap, burned-in
    /// subtitles); else the sound converted for a sound reason; else only
    /// the container changed (a stream with no reasons is taken as that).
    public var delivery: MediaStream.Delivery {
        guard method == .hls else { return .original }
        return convertsVideo ? .reencoded : convertsSound ? .soundConverted : .repackaged
    }

    /// Reasons that only change the container: the file's own, or a sound
    /// track other than its first, which a player plays only from a stream
    /// that carries that track alone (`DeviceProfile.CodecProfile.firstSoundTrackOnly`).
    private static let repackagingReasons: Set<String> = ["ContainerNotSupported", "SecondaryAudioNotSupported"]

    /// The video is re-encoded: a reason that isn't the container's or the sound's.
    private var convertsVideo: Bool {
        method == .hls && transcodeReasons.contains { !Self.repackagingReasons.contains($0) && !Self.isSoundReason($0) }
    }

    /// The sound is converted.
    var convertsSound: Bool {
        method == .hls && transcodeReasons.contains(where: Self.isSoundReason)
    }

    /// Reasons that make a re-encode among the heaviest: tone mapping HDR to
    /// SDR, 10-bit to 8-bit, and deinterlacing (`MediaStream.isHeavyReencode`).
    private static let heavyReasons: Set<String> = ["VideoRangeTypeNotSupported", "VideoBitDepthNotSupported",
                                                    "InterlacedVideoNotSupported"]

    /// The video is re-encoded, and among the heaviest re-encodes.
    var isHeavyReencode: Bool {
        convertsVideo && transcodeReasons.contains(where: Self.heavyReasons.contains)
    }

    private static func isSoundReason(_ reason: String) -> Bool {
        reason.hasPrefix("Audio") || reason == "UnknownAudioStreamInfo"
    }

    /// What reaches the player: the file's own video and sound, except what's
    /// converted, which is the first codec the conversion may make (the one
    /// Jellyfin makes, as `TranscodingProfile` lists them).
    public var contents: StreamContents {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let first = { (name: String) in
            query.first { $0.name == name }?.value?.split(separator: ",").first.map(String.init)
        }
        return StreamContents(video: convertsVideo ? first("VideoCodec").map { MediaFormat(.video, $0) } : source.video,
                              sound: convertsSound ? first("AudioCodec").map { MediaFormat(.sound, $0) } : source.sound)
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
                    delivery: delivery,
                    player: player,
                    conversionReasons: transcodeReasons.map(Self.plainWords),
                    sessionID: method == .hls ? playSessionID : nil,
                    contents: contents,
                    isHeavyReencode: isHeavyReencode)
    }
}

/// What this device can play (`PlayableFormats`), as Jellyfin asks for it.
/// Jellyfin uses this to decide between direct play and transcoding.
struct DeviceProfile: Encodable {
    struct DirectPlayProfile: Encodable {
        /// Nil for any container.
        let container: String?
        /// "Video", or "Audio" for sound files.
        let type: String
        let videoCodec: String?
        let audioCodec: String
    }

    struct TranscodingProfile: Encodable {
        var container = "mp4"           // fMP4 HLS, which carries HEVC as well as H.264
        var type = "Video"
        /// Copied as it is when the video already is one of these; made as
        /// the first when it has to be re-encoded.
        var videoCodec: String?
        let audioCodec: String
        var `protocol` = "hls"
        var context = "Streaming"
        let maxAudioChannels: String
        var minSegments: Int? = 2
        var breakOnNonKeyFrames: Bool? = true

        /// A song's sound converted into one file in `codec` (in a container
        /// of the same name, such as raw AAC), made as it's fetched, to fetch
        /// whole (`JellyfinClient.wholeFileURL(of:)`). Stereo is plenty.
        static func song(_ codec: String) -> TranscodingProfile {
            TranscodingProfile(container: codec, type: "Audio", videoCodec: nil, audioCodec: codec, protocol: "http",
                               context: "Static", maxAudioChannels: "2", minSegments: nil, breakOnNonKeyFrames: nil)
        }
    }

    /// What a file must be, beyond its codecs' names, to play as it is (or
    /// be copied into a stream).
    struct CodecProfile: Encodable {
        struct Condition: Encodable {
            var condition = "EqualsAny"
            /// Such as "VideoProfile" or "VideoCodecTag".
            let property: String
            /// The values allowed, separated by "|".
            let value: String
            /// A file whose value isn't known passes.
            let isRequired = false
        }

        /// "Video", or "VideoAudio" for a video file's sound.
        var type = "Video"
        /// Nil for every codec.
        var codec: String?
        let conditions: [Condition]

        /// `PlayableFormats.CodecLimit`: one video codec's profiles and tags.
        init(_ limit: PlayableFormats.CodecLimit) {
            codec = limit.codec
            conditions = [limit.profiles.map { Condition(property: "VideoProfile", value: $0.joined(separator: "|")) },
                          limit.tags.map { Condition(property: "VideoCodecTag", value: $0.joined(separator: "|")) }]
                .compactMap { $0 }
        }

        private init(type: String, conditions: [Condition]) {
            self.type = type
            self.conditions = conditions
        }

        /// A file plays as it is only with its first sound track: a player
        /// plays the file's own choice of track, so a stream asked for with
        /// another (`PlaybackInfoRequest.audioStreamIndex`) comes repackaged,
        /// carrying that track alone. Jellyfin's web app says the same for
        /// browsers that can't switch tracks.
        static let firstSoundTrackOnly = CodecProfile(
            type: "VideoAudio", conditions: [Condition(condition: "Equals", property: "IsSecondaryAudio", value: "false")])
    }

    struct SubtitleProfile: Encodable {
        let format: String
        let method = "External"
    }

    let name: String
    let maxStreamingBitrate: Int
    let maxStaticBitrate: Int
    let directPlayProfiles: [DirectPlayProfile]
    let transcodingProfiles: [TranscodingProfile]
    let codecProfiles: [CodecProfile]
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
    /// - Parameters:
    ///   - secure: the server is on https.
    ///   - choosingSoundTrack: the request names a sound track
    ///     (`CodecProfile.firstSoundTrackOnly`).
    init(formats: PlayableFormats, maxBitrate: Int, secure: Bool, choosingSoundTrack: Bool = false) {
        name = "\(ClientIdentity.clientName) (\(formats.name))"
        maxStreamingBitrate = maxBitrate
        maxStaticBitrate = maxBitrate
        let containers = formats.containers.isEmpty ? nil : formats.containers.joined(separator: ",")
        let video = DirectPlayProfile(container: containers, type: "Video",
                                      videoCodec: formats.videoCodecs.joined(separator: ","),
                                      audioCodec: formats.audioCodecs.joined(separator: ","))
        let audio = DirectPlayProfile(container: formats.audioFileContainers.joined(separator: ","), type: "Audio",
                                      videoCodec: nil, audioCodec: formats.audioFileCodecs.joined(separator: ","))
        directPlayProfiles = formats.playsFilesOnlyOverHTTPS && !secure ? [] : [video] + (formats.audioFileContainers.isEmpty ? [] : [audio])
        transcodingProfiles = [TranscodingProfile(videoCodec: formats.convertedVideoCodecs.joined(separator: ","),
                                                  audioCodec: formats.convertedAudioCodecs.joined(separator: ","),
                                                  maxAudioChannels: String(formats.mostAudioChannels))]
            + (formats.audioFileContainers.isEmpty ? [] : formats.convertedAudioCodecs.prefix(1).map(TranscodingProfile.song))
        codecProfiles = formats.codecLimits.map(CodecProfile.init) + (choosingSoundTrack ? [.firstSoundTrackOnly] : [])
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
    /// The sound track to play, by its index in the file; nil for Jellyfin's
    /// own choice (`MediaSource.defaultAudioStreamIndex`).
    let audioStreamIndex: Int?

    init(itemID: String, userId: String, formats: PlayableFormats, maxBitrate: Int, secure: Bool, soundTrack: Int? = nil) {
        mediaSourceId = itemID
        self.userId = userId
        deviceProfile = DeviceProfile(formats: formats, maxBitrate: maxBitrate, secure: secure, choosingSoundTrack: soundTrack != nil)
        maxStreamingBitrate = maxBitrate
        audioStreamIndex = soundTrack
    }
}

struct PlaybackInfoResponse: Decodable {
    struct MediaSource: Decodable {
        let id: String
        let container: String?
        let supportsDirectPlay: Bool
        let transcodingUrl: String?
        let mediaStreams: [Stream]?
        /// The sound track Jellyfin plays when none is named: the file's
        /// default, or the one in the language the user prefers.
        let defaultAudioStreamIndex: Int?

        /// One of the file's tracks: what says whether a player can decode
        /// it, and for a sound track, what it's in (its language, and its
        /// name, which says if it's a commentary), to choose one like Jellyfin's own.
        struct Stream: Decodable {
            let type: String?
            let index: Int?
            let codec: String?
            let profile: String?
            let isDefault: Bool?
            let channels: Int?
            let language: String?
            let title: String?

            /// Its language, with "und" (undetermined) as none.
            var languageCode: String {
                let code = language?.lowercased() ?? ""
                return code == "und" ? "" : code
            }

            /// A commentary or a description for the blind, by its name:
            /// never a substitute for the programme's own sound.
            var isAside: Bool {
                let name = title?.lowercased() ?? ""
                return name.contains("commentary") || name.contains("descri")
            }
        }

        private var soundTracks: [Stream] { (mediaStreams ?? []).filter { $0.type == "Audio" } }

        /// The sound track Jellyfin plays when none is named: by its index,
        /// else the file's default, else its first.
        var defaultSoundTrack: Stream? {
            soundTracks.first { $0.index != nil && $0.index == defaultAudioStreamIndex }
                ?? soundTracks.first { $0.isDefault == true } ?? soundTracks.first
        }

        /// The file's video, and the sound track that plays: `soundTrack`
        /// (by index), or else Jellyfin's own choice.
        func contents(soundTrack: Int? = nil) -> StreamContents {
            let video = mediaStreams?.first { $0.type == "Video" }
            let sound = soundTracks.first { soundTrack != nil && $0.index == soundTrack } ?? defaultSoundTrack
            return StreamContents(video: video?.codec.map { MediaFormat(.video, $0, profile: video?.profile) },
                                  sound: sound?.codec.map { MediaFormat(.sound, $0) })
        }

        /// Another sound track a conversion for `formats` copies as it is,
        /// where Jellyfin's own choice it would convert: in the same
        /// language, not an aside, with no more channels than a conversion
        /// keeps; the one with the most channels, then the first. Nil if there's none.
        func soundTrackToCopy(into formats: PlayableFormats) -> Int? {
            guard let chosen = defaultSoundTrack else { return nil }
            let copies = { (track: Stream) in
                track.codec.map { formats.convertedAudioCodecs.contains($0.lowercased()) } == true
                    && (track.channels ?? .max) <= formats.mostAudioChannels
            }
            guard !copies(chosen) else { return nil }
            return soundTracks
                .filter { $0.index != nil && $0.index != chosen.index && $0.languageCode == chosen.languageCode && !$0.isAside && copies($0) }
                .max { ($0.channels ?? 0, -$0.index!) < ($1.channels ?? 0, -$1.index!) }?.index
        }
    }

    let mediaSources: [MediaSource]
    let playSessionId: String?
}

/// `/Audio/{id}/Lyrics`: the lyrics Jellyfin read from the song's lyrics
/// file (such as an .lrc), with times in ticks.
struct LyricsDTO: Decodable {
    struct Line: Decodable {
        let text: String?
        let start: Int64?
        /// Each word's timing (Jellyfin 10.10 and later), by its place in `text`.
        let cues: [Cue]?
    }

    struct Cue: Decodable {
        /// Where the word starts and ends in the line's text, in UTF-16 units (as .NET counts).
        let position: Int?
        let endPosition: Int?
        let start: Int64?
        let end: Int64?
    }

    let lyrics: [Line]?

    /// The timed lines, or nil if there are none (no lyrics, or untimed words).
    var synced: SyncedLyrics? {
        let lines: [SyncedLyrics.Line] = (lyrics ?? []).compactMap { line in
            guard let start = line.start else { return nil }
            let text = line.text ?? ""
            return SyncedLyrics.Line(start: Ticks.seconds(start), text: text, words: Self.words(line.cues ?? [], in: text))
        }
        return lines.isEmpty ? nil : SyncedLyrics(lines: lines)
    }

    /// The cues as words, by character. A cue with no end runs to the next one, or the end of the line.
    private static func words(_ cues: [Cue], in text: String) -> [SyncedLyrics.Word] {
        let utf16Count = text.utf16.count
        let timed = cues.filter { $0.start != nil && $0.position != nil }.sorted { $0.position! < $1.position! }
        return timed.enumerated().compactMap { index, cue in
            let from = min(max(cue.position!, 0), utf16Count)
            let to = min(max(cue.endPosition ?? (index + 1 < timed.count ? timed[index + 1].position! : utf16Count), from), utf16Count)
            let range = characters(upTo: from, in: text)..<characters(upTo: to, in: text)
            guard !range.isEmpty else { return nil }
            return SyncedLyrics.Word(range: range, start: Ticks.seconds(cue.start!), end: cue.end.map(Ticks.seconds))
        }
    }

    /// How many characters start in the first `utf16Offset` UTF-16 units of `text`.
    private static func characters(upTo utf16Offset: Int, in text: String) -> Int {
        var units = 0, count = 0
        for character in text where units < utf16Offset {
            units += character.utf16.count
            count += 1
        }
        return count
    }
}
