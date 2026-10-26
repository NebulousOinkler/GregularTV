/// How fast a server can send data right now, measured in a few seconds on
/// any connection.
///
/// One fixed size can't do that: what takes a second on a fast connection
/// takes most of a minute on a slow one, and a programme's retry waits for
/// the measurement (`ChannelPlayer`). So each download is four times the
/// last, until one takes `longEnough` to time well, and that one is the
/// measurement. On a slow connection the first answers; on a fast one, the
/// largest.
public enum SpeedTest {
    /// The downloads, in bytes, in order. The largest fits easily under
    /// `TransportRules.largestResponse`.
    public static let sizes = [256_000, 1_000_000, 4_000_000, 12_000_000]
    /// A download this long is timed well enough to stop at.
    public static let longEnough: Duration = .milliseconds(750)
    /// The fastest a measurement reports: 2 Gbps, far beyond any stream,
    /// and within a 32-bit Int (WebAssembly's).
    public static let fastest = 2_000_000_000

    /// Bits per second, from `download`, which fetches that many bytes from
    /// the server and says how long it took.
    public static func measure(_ download: (Int) async throws -> Duration) async throws -> Int {
        var measured = 0
        for bytes in sizes {
            let took = try await download(bytes)
            let seconds = max(0.001, took / .seconds(1))
            measured = Int(min(Double(bytes * 8) / seconds, Double(fastest)))
            if took >= longEnough { break }
        }
        return measured
    }
}
