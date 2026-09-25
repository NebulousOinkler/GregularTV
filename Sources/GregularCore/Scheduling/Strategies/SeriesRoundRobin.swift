/// Series take turns: an episode of show A, then show B, then C, then back to A.
/// Each show's episodes stay in aired order, and each show loops back to its
/// first episode on its own. The turn order of the shows is shuffled once
/// per channel.
struct SeriesRoundRobin: ScheduleStrategy {
    static let id = "series-round-robin"
    static let displayName = "Series Round Robin"
    static let mayReorderToFit = false   // skipping would break the turn order

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let shows = content.series
        let turnOrder = LazyPermutation(count: shows.count, seed: content.seed)
        return programmes(startingAt: position) { position in
            let round = ChannelContent.pass(position, shows.count)
            let show = shows[turnOrder.index(at: position)]
            return show[ChannelContent.wrap(round, show.count)]
        }
    }
}
