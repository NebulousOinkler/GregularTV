/// A rule that stops the same item airing twice in a row on its stream.
protocol NotTwiceInARow: SequenceRule {}

extension NotTwiceInARow {
    func allows(_ next: MediaItem, after previous: MediaItem) -> Bool {
        next.id != previous.id
    }
}

/// The same programme never airs twice in a row: a movie, or the same
/// episode. A show may follow itself with a different episode.
struct NoProgrammeTwiceInARow: NotTwiceInARow {
    static let id = "no-programme-twice-in-a-row"
    static let summary = "The same movie (or the same episode) never airs twice in a row; a show may follow itself with another episode."
    static let stream = ScheduleStream.programmes
}

/// The same commercial never plays twice in a row.
struct NoCommercialTwiceInARow: NotTwiceInARow {
    static let id = "no-commercial-twice-in-a-row"
    static let summary = "The same commercial never plays twice in a row."
    static let stream = ScheduleStream.commercials
}

/// A stream that follows the `SequenceRule`s for one kind of stream. An item
/// that isn't allowed next waits, and airs as soon as one that is has gone
/// first, so nothing is dropped and the order moves by as little as possible.
struct RuledStream {
    /// How many new items to look at for one that's allowed. Past that the
    /// rules give way, for a channel with only one movie.
    static let lookahead = 8

    private let source: AnyIterator<MediaItem>
    private let rules: [any SequenceRule]
    /// Pulled, but not yet given out: kept back by a rule, or put back.
    private var waiting: [MediaItem] = []
    /// What aired last.
    private(set) var previous: MediaItem?

    init(_ source: AnyIterator<MediaItem>, for stream: ScheduleStream, after previous: MediaItem? = nil) {
        self.source = source
        rules = ScheduleRules.sequenceRules(for: stream)
        self.previous = previous
    }

    /// The next item allowed after `previous`.
    mutating func next() -> MediaItem? {
        if let i = waiting.firstIndex(where: mayAirNext) {
            return waiting.remove(at: i)
        }
        for _ in 0..<Self.lookahead {
            guard let item = source.next() else { break }
            if mayAirNext(item) { return item }
            waiting.append(item)
        }
        return waiting.isEmpty ? source.next() : waiting.removeFirst()
    }

    /// `item` is airing: the next one is checked against it. Nil forgets
    /// what aired, to choose again.
    mutating func aired(_ item: MediaItem?) {
        previous = item
    }

    /// Items taken but not used, back at the front in their order.
    mutating func putBack(_ items: [MediaItem]) {
        waiting.insert(contentsOf: items, at: 0)
    }

    /// Takes back an item that was put back, when it airs after all.
    mutating func withdraw(_ item: MediaItem) {
        if let i = waiting.firstIndex(of: item) { waiting.remove(at: i) }
    }

    /// Whether the rules let `next` air straight after `item`.
    func allows(_ next: MediaItem, after item: MediaItem) -> Bool {
        rules.allow(next, after: item)
    }

    private func mayAirNext(_ item: MediaItem) -> Bool {
        previous.map { allows(item, after: $0) } ?? true
    }
}
