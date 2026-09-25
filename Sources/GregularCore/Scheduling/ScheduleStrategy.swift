/// Decides the running order of a channel's programmes, as an endless stream.
///
/// Like a Python generator: the engine calls `next()` on the iterator you
/// return, one programme at a time through each day-long run, and never asks for the
/// whole list. Channels can hold thousands of items, and there can be any
/// number of channels, so only what's about to air is ever worked out.
///
/// The rules for a strategy:
/// 1. **Keep going.** Wrap around (or reshuffle) when you reach the end of the
///    content. Returning nil ends the run early (the rest becomes a gap), so
///    keep it for a genuine dead end.
/// 2. **Be deterministic.** The same content, position and `rng` must give the
///    same stream. Use only `rng` (or `LazyPermutation` with `content.seed`)
///    for randomness.
/// 3. **Treat `position` as "about this many programmes have aired before".**
///    Strategies that continue a sequence (episode 5 after episode 4) should
///    start from it. It's an estimate, so a sequence may repeat or skip one
///    item where one run meets the next (once a day).
///
/// `StrategyConformanceTests` checks the rules for every strategy in
/// `StrategyRegistry`, so a new strategy is tested automatically.
public protocol ScheduleStrategy: Sendable {
    /// Stable identifier that channel config refers to, e.g. `"random-shuffle"`.
    /// Don't change it after release, because it would break `channels.json`.
    static var id: String { get }
    /// Human-readable name for settings and debug UI.
    static var displayName: String { get }
    /// Whether the engine may skip a programme that doesn't fit the time left
    /// in a run and pull the next one instead. Defaults to true; return
    /// false when order matters, such as episodes in sequence.
    static var mayReorderToFit: Bool { get }

    init()

    /// An endless stream of programmes, starting from `position`.
    /// - Parameters:
    ///   - content: the channel's programmes (never empty).
    ///   - position: roughly how many programmes the channel has aired
    ///     before this point. It can be negative, for times before the epoch.
    ///   - rng: a random source seeded for this run.
    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem>
}

extension ScheduleStrategy {
    public static var mayReorderToFit: Bool { true }
}
