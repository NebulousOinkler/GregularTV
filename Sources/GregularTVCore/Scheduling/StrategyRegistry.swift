/// Every schedule strategy the app knows about.
///
/// **To add a strategy:**
/// 1. Create a file in `Scheduling/Strategies/` with a type that conforms to
///    `ScheduleStrategy`.
/// 2. Add it to the list below.
/// 3. Use its `id` as the `"strategy"` value in `channels.json`.
///
/// `swift test` then runs the shared conformance tests against it.
public enum StrategyRegistry {
    public static var all: [any ScheduleStrategy.Type] {
        [
            DerangedShows.self,
            RandomShuffle.self,
            SequentialBySeries.self,
            SeriesRoundRobin.self,
            ShuffledSeriesInOrder.self,
            // ← add new strategies here
        ]
    }

    public static func contains(id: String) -> Bool {
        all.contains { $0.id == id }
    }

    public static func strategy(withID id: String) -> (any ScheduleStrategy)? {
        all.first { $0.id == id }.map { $0.init() }
    }
}
