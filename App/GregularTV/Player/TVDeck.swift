import AVFoundation
import GregularCore
import GregularScreens
import Observation

/// `PlayerDeck` on Apple TV. Everything `ChannelPlayer` does to video goes
/// through here, and `DeckSurface` shows it.
///
/// Each item plays on the player its stream says (`MediaStream.Player`):
/// Apple TV's own, an `AVQueuePlayer`, or VLC (`VLCItem`) for a file only
/// VLC plays as it is. A VLC item has a VLC player of its own, so it opens
/// and buffers, paused, while the item before it plays, as a queued
/// AVFoundation item does.
///
/// The queue is the deck's own, in order, the first item current.
/// AVFoundation items also go into the `AVQueuePlayer`, in the same order,
/// and it goes from one straight on to the next by itself. Where the next
/// item is VLC's, or the deck is to hold on an item's last frame, the
/// `AVQueuePlayer` pauses at the end instead, and the deck moves on itself
/// (`settle()`), which a short heartbeat checks for.
@MainActor @Observable final class TVDeck: PlayerDeck {
    /// Plays the AVFoundation items, shown by `VideoSurface`.
    @ObservationIgnored let avPlayer = AVQueuePlayer()
    /// Everything queued, the current item first.
    private(set) var queue: [Item] = []
    /// play() was called and pause() hasn't been since.
    private var wantsToPlay = false
    /// The current item reached its end with `pausesAtItemEnd` on: it holds there.
    private var heldAtEnd = false
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    /// The two decks a `ChannelPlayer` plays on.
    static func pair() -> [any PlayerDeck] { [TVDeck(), TVDeck()] }

    init() {
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil,
                                                             queue: .main) { [weak self] note in
            guard let ended = (note.object as? AVPlayerItem).map(ObjectIdentifier.init) else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.queue.first { $0.avItem.map(ObjectIdentifier.init) == ended }?.reachedEnd = true
                self.settle()
            }
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.settle()
            }
        }
    }

    isolated deinit {
        heartbeat?.cancel()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    func makeItem(url: URL, on player: MediaStream.Player, from start: TimeInterval, to end: TimeInterval,
                  bufferAhead: TimeInterval?) -> any PlayerItem {
        switch player {
        case .builtIn:
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
            return Item(.av(item))
        case .fallback:
            return Item(.vlc(VLCItem(url: url, from: start, to: end)))
        }
    }

    var currentItem: (any PlayerItem)? { queue.first }

    func contains(_ item: any PlayerItem) -> Bool {
        queue.contains { $0 === item }
    }

    func append(_ item: any PlayerItem) {
        guard let item = item as? Item, !contains(item) else { return }
        queue.append(item)
        switch item.engine {
        case .av(let avItem): avPlayer.insert(avItem, after: avPlayer.items().last)
        case .vlc(let vlc): vlc.volume = volume
        }
        settle()
    }

    func removeAll() {
        avPlayer.removeAllItems()
        for item in queue { item.vlcItem?.close() }
        queue = []
        heldAtEnd = false
        settle()
    }

    func advance() {
        guard !queue.isEmpty else { return }
        let gone = queue.removeFirst()
        heldAtEnd = false
        switch gone.engine {
        case .av(let avItem):
            if avPlayer.currentItem === avItem { avPlayer.advanceToNextItem() } else { avPlayer.remove(avItem) }
        case .vlc(let vlc):
            vlc.close()
        }
        settle()
    }

    var pausesAtItemEnd = false {
        didSet { settle() }
    }

    var volume: Float = 1 {
        didSet {
            avPlayer.volume = volume
            for item in queue { item.vlcItem?.volume = volume }
        }
    }

    var state: PlayerDeckState {
        guard let current = queue.first else { return Self.state(of: avPlayer) }
        if heldAtEnd { return .paused }
        guard let vlc = current.vlcItem else { return Self.state(of: avPlayer) }
        return wantsToPlay ? vlc.state : .paused
    }

    func play() {
        wantsToPlay = true
        settle()
    }

    func pause() {
        wantsToPlay = false
        settle()
    }

    func seek(to seconds: TimeInterval) {
        guard let current = queue.first else { return }
        if seconds < current.end {
            current.reachedEnd = false
            heldAtEnd = false
        }
        switch current.engine {
        case .av:
            let tolerance = CMTime(seconds: 2, preferredTimescale: 600)
            avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                          toleranceBefore: tolerance, toleranceAfter: tolerance)
        case .vlc(let vlc):
            vlc.seek(to: seconds)
        }
        settle()
    }

    var position: TimeInterval {
        if let vlc = queue.first?.vlcItem { return vlc.position }
        let seconds = avPlayer.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    // MARK: - Keeping the players in step

    /// Brings both players into line with the queue: drops what
    /// AVFoundation has moved on from by itself, holds or moves on at the
    /// current item's end, sets whether AVFoundation goes on by itself, and
    /// plays the current item (if wanted) and nothing else.
    private func settle() {
        // AVFoundation went on to its next item by itself, or dropped one that failed.
        while let first = queue.first, let avItem = first.avItem, !avPlayer.items().contains(avItem), !first.hasFailed {
            queue.removeFirst()
            heldAtEnd = false
        }
        // At the end of the current item, unless AVFoundation is going on by itself.
        if let current = queue.first, !heldAtEnd, current.isAtEnd,
           current.avItem == nil || avPlayer.actionAtItemEnd != .advance {
            if pausesAtItemEnd {
                heldAtEnd = true
            } else {
                return advance()
            }
        }

        // AVFoundation goes on by itself only from one of its items to the next.
        let nextIsAV = queue.count > 1 && queue[0].avItem != nil && queue[1].avItem != nil
        avPlayer.actionAtItemEnd = nextIsAV && !pausesAtItemEnd ? .advance : .pause

        let plays = wantsToPlay && !heldAtEnd
        if let current = queue.first, current.avItem != nil, plays {
            if avPlayer.rate == 0 { avPlayer.play() }
        } else if avPlayer.rate != 0 {
            avPlayer.pause()
        }
        for (index, item) in queue.enumerated() {
            item.vlcItem?.settle(playing: index == 0 && plays)
        }
    }

    private static func state(of player: AVPlayer) -> PlayerDeckState {
        switch player.timeControlStatus {
        case .playing: .playing
        case .waitingToPlayAtSpecifiedRate: .waiting
        default: .paused
        }
    }

    // MARK: - Diagnostics

    var activity: String {
        if let vlc = queue.first?.vlcItem, !heldAtEnd {
            return switch state {
            case .playing: "Playing in VLC"
            case .paused: "Paused"
            case .waiting: "Buffering in VLC" + (vlc.waitingReason.map { " (\($0))" } ?? "")
            }
        }
        if heldAtEnd { return "Paused" }
        return switch avPlayer.timeControlStatus {
        case .playing: "Playing"
        case .paused: "Paused"
        case .waitingToPlayAtSpecifiedRate:
            "Buffering" + (avPlayer.reasonForWaitingToPlay.map { " (\(Self.describe($0)))" } ?? "")
        @unknown default: "Unknown"
        }
    }

    private static func describe(_ reason: AVPlayer.WaitingReason) -> String {
        switch reason {
        case .toMinimizeStalls: "filling buffer"
        case .evaluatingBufferingRate: "measuring network"
        case .noItemToPlay: "nothing loaded"
        default: "waiting"
        }
    }

    // MARK: - Items

    /// One item on a `TVDeck`: an `AVPlayerItem`, or a `VLCItem`.
    final class Item: PlayerItem {
        enum Engine {
            case av(AVPlayerItem)
            case vlc(VLCItem)
        }

        let engine: Engine
        /// AVFoundation said it has played to its end time.
        fileprivate(set) var reachedEnd = false

        init(_ engine: Engine) {
            self.engine = engine
        }

        var avItem: AVPlayerItem? {
            if case .av(let item) = engine { item } else { nil }
        }

        var vlcItem: VLCItem? {
            if case .vlc(let item) = engine { item } else { nil }
        }

        /// Where it stops, in seconds into the file.
        var end: TimeInterval {
            switch engine {
            case .av(let item): item.forwardPlaybackEndTime.seconds
            case .vlc(let item): item.end
            }
        }

        /// It has played to where it stops.
        var isAtEnd: Bool {
            switch engine {
            case .av: reachedEnd
            case .vlc(let item): item.isAtEnd
            }
        }

        var hasFailed: Bool {
            switch engine {
            case .av(let item): item.status == .failed
            case .vlc(let item): item.failure != nil
            }
        }

        /// AVFoundation's own errors are technical; say it plainly instead.
        var failure: (any Error)? {
            switch engine {
            case .av(let item):
                guard let error = item.error else { return nil }
                return (error as NSError).domain == AVFoundationErrorDomain ? UnplayableFormat() : error
            case .vlc(let item):
                return item.failure
            }
        }

        var bufferedAhead: TimeInterval {
            guard let item = avItem else { return 0 }   // VLC doesn't say
            let now = item.currentTime()
            return item.loadedTimeRanges.map(\.timeRangeValue)
                .first { $0.containsTime(now) }
                .map { ($0.end - now).seconds } ?? 0
        }

        var bufferedInAll: TimeInterval {
            guard let item = avItem else { return 0 }
            return item.loadedTimeRanges.map(\.timeRangeValue.duration.seconds).filter(\.isFinite).reduce(0, +)
        }
    }
}

/// A programme Apple TV couldn't play.
struct UnplayableFormat: LocalizedError {
    var errorDescription: String? {
        "This programme couldn't be played. It may be in a format Apple TV can't show."
    }
}
