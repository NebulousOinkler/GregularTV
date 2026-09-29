import Foundation

/// A household's set times on one channel: programmes at set local times,
/// laid over the channel's shared schedule. Everyone else with the same
/// schedule code still sees the same programmes whenever these aren't on.
///
/// Made in Settings (bundled channels and custom ones alike), and saved on
/// the device as its code (see `AppPreferences`), which is also how it's
/// shared: type it into another Apple TV and both show the same set times.
/// The times are read in the time zone they were made in, kept with them, so
/// every Apple TV agrees what "6:00 PM" means.
public struct SetTimes: Sendable, Hashable {
    public var channelNumber: Int
    /// The programmes and their times, read in `timeZone`.
    public var programmes: [FixedProgramme]
    public var timeZone: TimeZone

    public init(channelNumber: Int, programmes: [FixedProgramme], timeZone: TimeZone = .current) {
        self.channelNumber = channelNumber
        self.programmes = programmes.map { $0.in(timeZone) }
        self.timeZone = timeZone
    }

    private static let version: UInt8 = 1

    /// The code to type into another Apple TV: the channel number, the time
    /// zone and the set times (see `CodeWriter`).
    public var code: String {
        var writer = CodeWriter(version: Self.version)
        writer.byte(UInt8(clamping: channelNumber))
        writer.text(timeZone.identifier)
        writer.setTimes(programmes)
        return writer.code
    }

    /// Reads a set-times code. Nil if it isn't one, or was mistyped.
    public init?(code: String) {
        guard var reader = CodeReader(code: code, version: Self.version), let number = reader.byte(),
              let identifier = reader.text(), let zone = TimeZone(identifier: identifier),
              let programmes = reader.setTimes(), reader.isAtEnd else { return nil }
        self.init(channelNumber: Int(number), programmes: programmes, timeZone: zone)
    }
}
