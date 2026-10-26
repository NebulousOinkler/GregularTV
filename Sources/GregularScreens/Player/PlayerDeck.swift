import Foundation
import GregularCore

/// One video player with its own picture on screen, playing a queue of
/// items back to back. This is the only way `ChannelPlayer` touches actual
/// video: Apple TV provides it with `AVQueuePlayer`, and VLC for the items
/// its stream says the add-on player plays (`TVDeck` in the app); the
/// web version with `<video>` elements.
///
/// `ChannelPlayer` uses two decks: one on screen, and one behind it buffering
/// the programme after a commercial break, so the two can swap on the dot.
@MainActor public protocol PlayerDeck: AnyObject {
    /// An item that plays `url` from `start` seconds into it and stops at
    /// `end`. It may be queued on either deck, but only on one.
    /// - Parameters:
    ///   - player: the device's own player, or its add-on player, as the stream says.
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

    /// What the deck is doing, for "Show playback diagnostics" (`PlayerText.activity`).
    var activity: DeckActivity { get }
}

/// What a deck is doing, as its player says, for diagnostics. `PlayerText`
/// words it, so every deck's read the same.
public struct DeckActivity: Sendable, Equatable {
    /// What a waiting player is waiting for.
    public enum Wait: Sendable, Equatable {
        case opening, waitingForScreen, fillingBuffer, starting, measuringNetwork, nothingLoaded, networkStalled, other
    }

    /// Nil if the player says something the deck doesn't know.
    public let state: PlayerDeckState?
    /// On the device's add-on player (VLC on Apple TV).
    public let onAddOn: Bool
    /// While waiting, what for, if the player says.
    public let waitingFor: Wait?

    public init(_ state: PlayerDeckState?, onAddOn: Bool = false, waitingFor: Wait? = nil) {
        self.state = state
        self.onAddOn = onAddOn
        self.waitingFor = waitingFor
    }
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

/// A deck's item stopped for a reason that isn't its format (`UnplayableMedia`)
/// or the connection (`ConnectionFailure`): it's retried as it is. For any
/// deck to report.
public struct PlaybackStopped: LocalizedError {
    public init() {}

    public var errorDescription: String? {
        PlayerText.stopped
    }
}

/// A deck couldn't decode what it was sent (`UnplayableMedia`): its player
/// couldn't read the format, so something else must be sent.
public struct UnplayableFormat: UnplayableMedia, LocalizedError {
    /// The device, as "a format … can't show" names it (`PlayerText.appleTV`, `PlayerText.thisBrowser`).
    let device: String

    public init(on device: String) {
        self.device = device
    }

    public var errorDescription: String? {
        PlayerText.unplayable(on: device)
    }
}
