/// Everything in a random order. Each item plays once before any repeats,
/// then the next pass is shuffled differently.
/// Good for movie channels and anthology-style content.
struct RandomShuffle: ScheduleStrategy {
    static let id = "random-shuffle"
    static let displayName = "Random Shuffle"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let count = content.items.count
        var position = position
        return AnyIterator {
            defer { position += 1 }
            // A different shuffle for each pass through the items, read at one position.
            let pass = ChannelContent.pass(position, count)
            let order = LazyPermutation(count: count, seed: content.seed &+ UInt64(bitPattern: Int64(pass)))
            return content.items[order.index(at: position)]
        }
    }
}
