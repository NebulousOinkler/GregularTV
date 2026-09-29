import Foundation

/// A set time's programme airs at exactly its local times, on its days, laid
/// over the shared schedule. A series plays its next episode at each airing:
/// its own count of airings since the channel's clock started, worked out
/// from the calendar, so any day can be found without replaying the ones before.
struct PinnedProgrammes: PinRule {
    static let id = "pinned-programmes"
    static let summary = "Set times air at exactly their local times, over the shared schedule, each series advancing one episode per airing."

    func pins(for entry: FixedProgramme, programmes: [MediaItem], on day: ScheduleDay) -> [Pin] {
        let calendar = day.calendar
        let parts = calendar.dateComponents([.month, .day], from: day.start)
        let date = FixedProgramme.MonthDay(month: parts.month ?? 1, day: parts.day ?? 1)
        guard !programmes.isEmpty, entry.airs(onWeekday: calendar.component(.weekday, from: day.start), date: date) else { return [] }
        let years = [calendar.component(.year, from: day.firstDay), calendar.component(.year, from: day.start)]
        let before = entry.airings(before: day.index, firstWeekday: calendar.component(.weekday, from: day.firstDay),
                                   dayOf: { dayIndex(of: $0, in: $1, calendar: calendar, firstDay: day.firstDay) },
                                   years: years.min()!...years.max()!)
        return entry.times.enumerated().compactMap { i, minutes in
            // A time the clocks skip (spring forward) moves to the next one that exists.
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day.start,
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
                .map { Pin(item: programmes[ChannelContent.wrap(before + i, programmes.count)], start: $0) }
        }
    }

    /// The day number of `date` in `year`, or nil if that year has no such
    /// date (February 29).
    private func dayIndex(of date: FixedProgramme.MonthDay, in year: Int, calendar: Calendar, firstDay: Date) -> Int? {
        guard let day = calendar.date(from: DateComponents(year: year, month: date.month, day: date.day)),
              calendar.component(.day, from: day) == date.day else { return nil }
        return calendar.dateComponents([.day], from: firstDay, to: day).day
    }
}

/// A set time marked `"exclusive": true` keeps its programme to its set
/// times: wherever the shared schedule airs it otherwise, a stand-in takes
/// that slot. Nothing else in the shared schedule moves.
struct ExclusiveProgrammesOnlyAtSetTimes: CoverRule {
    static let id = "exclusive-programmes-only-at-set-times"
    static let summary = "An exclusive set programme only airs at its set times: its other airings get a stand-in."

    func covers(_ item: MediaItem, on channel: Channel) -> Bool {
        channel.fixed.contains { $0.exclusive && $0.matches(item) }
    }
}

/// A channel's set times must make sense before it loads: a time zone to
/// read them in, at least one time each, and no two programmes at the same
/// time on a day they share. (One that overlaps an earlier one's slot, which
/// depends on the library, is left out that day.)
struct FixedTimesAreValid: ChannelRule {
    static let id = "fixed-times-are-valid"
    static let summary = "Set times need a time zone, and no two may share a time on the same day."

    func problems(with channel: Channel) -> [String] {
        var problems: [String] = []
        if channel.fixed.contains(where: { $0.timeZone == nil }) {
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
