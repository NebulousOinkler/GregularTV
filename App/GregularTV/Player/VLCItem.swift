import Foundation
import GregularScreens
import SwiftVLC

/// An item a `TVDeck` plays on VLC (`MediaStream.Player.fallback`): a file
/// Apple TV's own player can't play as it is, which VLC plays as it is, so
/// the server only sends the file.
///
/// It has a VLC player of its own. It opens, paused, as soon as its picture
/// is on screen (`DeckSurface`, even hidden behind another): VLC draws only
/// into a view it had when it started. Then it goes to where it starts and
/// buffers there, ready to play at once, as a queued AVFoundation item does.
/// The deck says whether it should be playing (`settle(playing:)`), many
/// times a second, and it follows: VLC acts on requests in its own time, so
/// they're made again until they've taken.
@MainActor final class VLCItem: Identifiable {
    let player = SwiftVLC.Player(instance: VLCItem.vlc)
    /// libVLC, set up once (`arguments`).
    ///
    /// Its https is Apple's (SwiftVLC's libVLC uses its SecureTransport
    /// module), so certificates are checked against the system's trust. It
    /// never asks the viewer anything: the app gives libVLC no dialog
    /// handler, so where VLC would ask whether to accept a certificate that
    /// fails, the answer is no and the stream fails, as the app's own
    /// requests do. (That libVLC has no Lua, so no scripts run on what it reads.)
    private static let vlc = (try? VLCInstance(arguments: arguments)) ?? .shared
    /// Its messages off: like the rest of the app, it logs nothing
    /// (`scripts/privacy-check.sh`). `VLCSetupTests` checks libVLC takes them.
    static let arguments = VLCInstance.defaultArguments + ["--quiet"]
    let url: URL
    /// Where it starts and stops, in seconds into the file.
    let start: TimeInterval
    let end: TimeInterval
    /// Why it can't play, if it can't.
    private(set) var failure: (any Error)?
    /// Its picture is on screen (perhaps hidden), so it can open.
    private var hasSurface = false
    private var isOpen = false
    private var isClosed = false
    /// Where it's been asked to go and hasn't yet: VLC can only go once the
    /// file is open. Until then this is where it says it is, as AVFoundation
    /// does, so the player doesn't think it's far behind live.
    private var pendingSeek: TimeInterval?
    /// It ran out of buffered video while playing, and hasn't refilled.
    private var rebuffering = false
    /// The sound level VLC was last given.
    private var appliedVolume: Float = 0

    /// Sound level, 0 to 1. Silent while it isn't the item playing.
    var volume: Float = 1

    /// Closer to its end than this counts as at its end.
    static let endTolerance: TimeInterval = 0.1
    /// Stopping further than this before its end is a dropped connection, not its end.
    static let earlyStop: TimeInterval = 5

    init(url: URL, from start: TimeInterval, to end: TimeInterval) {
        self.url = url
        self.start = start
        self.end = end
        pendingSeek = start > 0 ? start : nil
    }

    // MARK: - On screen

    /// Its picture is on screen: it can open now.
    func surfaceAppeared() {
        hasSurface = true
        open()
    }

    private func open() {
        guard hasSurface, !isOpen, !isClosed else { return }
        isOpen = true
        do {
            let media = try Media(url: url)
            media.addOption(":start-paused")
            // No subtitles, as everywhere else in the app (PLAN.md): VLC would
            // otherwise show a file's default track.
            media.addOption(":no-spu")
            try player.setAudioVolume(Volume(0))
            try player.play(media)
        } catch {
            failure = UnplayableFormat()
        }
    }

    /// It's done with: VLC stops, and lets go of the file.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        if isOpen { player.stop() }
    }

    // MARK: - Playing

    /// Plays, or holds paused, as the deck says. Called many times a second.
    func settle(playing: Bool) {
        guard isOpen, !isClosed, failure == nil else { return }
        if let target = pendingSeek, player.isSeekable {
            pendingSeek = nil
            try? player.seek(to: .milliseconds(Int64(target * 1000)))
        }
        let level = playing ? volume : 0
        if level != appliedVolume, (try? player.setAudioVolume(Volume(level))) != nil { appliedVolume = level }
        switch player.state {
        case .playing:
            if !playing { player.pause() }
            // Swiftfin's measure: under 90% is out, full again is back.
            if player.bufferFill < 0.9 { rebuffering = true } else if player.bufferFill >= 1 { rebuffering = false }
        case .paused:
            if playing, pendingSeek == nil { player.resume() }
        case .error:
            failure = UnplayableFormat()
        case .stopped where !isAtEnd:
            failure = DroppedConnection()
        default:
            break
        }
    }

    /// Goes to `seconds` into the file, once it's open.
    func seek(to seconds: TimeInterval) {
        guard player.isSeekable else {
            pendingSeek = seconds
            return
        }
        pendingSeek = nil
        try? player.seek(to: .milliseconds(Int64(seconds * 1000)))
    }

    /// Seconds into the file.
    var position: TimeInterval {
        pendingSeek ?? player.currentTime.seconds
    }

    /// It has played to where it stops, or to the end of the file a little
    /// before (a file a touch shorter than the server says).
    var isAtEnd: Bool {
        guard pendingSeek == nil else { return false }
        if position >= end - Self.endTolerance { return true }
        return player.didReachEnd && position >= end - Self.earlyStop
    }

    /// What it's doing while it's meant to be playing.
    var state: PlayerDeckState {
        switch player.state {
        case .playing: rebuffering || pendingSeek != nil ? .waiting : .playing
        case .error: .paused
        default: .waiting
        }
    }

    /// What it's waiting for, while it waits, in a word or two.
    var waitingReason: String? {
        switch player.state {
        case .idle, .opening: hasSurface ? "opening" : "waiting for the screen"
        case .buffering, .playing: "filling buffer"
        case .paused: "starting"
        default: nil
        }
    }

    /// The video's frame rate and size, once VLC knows them.
    var videoTrack: (frameRate: Double, width: Int, height: Int)? {
        guard let track = player.videoTracks.first(where: \.isSelected) ?? player.videoTracks.first,
              let frameRate = track.frameRate, frameRate > 0, let width = track.width, let height = track.height
        else { return nil }
        return (frameRate, width, height)
    }
}

/// VLC stopped well before the end: the connection to the server dropped.
struct DroppedConnection: LocalizedError {
    var errorDescription: String? {
        "The connection to the server dropped."
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
