import Foundation

/// Decides the order commercials play in, in the gaps between a programme's
/// end and the start of the next slot (on channels with `padTo`, and at the
/// end of each run).
///
/// A filler gives one endless stream of clips per channel, like a strategy
/// gives programmes. The engine deals from it break after break, so the
/// order carries on from one break to the next rather than starting afresh:
/// - A gap of a minute or less gets no commercials.
/// - Clips play back to back. When one ends, the next only starts if at
///   least half of it will play before the next programme; if not, it waits
///   to open the next break instead, and the rest of this gap is blank.
/// - A clip still playing when the next programme starts is cut off.
///
/// The rules for a filler:
/// 1. **Be deterministic.** The stream must depend only on the pool, the
///    channel's content (its key, `content.seed`) and `position`. Every
///    launch and every Apple TV then fills the same gaps the same way.
/// 2. **Start anywhere.** `position` counts clips aired on the channel so
///    far (an estimate at the start of each run, like a strategy's). The
///    stream must be quick to start at any position.
///
/// Fillers play as ordinary airings (marked `isFiller`), so the player hands
/// off between them seamlessly, as it does between programmes.
///
/// **To add a filler:** create a type conforming to this protocol, add it to
/// `GapFillerRegistry.all`, and set `"filler": "<id>"` on a channel in
/// `channels.json`.
public protocol GapFiller: Sendable {
    /// Stable identifier used by channel config, e.g. `"shuffle"`.
    static var id: String { get }

    init()

    /// The channel's commercials, in order, from `position` on. Endless.
    /// - Parameters:
    ///   - pool: the clips (never empty), sorted by name.
    ///   - content: the channel's programmes and key (`content.seed`).
    func clips(from pool: [MediaItem], for content: ChannelContent, startingAt position: Int) -> AnyIterator<MediaItem>
}

public enum GapFillerRegistry {
    public static var all: [any GapFiller.Type] {
        [
            NoGapFiller.self,
            ShuffledCommercials.self,
            // ← add new fillers here
        ]
    }

    public static func contains(id: String) -> Bool {
        all.contains { $0.id == id }
    }

    public static func filler(withID id: String) -> (any GapFiller)? {
        all.first { $0.id == id }.map { $0.init() }
    }
}

/// Leave gaps empty: a blank screen with the "Up next" card.
struct NoGapFiller: GapFiller {
    static let id = "none"

    func clips(from pool: [MediaItem], for content: ChannelContent, startingAt position: Int) -> AnyIterator<MediaItem> {
        AnyIterator { nil }
    }
}

/// Every default channel's filler. Each pass through the pool plays every
/// clip once, in a new shuffle (`ShuffledOrder.Passes`), and passes follow
/// each other across breaks. The same clip never plays twice in a row
/// (`NoCommercialTwiceInARow`). The
/// shuffle's seed is the channel's key mixed with a constant, so the
/// commercials don't mirror the order of the shows.
struct ShuffledCommercials: GapFiller {
    static let id = "shuffle"

    func clips(from pool: [MediaItem], for content: ChannelContent, startingAt position: Int) -> AnyIterator<MediaItem> {
        guard !pool.isEmpty else { return AnyIterator { nil } }
        let order = ShuffledOrder.Passes(count: pool.count, seed: content.seed ^ 0xC0_33E4)
        var position = position
        return AnyIterator {
            defer { position += 1 }
            return pool[order.index(at: position)]
        }
    }
}
