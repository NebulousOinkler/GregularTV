/// Series and films on one channel, with films taking a set share of the
/// slots (`ChannelContent.filmSlotShare`, from the channel's `"films"` share
/// of airtime), each side in its own Shuffled Shows order. Every mixed
/// channel uses it.
///
/// Under Shuffled Shows every title gets one turn per pass, so a library
/// with far more films than series fills a mixed channel with films. Here
/// the share decides instead:
/// - **Which slots are films:** positions come in blocks of `blockLength`.
///   Each block holds its share of film slots exactly (`⌊(b+1)·B·r⌋ − ⌊b·B·r⌋`
///   for block `b`), at places picked by a shuffle seeded by the block, so
///   films don't arrive on a fixed beat and any position can be read directly.
/// - **What plays in them:** the series and the films each follow their own
///   `ShowOrder` (seeded apart), counted by how many slots of that kind came
///   before. So each series still advances one episode per pass of the
///   series, and every film airs once per pass of the films.
///
/// Without a share, or with only series or only films, it's Shuffled Shows.
struct ShuffledMix: ScheduleStrategy {
    static let id = "shuffled-mix"
    static let displayName = "Shuffled Mix"
    /// Positions per block of film and series slots.
    static let blockLength = 10

    func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
        let films = content.series.filter(Self.isFilm)
        let series = content.series.filter { !Self.isFilm($0) }
        guard let share = content.filmSlotShare, !films.isEmpty, !series.isEmpty else {
            return ShuffledShows().programmes(from: content, startingAt: position, rng: rng)
        }
        let slots = FilmSlots(share: share, seed: SeededRandom.mix(content.seed ^ 0x51_07))
        let filmOrder = ShowOrder(shows: films, seed: SeededRandom.mix(content.seed ^ 0xF1_17))
        let seriesOrder = ShowOrder(shows: series, seed: SeededRandom.mix(content.seed ^ 0x5E_71))
        return AnyIterator(startingAt: position) { position in
            let filmsBefore = slots.films(before: position)
            return slots.isFilm(position)
                ? filmOrder.programme(at: filmsBefore)
                : seriesOrder.programme(at: position - filmsBefore)
        }
    }

    /// The average slot per position: the films' share of slots at the
    /// films' average, the rest at the series' (each series at the average of
    /// its episodes, as each gets one turn per pass).
    func averageSlotLength(of content: ChannelContent, slotLength: (MediaItem) -> Int64) -> Double? {
        guard let share = content.filmSlotShare else { return nil }
        let films = content.series.filter(Self.isFilm), series = content.series.filter { !Self.isFilm($0) }
        guard !films.isEmpty, !series.isEmpty else { return nil }
        return share * ChannelVariety.averageSlot(of: films, slotLength: slotLength)
            + (1 - share) * ChannelVariety.averageSlot(of: series, slotLength: slotLength)
    }

    /// A film (or other one-off video), as opposed to a series' episodes.
    static func isFilm(_ show: [MediaItem]) -> Bool {
        show[0].kind != .episode
    }
}

/// Which positions are film slots, `share` of them, readable at any position.
struct FilmSlots: Sendable {
    let share: Double
    let seed: UInt64

    /// How many film slots there are before `position`.
    func films(before position: Int) -> Int {
        let (block, offset) = Self.split(position)
        return filmsBefore(block: block) + places(inBlock: block).filter { $0 < offset }.count
    }

    func isFilm(_ position: Int) -> Bool {
        let (block, offset) = Self.split(position)
        return places(inBlock: block).contains(offset)
    }

    /// Film slots in every block before `block`.
    private func filmsBefore(block: Int) -> Int {
        Int((Double(block) * Double(ShuffledMix.blockLength) * share).rounded(.down))
    }

    /// The offsets in `block` that are film slots.
    private func places(inBlock block: Int) -> ArraySlice<Int> {
        let count = filmsBefore(block: block + 1) - filmsBefore(block: block)
        var rng = SeededRandom(seed: seed, cycle: block)
        let order = ShuffledOrder(count: ShuffledMix.blockLength, seed: rng.next())
        return (0..<ShuffledMix.blockLength).map(order.index(at:)).prefix(count)
    }

    private static func split(_ position: Int) -> (block: Int, offset: Int) {
        (ChannelContent.pass(position, ShuffledMix.blockLength), ChannelContent.wrap(position, ShuffledMix.blockLength))
    }
}
