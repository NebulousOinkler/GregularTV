import Foundation

/// Where each run of a channel's schedule begins, in milliseconds since the
/// channel's epoch. Both kinds are one calculation for any run, with no replay.
enum RunCalendar: Sendable {
    /// Runs of one length from the epoch: channels without fixed times.
    case uniform(length: Int64)
    /// Local calendar days in the channel's time zone (23 or 25 hours on
    /// clock-change days): channels with fixed times, so "6:00 PM" is always
    /// in the same run as the rest of its day.
    case localDays(Calendar, firstDay: Date, epoch: Date)

    init(for channel: Channel, length: Int64) {
        if let zone = channel.timeZone, !channel.fixed.isEmpty {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            self = .localDays(calendar, firstDay: calendar.startOfDay(for: channel.epoch), epoch: channel.epoch)
        } else {
            self = .uniform(length: length)
        }
    }

    /// Where run `run` starts: for local days, its midnight.
    func start(ofRun run: Int) -> Int64 {
        switch self {
        case .uniform(let length):
            return Int64(run) * length
        case .localDays(let calendar, let firstDay, let epoch):
            let midnight = calendar.date(byAdding: .day, value: run, to: firstDay) ?? firstDay
            return Int64((midnight.timeIntervalSince(epoch) * 1000).rounded())
        }
    }

    /// The run whose day contains `ms`.
    func run(containing ms: Int64) -> Int {
        switch self {
        case .uniform(let length):
            return Int(ChannelSchedule.floorDivide(ms, length))
        case .localDays(let calendar, let firstDay, let epoch):
            let date = epoch.addingTimeInterval(TimeInterval(ms) / 1000)
            var run = calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: date)).day ?? 0
            // Guard against rounding at midnight.
            while start(ofRun: run) > ms { run -= 1 }
            while start(ofRun: run + 1) <= ms { run += 1 }
            return run
        }
    }

    /// Run `run` as a local day, for placing programmes at set times. Nil for
    /// uniform runs, which have no set times.
    func day(_ run: Int) -> ScheduleDay? {
        guard case .localDays(let calendar, let firstDay, _) = self else { return nil }
        let start = calendar.date(byAdding: .day, value: run, to: firstDay) ?? firstDay
        return ScheduleDay(index: run, start: start, calendar: calendar, firstDay: firstDay)
    }
}
