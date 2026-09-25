/// A channel's programmes, prepared once when the channel is built, for
/// strategies to draw from.
///
/// This is the channel's *library* (what it can play), not its schedule.
/// Schedules are never built in full: the engine pulls a few programmes at a
/// time from a strategy (see `ScheduleStrategy`).
public struct ChannelContent: Sendable {
    /// Every programme in a stable order: series by title, each series in
    /// aired order, with movies as one-item "series" sorted in among them.
    public let items: [MediaItem]
    /// The same items grouped by series, in the same order.
    public let series: [[MediaItem]]
    /// The channel's seed, for strategies that shuffle.
    public let seed: UInt64

    public init(items: [MediaItem], seed: UInt64) {
        series = MediaItem.groupedBySeries(items).sorted {
            (($0[0].seriesName ?? $0[0].name).lowercased(), $0[0].seriesKey)
                < (($1[0].seriesName ?? $1[0].name).lowercased(), $1[0].seriesKey)
        }
        self.items = series.flatMap { $0 }
        self.seed = seed
    }

    /// `position` wrapped into `0..<count`. It works for negative positions
    /// too, which occur for times before the channel's epoch.
    public static func wrap(_ position: Int, _ count: Int) -> Int {
        let r = position % count
        return r < 0 ? r + count : r
    }

    /// Integer division rounding towards negative infinity: which pass through
    /// the items `position` falls in.
    public static func pass(_ position: Int, _ count: Int) -> Int {
        Int(ChannelSchedule.floorDivide(Int64(position), Int64(count)))
    }
}
