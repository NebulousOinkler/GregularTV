import Foundation
import GregularCore

/// One video player with its own picture on screen, playing a queue of
/// items back to back. This is the only way `ChannelPlayer` touches actual
/// video: Apple TV provides it with `AVQueuePlayer`, and VLC for the items
/// its stream says the fallback player plays (`TVDeck` in the app); the
/// web version with `<video>` elements.
///
/// `ChannelPlayer` uses two decks: one on screen, and one behind it buffering
/// the programme after a commercial break, so the two can swap on the dot.
@MainActor public protocol PlayerDeck: AnyObject {
    /// An item that plays `url` from `start` seconds into it and stops at
    /// `end`. It may be queued on either deck, but only on one.
    /// - Parameters:
    ///   - player: the device's own player, or its fallback, as the stream says.
    ///   - bufferAhead: how far ahead to buffer, or nil for the default.
    func makeItem(url: URL, on player: MediaStream.Player, from start: TimeInterval, to end: TimeInterval,
                  bufferAhead: TimeInterval?) -> any PlayerItem

    /// The item playing (or paused, or waiting for data), if any.
    var currentItem: (any PlayerItem)? { get }
    /// Whether `item` is the current item or queued after it.
    func contains(_ item: any PlayerItem) -> Bool
    /// Queues `item` after everything already queued.
    func append(_ item: any PlayerItem)
    /// Stops and forgets every item.
    func removeAll()
    /// Moves on to the next queued item now.
    func advance()
    /// True: hold on the last frame when an item ends (the deck reports
    /// `.paused`). False: go straight on to the next item.
    var pausesAtItemEnd: Bool { get set }
    /// Sound level, 0 (silent) to 1 (full), for every item on the deck.
    var volume: Float { get set }

    var state: PlayerDeckState { get }
    func play()
    func pause()
    /// Seeks the current item to `seconds` into it (to within a couple of seconds).
    func seek(to seconds: TimeInterval)
    /// Seconds into the current item.
    var position: TimeInterval { get }

    /// What the deck is doing, in a word or two, for "Show playback
    /// diagnostics": "Playing", or "Buffering" with why if the player says.
    var activity: String { get }
}

/// What a deck is doing.
public enum PlayerDeckState: Sendable, Equatable {
    case paused
    case playing
    /// Waiting for data (buffering).
    case waiting
}

/// One item made by a `PlayerDeck`.
@MainActor public protocol PlayerItem: AnyObject {
    /// It can't play: the stream failed. `failure` says why.
    var hasFailed: Bool { get }
    var failure: (any Error)? { get }
    /// Seconds buffered past its playhead.
    var bufferedAhead: TimeInterval { get }
    /// Seconds of it loaded in all, wherever they are, even before it plays
    /// (for diagnostics).
    var bufferedInAll: TimeInterval { get }
}
