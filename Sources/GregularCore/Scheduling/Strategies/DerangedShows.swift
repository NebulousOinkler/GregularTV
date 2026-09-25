/// Shows and movies in the order of a lazy derangement (see `LazyDerangement`),
/// each show advancing one episode per pass.
///
/// - Each show or movie on the channel has a numeric ID: its index in
///   `content.series`, which is sorted by title.
/// - A derangement of those IDs, with (a, b) from the channel's key
///   (`ScheduleCode`), decides which show comes next.
/// - Each pass of the derangement plays every show once. On pass `k`, a show
///   plays its episode `k` (wrapping at its last episode), so a show's
///   appearances go forward through its episodes.
/// - **Within one run (a day), a show's episodes only ever go forwards**, so a
///   viewer never sees an episode before the one that precedes it. The one
///   exception: once a show has played its final episode, its next appearance
///   cycles back to the pilot (its first available episode) and carries on
///   forwards from there. Any other backwards step is skipped (a safety net;
///   the pass arithmetic doesn't produce one). Movies are single-item shows,
///   so the rule doesn't apply to them.
struct DerangedShows: ScheduleStrategy {
    static let id = "derangement"
    static let displayName = "Shuffled Shows (Derangement)"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let shows = content.series
        let order = LazyDerangement(count: shows.count, key: content.seed)
        // `position` counts programmes; the derangement advances about p/N raw steps per programme.
        var step = Int((Double(position) * Double(order.prime) / Double(shows.count)).rounded(.down))
        // The last episode index each show played in this run.
        var lastEpisode: [Int: Int] = [:]
        var rejectedInARow = 0
        // 2N consecutive rejections span at least one full pass: every show has
        // been offered and none can go forwards, so stop rather than loop.
        let stuck = 2 * shows.count

        return AnyIterator {
            while true {
                defer { step += 1 }
                guard let show = order.value(atStep: step) else { continue }
                let episodes = shows[show]
                let episode = ChannelContent.wrap(order.pass(ofStep: step), episodes.count)

                // Forwards, or back to the pilot after the show came round, is fine.
                if let last = lastEpisode[show], episode <= last, episode != 0 {
                    rejectedInARow += 1
                    if rejectedInARow >= stuck { return nil }
                    continue
                }
                rejectedInARow = 0
                lastEpisode[show] = episode
                return episodes[episode]
            }
        }
    }
}
