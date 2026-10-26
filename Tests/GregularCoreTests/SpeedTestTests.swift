import Testing
@testable import GregularCore

/// The speed test takes a few seconds whatever the connection: it stops at
/// the first download long enough to time.
struct SpeedTestTests {
    /// Downloads on a connection of `bitsPerSecond`, recording their sizes.
    private final class Connection: @unchecked Sendable {
        let bitsPerSecond: Double
        var sizes: [Int] = []
        init(_ bitsPerSecond: Double) { self.bitsPerSecond = bitsPerSecond }

        func download(_ bytes: Int) -> Duration {
            sizes.append(bytes)
            return .seconds(Double(bytes * 8) / bitsPerSecond)
        }
    }

    @Test(arguments: [
        (1_000_000.0, [256_000]),                                  // 2 s: the first is long enough
        (8_000_000.0, [256_000, 1_000_000]),                       // a quarter of a second, then 1 s
        (20_000_000.0, [256_000, 1_000_000, 4_000_000]),           // then 1.6 s
        (500_000_000.0, [256_000, 1_000_000, 4_000_000, 12_000_000]),
    ])
    func itStopsAtTheFirstDownloadLongEnoughToTime(bitsPerSecond: Double, sizes: [Int]) async throws {
        let connection = Connection(bitsPerSecond)
        let measured = try await SpeedTest.measure { connection.download($0) }
        #expect(connection.sizes == sizes)
        #expect(abs(Double(measured) - bitsPerSecond) < bitsPerSecond * 0.01)
        let seconds = connection.sizes.reduce(0) { $0 + Double($1 * 8) / bitsPerSecond }
        #expect(seconds < 3, "A few seconds, not the most of a minute 3 MB took at 1 Mbps")
    }

    @Test func aMeasurementBeyondAnyStreamIsCapped() async throws {
        #expect(try await SpeedTest.measure { _ in .zero } == SpeedTest.fastest)
    }

    @Test func aFailedDownloadFailsTheTest() async {
        struct Dropped: Error {}
        await #expect(throws: Dropped.self) { try await SpeedTest.measure { _ in throw Dropped() } }
    }
}
