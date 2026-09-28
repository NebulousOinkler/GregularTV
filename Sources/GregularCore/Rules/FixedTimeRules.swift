import Foundation

/// Programmes in a channel's `fixed` list air at exactly their local times,
/// on their days. A series plays its next episode at each airing: its own
/// count of airings since the channel's first day, worked out from the
/// calendar, so any day can be found without replaying the ones before.
///
/// The engine then treats each one as a hard edge: the shuffle fills up to
/// it, programmes that wouldn't finish in time wait until after it, and any
/// time left over becomes a commercial break before it.
struct PinnedProgrammes: PinRule {
    static let id = "pinned-programmes"
    static let summary = "Fixed programmes air at exactly their set local times, each series advancing one episode per airing."

    func pins(on channel: Channel, day: ScheduleDay, programmes: [[MediaItem]]) -> [Pin] {
        let calendar = day.calendar
        let weekday = calendar.component(.weekday, from: day.start)
        let parts = calendar.dateComponents([.month, .day], from: day.start)
        let date = FixedProgramme.MonthDay(month: parts.month ?? 1, day: parts.day ?? 1)
        let firstWeekday = calendar.component(.weekday, from: day.firstDay)
        let years = [calendar.component(.year, from: day.firstDay), calendar.component(.year, from: day.start)]
        var pins: [Pin] = []
        for (entry, items) in zip(channel.fixed, programmes) where !items.isEmpty && entry.airs(onWeekday: weekday, date: date) {
            let before = entry.airings(before: day.index, firstWeekday: firstWeekday,
                                       dayOf: { dayIndex(of: $0, in: $1, calendar: calendar, firstDay: day.firstDay) },
                                       years: years.min()!...years.max()!)
            for (i, minutes) in entry.times.enumerated() {
                // A time the clocks skip (spring forward) moves to the next one that exists.
                guard let start = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day.start,
                                                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
                else { continue }
                pins.append(Pin(item: items[ChannelContent.wrap(before + i, items.count)], start: start))
            }
        }
        return pins.sorted { $0.start < $1.start }
    }

    /// The day number of `date` in `year`, or nil if that year has no such
    /// date (February 29).
    private func dayIndex(of date: FixedProgramme.MonthDay, in year: Int, calendar: Calendar, firstDay: Date) -> Int? {
        guard let day = calendar.date(from: DateComponents(year: year, month: date.month, day: date.day)),
              calendar.component(.day, from: day) == date.day else { return nil }
        return calendar.dateComponents([.day], from: firstDay, to: day).day
    }
}

/// A fixed programme marked `"exclusive": true` only airs at its set times:
/// the channel's shuffle leaves it out.
struct PinnedShowsStayOutOfTheShuffle: ContentRule {
    static let id = "pinned-shows-stay-out-of-the-shuffle"
    static let summary = "A fixed programme marked exclusive only airs at its set times, never in the shuffle."

    func keepsInShuffle(_ item: MediaItem, on channel: Channel) -> Bool {
        !channel.fixed.contains { $0.exclusive && $0.matches(item) }
    }
}

/// A channel's `fixed` list must make sense before it loads: a time zone to
/// read the times in, at least one time each, and no two programmes at the
/// same time on a day they share. (Whether each one finishes before the next
/// set time depends on the library; one that wouldn't is left out that day.)
struct FixedTimesAreValid: ChannelRule {
    static let id = "fixed-times-are-valid"
    static let summary = "Fixed programmes need a time zone, and no two may share a time on the same day."

    func problems(with channel: Channel) -> [String] {
        guard !channel.fixed.isEmpty else { return [] }
        var problems: [String] = []
        if channel.timeZone == nil {
            problems.append("Channel \(channel.number): \"fixed\" programmes need a \"timeZone\", such as \"America/New_York\".")
        }
        for (i, entry) in channel.fixed.enumerated() {
            if entry.times.isEmpty {
                problems.append("Channel \(channel.number): a fixed programme has no times in \"at\".")
            }
            problems += entry.clashes(with: Array(channel.fixed.dropFirst(i + 1))).map {
                "Channel \(channel.number): two fixed programmes at \(FixedProgramme.text(forMinutes: $0))."
            }
        }
        return problems
    }
}
