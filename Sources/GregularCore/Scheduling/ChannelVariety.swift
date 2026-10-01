/// How much different programming a channel has in the library it's
/// connected to, which decides two things when its schedule is built:
/// - **Whether a themed channel is shown.** A channel with `needsVariety`
///   (every bundled channel but the two catch-alls) is hidden when its
///   programmes can't fill a day without repeating sooner than the limits
///   below. So a small library shows fewer, broader channels, and a big one
///   shows them all, with nothing to set.
/// - **A mixed channel's film share.** The channel asks for a share of the
///   airtime (`Channel.filmShare`); if its series or its films can't carry
///   their part without repeating too soon, the other side takes the rest.
///
/// The limits: a series airs at most about once a day (`seriesDays`), like
/// a real channel's daily slot, and a film at most about once every three
/// days (`filmDays`). Both come from a pass of the channel's shuffle: one
/// episode of every series, or every film once.
public struct ChannelVariety: Sendable {
    /// A series' turn comes round at most about this often, in days.
    public static let seriesDays = 1.0
    /// A film's turn comes round at most about this often, in days.
    public static let filmDays = 3.0
    static let day = 86_400_000.0

    /// One pass of the series (each at its average episode's slot), in milliseconds.
    public let seriesAirtime: Double
    /// One pass of the films (each once), in milliseconds.
    public let filmAirtime: Double
    /// The average slot of a series' episode and of a film, in milliseconds.
    let averageSeriesSlot: Double
    let averageFilmSlot: Double

    /// `shows` as `ChannelContent.series` groups them: each a series, or a one-item film.
    init(shows: [[MediaItem]], slotLength: (MediaItem) -> Int64) {
        let films = shows.filter(ShuffledMix.isFilm), series = shows.filter { !ShuffledMix.isFilm($0) }
        averageSeriesSlot = Self.averageSlot(of: series, slotLength: slotLength)
        averageFilmSlot = Self.averageSlot(of: films, slotLength: slotLength)
        seriesAirtime = averageSeriesSlot * Double(series.count)
        filmAirtime = averageFilmSlot * Double(films.count)
    }

    /// The most airtime a day the series and the films can each fill
    /// without coming round sooner than the limits.
    var seriesPerDay: Double { seriesAirtime / Self.seriesDays }
    var filmsPerDay: Double { filmAirtime / Self.filmDays }

    /// Enough to fill a day without anything coming round too soon.
    public var fillsADay: Bool { seriesPerDay + filmsPerDay >= Self.day }

    /// The share of airtime for films, from the share `wanted`: no more than
    /// the films can carry, and no less than the series leave over.
    public func filmShare(wanted: Double) -> Double {
        if filmAirtime == 0 { return 0 }
        if seriesAirtime == 0 { return 1 }
        let films = max(min(wanted * Self.day, filmsPerDay), Self.day - seriesPerDay)
        return min(1, max(0, films / Self.day))
    }

    /// The share of slots that are films, for an airtime share of `share`:
    /// films are longer, so they take fewer slots than their airtime.
    func filmSlotShare(forAirtime share: Double) -> Double {
        guard averageFilmSlot > 0, averageSeriesSlot > 0 else { return share > 0 ? 1 : 0 }
        let films = share / averageFilmSlot, series = (1 - share) / averageSeriesSlot
        return films / (films + series)
    }

    /// The average slot of `shows`, each counted once: a series at the
    /// average of its episodes' slots.
    static func averageSlot(of shows: [[MediaItem]], slotLength: (MediaItem) -> Int64) -> Double {
        guard !shows.isEmpty else { return 0 }
        let each = shows.map { show in Double(show.reduce(0) { $0 + slotLength($1) }) / Double(show.count) }
        return each.reduce(0, +) / Double(shows.count)
    }
}
