/// Each series plays from start to finish, and the series run in alphabetical
/// order. Movies are ordered by title. Uses no randomness: a marathon channel.
struct SequentialBySeries: ScheduleStrategy {
    static let id = "sequential-by-series"
    static let displayName = "Sequential by Series"
    static let mayReorderToFit = false   // skipping would break episode order

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        var position = position
        return AnyIterator {
            defer { position += 1 }
            return content.items[ChannelContent.wrap(position, content.items.count)]
        }
    }
}
