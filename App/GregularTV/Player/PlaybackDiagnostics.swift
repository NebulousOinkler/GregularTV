import AVFoundation

/// A readable snapshot of what the player is doing, shown in the info banner
/// when "Show playback diagnostics" is on in Settings.
///
/// It holds only playback state. No server address, token, user or file
/// details: stream URLs are never shown anywhere.
struct PlaybackDiagnostics: Equatable {
    var state: String
    var behindLive: TimeInterval
    var position: TimeInterval
    /// Jellyfin's reasons for transcoding, made readable, or nil if it isn't transcoding.
    var transcoding: String?
    /// During a break, seconds of the next programme buffered so far.
    var preloaded: TimeInterval?

    init(player: AVPlayer, behindLive: TimeInterval, transcodeReasons: String?, preloaded: AVPlayerItem? = nil) {
        switch player.timeControlStatus {
        case .playing:
            state = "Playing"
        case .paused:
            state = "Paused"
        case .waitingToPlayAtSpecifiedRate:
            state = "Buffering" + (player.reasonForWaitingToPlay.map { " (\(Self.describe($0)))" } ?? "")
        @unknown default:
            state = "Unknown"
        }
        self.behindLive = behindLive
        position = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
        transcoding = transcodeReasons.map(Self.readable)
        self.preloaded = preloaded.map { item in
            item.loadedTimeRanges.map(\.timeRangeValue.duration.seconds).filter(\.isFinite).reduce(0, +)
        }
    }

    var text: String {
        let live = behindLive.formatted(.number.precision(.fractionLength(1)))
        let at = Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond))
        let work = transcoding.map { "transcoding: \($0)" } ?? "no transcoding"
        let next = preloaded.map { " · next programme: \(Int($0)) s buffered" } ?? ""
        return "\(state) · \(live) s behind live · at \(at) · \(work)\(next)"
    }

    private static func describe(_ reason: AVPlayer.WaitingReason) -> String {
        switch reason {
        case .toMinimizeStalls: "filling buffer"
        case .evaluatingBufferingRate: "measuring network"
        case .noItemToPlay: "nothing loaded"
        default: "waiting"
        }
    }

    /// "ContainerNotSupported,SubtitleCodecNotSupported" → "container not supported, subtitle codec not supported".
    private static func readable(_ reasons: String) -> String {
        reasons.split(separator: ",").map { reason in
            reason.reduce(into: "") { text, character in
                if character.isUppercase, !text.isEmpty { text.append(" ") }
                text.append(character.lowercased())
            }
        }.joined(separator: ", ")
    }
}
