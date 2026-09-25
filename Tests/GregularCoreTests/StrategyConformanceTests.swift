import Testing
@testable import GregularCore

/// Runs against **every** strategy in `StrategyRegistry`, so a new strategy is
/// checked automatically. If one of these fails for your new strategy, read
/// the rules on `ScheduleStrategy`.
struct StrategyConformanceTests {
    static let strategyIDs = StrategyRegistry.all.map { $0.id }

    private func pull(_ id: String, _ count: Int, from items: [MediaItem] = Fixtures.library,
                      position: Int = 0, seed: UInt64 = 42) throws -> [MediaItem] {
        let strategy = try #require(StrategyRegistry.strategy(withID: id))
        let stream = strategy.programmes(from: ChannelContent(items: items, seed: seed), startingAt: position,
                                         rng: SeededRandom(seed: seed, cycle: 0))
        return (0..<count).compactMap { _ in stream.next() }
    }

    @Test func idsAreUnique() {
        #expect(Set(Self.strategyIDs).count == Self.strategyIDs.count)
    }

    /// The fixture library includes movies, so no strategy has a reason to stop.
    @Test(arguments: strategyIDs)
    func keepsGoingOnMixedContent(id: String) throws {
        let n = Fixtures.library.count
        #expect(try pull(id, 5 * n).count == 5 * n)
    }

    @Test(arguments: strategyIDs)
    func onlyReturnsTheChannelsItems(id: String) throws {
        let ids = Set(Fixtures.library.map(\.id))
        #expect(try pull(id, 200).allSatisfy { ids.contains($0.id) })
    }

    @Test(arguments: strategyIDs)
    func isDeterministic(id: String) throws {
        for position in [-37, 0, 12, 10_000] {
            #expect(try pull(id, 50, position: position) == pull(id, 50, position: position))
        }
    }

    @Test(arguments: strategyIDs)
    func doesNotDependOnInputOrder(id: String) throws {
        #expect(try pull(id, 50, from: Fixtures.library) == pull(id, 50, from: Fixtures.library.reversed()))
    }

    @Test(arguments: strategyIDs)
    func handlesASingleItem(id: String) throws {
        let one = [Fixtures.movie("Solo")]
        #expect(try pull(id, 3, from: one) == one + one + one)
    }
}
