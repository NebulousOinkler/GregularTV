/// Picks a random series for each slot and plays that series' next episode.
/// Episodes stay in aired order, but which show comes on next is a surprise.
///
/// A series is picked with probability proportional to its length, so long
/// and short shows advance at the same pace. At `position`, each series is
/// estimated to have aired its share of the episodes so far, and continues
/// from there.
struct ShuffledSeriesInOrder: ScheduleStrategy {
    static let id = "shuffled-series-in-order"
    static let displayName = "Shuffled Series, Episodes in Order"
    static let mayReorderToFit = false   // skipping would break episode order

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let shows = content.series
        let total = content.items.count
        // Where each series is up to: its share of the programmes aired so far.
        var cursors = shows.map { Int((Double(position) * Double($0.count) / Double(total)).rounded(.down)) }
        var rng = rng
        return AnyIterator {
            var pick = rng.int(below: total)
            for i in shows.indices {
                if pick < shows[i].count {
                    defer { cursors[i] += 1 }
                    return shows[i][ChannelContent.wrap(cursors[i], shows[i].count)]
                }
                pick -= shows[i].count
            }
            return shows[0][0]   // unreachable: pick < total
        }
    }
}
