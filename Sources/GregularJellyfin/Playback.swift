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

/// What this device can play (`PlayableFormats`), as Jellyfin asks for it.
/// Jellyfin uses this to decide between direct play and transcoding.
struct DeviceProfile: Encodable {
    struct DirectPlayProfile: Encodable {
        let container: String
        /// "Video", or "Audio" for sound files.
        let type: String
        let videoCodec: String?
        let audioCodec: String
    }

    struct TranscodingProfile: Encodable {
        let container = "mp4"           // fMP4 HLS, which carries HEVC as well as H.264
        let type = "Video"
        /// Copied as it is when the video already is one of these; made as
        /// the first when it has to be re-encoded.
        let videoCodec: String
        let audioCodec: String
        let `protocol` = "hls"
        let context = "Streaming"
        let maxAudioChannels: String
        let minSegments = 2
        let breakOnNonKeyFrames = true
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
    /// - Parameter secure: the server is on https.
    init(formats: PlayableFormats, maxBitrate: Int, secure: Bool) {
        name = "\(ClientIdentity.clientName) (\(formats.name))"
        maxStreamingBitrate = maxBitrate
        maxStaticBitrate = maxBitrate
        let video = DirectPlayProfile(container: formats.containers.joined(separator: ","), type: "Video",
                                      videoCodec: formats.videoCodecs.joined(separator: ","),
                                      audioCodec: formats.audioCodecs.joined(separator: ","))
        let audio = DirectPlayProfile(container: formats.audioFileContainers.joined(separator: ","), type: "Audio",
                                      videoCodec: nil, audioCodec: formats.audioFileCodecs.joined(separator: ","))
        directPlayProfiles = formats.playsFilesOnlyOverHTTPS && !secure ? [] : [video] + (formats.audioFileContainers.isEmpty ? [] : [audio])
        transcodingProfiles = [TranscodingProfile(videoCodec: formats.convertedVideoCodecs.joined(separator: ","),
                                                  audioCodec: formats.convertedAudioCodecs.joined(separator: ","),
                                                  maxAudioChannels: String(formats.mostAudioChannels))]
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

    init(itemID: String, userId: String, formats: PlayableFormats, maxBitrate: Int, secure: Bool) {
        mediaSourceId = itemID
        self.userId = userId
        deviceProfile = DeviceProfile(formats: formats, maxBitrate: maxBitrate, secure: secure)
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
