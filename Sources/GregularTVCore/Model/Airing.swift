import Foundation

/// One scheduled showing of an item on a channel: a single entry in the guide.
public struct Airing: Sendable, Hashable {
    public let item: MediaItem
    /// When the programme starts.
    public let start: Date
    /// When the airing stops playing: the end of the programme, or for a
    /// commercial cut off by the next programme, the moment it's cut.
    public let end: Date
    /// When the next airing starts. This is later than `end` only when the
    /// channel pads slots to a boundary (see `Channel.padToMinutes`) and the
    /// gap isn't fully filled.
    public let slotEnd: Date
    /// True for gap content such as commercials (see `GapFiller`), false for programmes.
    public let isFiller: Bool

    /// How long it plays for. Shorter than the item for a commercial that's cut off.
    public var length: TimeInterval { end.timeIntervalSince(start) }
}

/// What a channel is showing at a particular moment.
public struct Tuning: Sendable, Hashable {
    public let airing: Airing
    /// Seconds into the airing's slot.
    public let offset: TimeInterval

    /// True when the programme has finished and the channel is in the padding
    /// before the next slot. The player shows filler here, not video.
    public var isInPadding: Bool { offset >= airing.length }
}
