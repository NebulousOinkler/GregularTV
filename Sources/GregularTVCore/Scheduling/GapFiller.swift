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
    /// Stable identifier used by channel config, e.g. `"derangement"`.
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
            DerangedCommercials.self,
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

/// The default. The commercials in the order of the same lazy derangement
/// as the channel's shows, with the **same `a` and `b`**: clip number
/// `(a·x + b) mod q` at step `x`, keeping only numbers below the pool size.
///
/// Clips are numbered by their position in the pool (sorted by name). `q` is
/// the smallest prime above both the pool size and the shows' `a` and `b`,
/// so those can be used unchanged. Each pass of `q` steps plays every clip
/// exactly once, in the same order each pass, and passes follow each other
/// across breaks. With far fewer clips than shows, most steps are skipped;
/// each is a multiplication, so that costs nothing noticeable.
struct DerangedCommercials: GapFiller {
    static let id = "derangement"

    func clips(from pool: [MediaItem], for content: ChannelContent, startingAt position: Int) -> AnyIterator<MediaItem> {
        guard !pool.isEmpty else { return AnyIterator { nil } }
        let order = Self.order(forPoolOf: pool.count, content: content)
        // `position` counts clips; the derangement advances about q/M raw steps per clip.
        var step = Int((Double(position) * Double(order.prime) / Double(pool.count)).rounded(.down))
        return AnyIterator {
            while true {
                defer { step += 1 }
                if let index = order.value(atStep: step) { return pool[index] }
            }
        }
    }

    /// The shows' derangement's `a` and `b`, over a prime big enough for them and the pool.
    static func order(forPoolOf count: Int, content: ChannelContent) -> LazyDerangement {
        let shows = LazyDerangement(count: content.series.count, key: content.seed)
        let prime = Primes.next(after: max(count, shows.a, shows.b))
        return LazyDerangement(count: count, prime: prime, a: shows.a, b: shows.b)
    }
}

/// An alternative: each pass through the pool is a fresh shuffle
/// (Fisher–Yates, seeded by the channel key and the pass number), so the
/// order differs every pass. Every clip plays once per pass.
struct ShuffledCommercials: GapFiller {
    static let id = "shuffle"

    func clips(from pool: [MediaItem], for content: ChannelContent, startingAt position: Int) -> AnyIterator<MediaItem> {
        guard !pool.isEmpty else { return AnyIterator { nil } }
        var position = position
        var pass = Int.min
        var deck: [MediaItem] = []
        return AnyIterator {
            defer { position += 1 }
            let thisPass = ChannelContent.pass(position, pool.count)
            if thisPass != pass {
                pass = thisPass
                var rng = SeededRandom(seed: content.seed ^ 0xC0_33E4, cycle: pass)
                deck = rng.shuffled(pool)
            }
            return deck[ChannelContent.wrap(position, pool.count)]
        }
    }
}
