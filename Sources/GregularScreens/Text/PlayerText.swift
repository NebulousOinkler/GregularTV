import Foundation
import GregularCore

/// The player's words: what a deck is doing and the stream it's playing
/// (for "Show playback diagnostics"), and why a programme stopped.
public enum PlayerText {
    /// What a deck is doing, in a word or two: "Playing", or "Buffering"
    /// with why if the player says, and "in VLC" on the add-on player.
    public static func activity(_ activity: DeckActivity) -> String {
        let player = activity.onAddOn ? " in VLC" : ""
        switch activity.state {
        case .playing: return "Playing" + player
        case .paused: return "Paused"
        case .waiting: return "Buffering" + player + (activity.waitingFor.map { " (\(waiting($0)))" } ?? "")
        case nil: return "Unknown"
        }
    }

    private static func waiting(_ wait: DeckActivity.Wait) -> String {
        switch wait {
        case .opening: "opening"
        case .waitingForScreen: "waiting for the screen"
        case .fillingBuffer: "filling buffer"
        case .starting: "starting"
        case .measuringNetwork: "measuring network"
        case .nothingLoaded: "nothing loaded"
        case .networkStalled: "network stalled"
        case .other: "waiting"
        }
    }

    /// The stream playing: what chose its cap, the cap, and what the server
    /// does to it, such as "1080p · 10 Mbps · up to 10 Mbps · direct play".
    /// No cap says so, rather than naming the highest there is. A commercial
    /// says it is one: it plays at its programme's cap.
    /// - Parameter fixedForProgramme: a fix for this programme (or its
    ///   break) sets the cap, rather than `quality`.
    static func stream(quality: StreamingQuality, fixedForProgramme: Bool, isCommercial: Bool, cap: Int,
                       delivery: MediaStream.Delivery) -> String {
        let method = switch delivery {
        case .original: "direct play"
        case .repackaged: "repackaged by the server"
        case .soundConverted: "sound converted by the server"
        case .reencoded: "re-encoded by the server"
        }
        let label = fixedForProgramme ? "This programme only" : quality.label
        let limit = cap >= StreamingQuality.maximumBitrate ? "no cap" : "up to \(mbps(cap))"
        return (isCommercial ? "Commercial · " : "") + "\(label) · \(limit) · \(method)"
    }

    /// The diagnostics line: what the deck is doing, how far behind live,
    /// where it is, whether the server converts it and why, and how much of
    /// the next programme is buffered, if one is loading.
    static func diagnostics(activity: DeckActivity, secondsBehindLive: Double, position: Double,
                            conversionReasons: String?, nextBuffered: Double?) -> String {
        let live = secondsBehindLive.formatted(.number.precision(.fractionLength(1)))
        let at = Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond))
        let work = conversionReasons.map { "transcoding: \($0)" } ?? "no transcoding"
        let buffered = nextBuffered.map { " · next programme: \(Int($0)) s buffered" } ?? ""
        return "\(self.activity(activity)) · \(live) s behind live · at \(at) · \(work)\(buffered)"
    }

    /// Bits per second, as "10 Mbps" or "1.5 Mbps".
    static func mbps(_ bitsPerSecond: Int) -> String {
        (Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + " Mbps"
    }

    /// A programme that stopped for a reason that isn't its format or the connection.
    static let stopped = "This programme stopped playing."

    /// A programme whose format `device` couldn't decode.
    static func unplayable(on device: String) -> String {
        "This programme couldn't be played. It may be in a format \(device) can't show."
    }

    /// Devices, as "a format … can't show" names them.
    public static let appleTV = "Apple TV"
    public static let thisBrowser = "this browser"
}
