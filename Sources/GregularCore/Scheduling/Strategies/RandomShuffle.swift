/// Everything in a random order. Each item plays once before any repeats,
/// then the next pass is shuffled differently.
/// Good for movie channels and anthology-style content.
struct RandomShuffle: ScheduleStrategy {
    static let id = "random-shuffle"
    static let displayName = "Random Shuffle"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let order = ShuffledOrder.Passes(count: content.items.count, seed: content.seed)
        return AnyIterator(startingAt: position) { content.items[order.index(at: $0)] }
    }
}
