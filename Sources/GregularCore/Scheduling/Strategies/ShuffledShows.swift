/// Shows and movies in a new shuffled order each pass, each show advancing
/// one episode per pass. Every default channel uses it.
///
/// - A pass plays every show or movie on the channel once, in its own
///   shuffle (`ShuffledOrder.Passes`, seeded by the channel's key from the
///   `ScheduleCode`). Where passes meet, a show may follow itself with its
///   next episode; a movie never follows itself (`NoProgrammeTwiceInARow`).
/// - On pass `k`, a show plays its episode `k` (wrapping at its last
///   episode). So within one run (a day) a show's episodes only go
///   forwards, except that after its final episode it cycles back to the
///   pilot (its first available episode). Movies are single-item shows.
struct ShuffledShows: ScheduleStrategy {
    static let id = "shuffled-shows"
    static let displayName = "Shuffled Shows"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let shows = content.series
        let order = ShuffledOrder.Passes(count: shows.count, seed: content.seed)
        return programmes(startingAt: position) { position in
            let episodes = shows[order.index(at: position)]
            return episodes[ChannelContent.wrap(order.pass(of: position), episodes.count)]
        }
    }
}
