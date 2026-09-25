import AVFoundation
import GregularScreens

/// `PlayerDeck` on Apple TV: an `AVQueuePlayer`, shown by `VideoSurface`.
/// Everything `ChannelPlayer` does to video goes through here.
@MainActor final class AVPlayerDeck: PlayerDeck {
    let player = AVQueuePlayer()

    /// The two decks a `ChannelPlayer` plays on.
    static func pair() -> [any PlayerDeck] { [AVPlayerDeck(), AVPlayerDeck()] }

    func makeItem(url: URL, from start: TimeInterval, to end: TimeInterval,
                  bufferAhead: TimeInterval?) -> any PlayerItem {
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        // Starts partway in, even when it's queued and starts by itself.
        // (No completion handler: that's allowed before the item is ready.)
        if start > 0 {
            item.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                      toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600),
                      completionHandler: nil)
        }
        if let bufferAhead { item.preferredForwardBufferDuration = bufferAhead }
        return Item(item)
    }

    var currentItem: (any PlayerItem)? {
        player.currentItem.flatMap(Item.wrapping)
    }

    func contains(_ item: any PlayerItem) -> Bool {
        guard let item = item as? Item else { return false }
        return player.items().contains { $0 === item.avItem }
    }

    func append(_ item: any PlayerItem) {
        guard let item = item as? Item else { return }
        player.insert(item.avItem, after: player.items().last)
    }

    func removeAll() { player.removeAllItems() }
    func advance() { player.advanceToNextItem() }

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    var pausesAtItemEnd: Bool {
        get { player.actionAtItemEnd == .pause }
        set { player.actionAtItemEnd = newValue ? .pause : .advance }
    }

    var state: PlayerDeckState {
        switch player.timeControlStatus {
        case .playing: .playing
        case .waitingToPlayAtSpecifiedRate: .waiting
        default: .paused
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: TimeInterval) {
        let tolerance = CMTime(seconds: 2, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    var position: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // MARK: - Diagnostics

    /// Only playback state: no server address, token, user or file details.
    func diagnostics(behindLive: TimeInterval, conversionReasons: String?, preloaded: (any PlayerItem)?) -> String {
        let state = switch player.timeControlStatus {
        case .playing: "Playing"
        case .paused: "Paused"
        case .waitingToPlayAtSpecifiedRate:
            "Buffering" + (player.reasonForWaitingToPlay.map { " (\(Self.describe($0)))" } ?? "")
        @unknown default: "Unknown"
        }
        let live = behindLive.formatted(.number.precision(.fractionLength(1)))
        let at = Duration.seconds(position).formatted(.time(pattern: .hourMinuteSecond))
        let work = conversionReasons.map { "transcoding: \(Self.readable($0))" } ?? "no transcoding"
        let buffered = (preloaded as? Item).map { item in
            item.avItem.loadedTimeRanges.map(\.timeRangeValue.duration.seconds).filter(\.isFinite).reduce(0, +)
        }
        let next = buffered.map { " · next programme: \(Int($0)) s buffered" } ?? ""
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

    // MARK: - Items

    /// An `AVPlayerItem` as a `PlayerItem`. The same wrapper is handed back
    /// for the same AVPlayerItem, so `===` works across calls.
    final class Item: PlayerItem {
        let avItem: AVPlayerItem
        private static let wrappers = NSMapTable<AVPlayerItem, Item>.weakToWeakObjects()

        init(_ avItem: AVPlayerItem) {
            self.avItem = avItem
            Self.wrappers.setObject(self, forKey: avItem)
        }

        static func wrapping(_ avItem: AVPlayerItem) -> Item {
            wrappers.object(forKey: avItem) ?? Item(avItem)
        }

        var hasFailed: Bool { avItem.status == .failed }

        /// AVFoundation's own errors are technical; say it plainly instead.
        var failure: (any Error)? {
            guard let error = avItem.error else { return nil }
            return (error as NSError).domain == AVFoundationErrorDomain ? UnplayableFormat() : error
        }

        var bufferedAhead: TimeInterval {
            let now = avItem.currentTime()
            return avItem.loadedTimeRanges.map(\.timeRangeValue)
                .first { $0.containsTime(now) }
                .map { ($0.end - now).seconds } ?? 0
        }
    }
}

/// A programme Apple TV couldn't play.
struct UnplayableFormat: LocalizedError {
    var errorDescription: String? {
        "This programme couldn't be played. It may be in a format Apple TV can't show."
    }
}
