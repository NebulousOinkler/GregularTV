/// The user's streaming quality setting.
///
/// Each option caps the bitrate the media server may send. The server then decides the
/// rest. If the original file fits under the cap and Apple TV can play it, it
/// plays directly. Otherwise the server transcodes, and picks a resolution to
/// match the bitrate, so the resolutions in the labels are approximate.
///
/// Lowering quality saves bandwidth, but if a file could otherwise play
/// directly, it makes the server transcode. That's *more* CPU work, so
/// "Maximum" can actually be the lightest option for the server.
public enum StreamingQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    case auto
    case maximum
    case hd20
    case hd10
    case hd720
    case sd

    public static let maximumBitrate = 120_000_000
    /// Used in Auto if measuring the connection fails.
    public static let fallbackAutoBitrate = 8_000_000
    /// The lowest option's cap (480p).
    public static let lowestBitrate = 1_500_000

    public var id: String { rawValue }

    /// The fixed cap in bits per second, or nil for Auto, which measures the
    /// connection instead.
    public var fixedBitrate: Int? {
        switch self {
        case .auto: nil
        case .maximum: Self.maximumBitrate
        case .hd20: 20_000_000
        case .hd10: 10_000_000
        case .hd720: 4_000_000
        case .sd: Self.lowestBitrate
        }
    }

    /// The fixed caps below Maximum, highest first: the steps for stepping
    /// quality down one at a time.
    public static let stepDownBitrates = [hd20, hd10, hd720, sd].compactMap(\.fixedBitrate)

    /// The next step down from `bitrate`, or nil if it's already the lowest.
    public static func bitrate(below bitrate: Int) -> Int? {
        stepDownBitrates.first { $0 < bitrate }
    }

    /// Auto's cap for a measured bandwidth: 70% of it, leaving headroom for
    /// fluctuations, kept between the lowest option and the maximum.
    public static func autoBitrate(measured bitsPerSecond: Int) -> Int {
        let target = Int(Double(bitsPerSecond) * 0.7)
        return min(maximumBitrate, max(lowestBitrate, target))
    }
}
