import Foundation

/// Where every channel's day starts and ends: a wall-clock time in one time
/// zone, following daylight saving, so a day is 23, 24 or 25 hours. Each day
/// is laid out on its own (a *run*, see `ChannelSchedule`): its programmes
/// play right up to this time, and the time a day can't fill is a break just
/// after it, before the next day's first programme.
///
/// **To move the day** (to 2 am, say), change `standard`. Everything else,
/// the epoch every channel's clock starts from included, follows from it.
/// Like any change to the epoch, it reshuffles what's on every channel.
/// A time the clocks skip (2 am in the US, the day they go forward) falls
/// on the first time after it that day: 3 am.
public struct DayBoundary: Sendable, Equatable {
    public let timeZone: TimeZone
    /// The time of day, after local midnight.
    public let hour: Int
    public let minute: Int

    public init(timeZone: TimeZone, hour: Int, minute: Int = 0) {
        self.timeZone = timeZone
        self.hour = hour
        self.minute = minute
    }

    /// Every channel's: midnight Pacific.
    public static let standard = DayBoundary(timeZone: TimeZone(identifier: "America/Los_Angeles")!, hour: 0)

    /// The first day's start, 1 January 2024 at this time: where every
    /// channel's clock starts (`Channel.defaultEpoch`).
    public var firstDay: Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: hour, minute: minute))!
    }

    /// The calendar days are counted in: Gregorian, in `timeZone`.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
