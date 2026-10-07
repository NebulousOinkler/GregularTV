/// Shows and movies in a new shuffled order each pass, each show advancing
/// one episode per pass. Every film-only channel uses it, and so does every
/// custom channel.
///
/// - A pass plays every show or movie on the channel once, in its own
///   shuffle (`ShuffledOrder.Passes`, seeded by the channel's key from the
///   `ScheduleCode`). Every pass opens with the same half of the shows, so
///   each comes round again at least half a pass after its last turn, and
///   the show that closed a pass never opens the next.
/// - On pass `k`, a show plays its episode `k` (wrapping at its last
///   episode). So within one run (a day) a show's episodes only go
///   forwards, except that after its final episode it cycles back to the
///   pilot (its first available episode). Movies are single-item shows.
struct ShuffledShows: ScheduleStrategy {
    static let id = "shuffled-shows"
    static let displayName = "Shuffled Shows"

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let order = ShowOrder(shows: content.series, seed: content.seed)
        return AnyIterator(startingAt: position, order.programme(at:))
    }
}

/// The Shuffled Shows order over a set of shows (each a series in aired
/// order, or a one-item film), readable at any position: pass after pass,
/// every show once per pass in a fresh shuffle, each show on its episode `k`
/// in pass `k`. `ShuffledMix` keeps one for its series and one for its films.
struct ShowOrder: Sendable {
    let shows: [[MediaItem]]
    private let passes: ShuffledOrder.Passes

    init(shows: [[MediaItem]], seed: UInt64) {
        self.shows = shows
        passes = ShuffledOrder.Passes(count: shows.count, seed: seed)
    }

    func programme(at position: Int) -> MediaItem {
        let episodes = shows[passes.index(at: position)]
        return episodes[ChannelContent.wrap(passes.pass(of: position), episodes.count)]
    }
}
