import Foundation
import Testing
@testable import GregularCore

/// Random small channels, with and without programmes at set times, on every
/// strategy: the rules hold, walks agree, set times are kept, and at every
/// other time the channel is the shared schedule. (Tiny libraries are the
/// hard case: they leave the fewest ways to keep a rule.)
struct RandomChannelTests {
    static let zones = ["Europe/London", "America/New_York", "Australia/Sydney", "Asia/Tokyo"]
    static let strategies = StrategyRegistry.all.map { $0.id }

    struct Case {
        let channel: Channel
        let items: [MediaItem]
        let schedule: ChannelSchedule
        let calendar: Calendar
        let start: Date
    }

    /// A random channel, or nil when its shuffle has only one programme (a repeat is then unavoidable).
    static func randomCase(_ trial: Int, _ rng: inout SeededRandom) -> Case? {
        let movies = (0..<(1 + rng.int(below: 9))).map { Fixtures.movie("M\($0)", minutes: Double(40 + rng.int(below: 140))) }
        let shows = (0..<rng.int(below: 3)).flatMap { k in
            Fixtures.series("S\(k)", seasons: 1, episodes: 1 + rng.int(below: 6), minutes: Double([22, 30, 44, 60][rng.int(below: 4)]))
        }
        let items = movies + shows
        var fixed: [FixedProgramme] = []
        var used = Set<Int>()
        for _ in 0..<rng.int(below: 3) {
            let times = Set((0..<(1 + rng.int(below: 3))).map { _ in rng.int(below: 96) * 15 }).subtracting(used).sorted()
            guard !times.isEmpty else { continue }
            used.formUnion(times)
            let match: FixedProgramme.Match = !shows.isEmpty && rng.int(below: 2) == 0 ? .series("S0") : .item("M\(rng.int(below: movies.count))")
            fixed.append(FixedProgramme(match: match, times: times, weekdays: rng.int(below: 3) == 0 ? [2, 4, 6] : [],
                                        exclusive: rng.int(below: 4) == 0))
        }
        let zone = TimeZone(identifier: zones[trial % zones.count])!
        fixed = fixed.map { $0.in(zone) }
        let channel = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: strategies[trial % strategies.count],
                              seed: UInt64(trial), padToMinutes: rng.int(below: 2) == 0 ? 30 : nil, fixed: fixed)
        let shuffled = items.filter { item in !fixed.contains { $0.exclusive && $0.matches(item) } }
        guard Set(shuffled.map(\.id)).count > 1, let schedule = ChannelSchedule(channel: channel, items: items) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = Channel.defaultEpoch.addingTimeInterval(Double(rng.int(below: 1200)) * 86400 + Double(rng.int(below: 86400)))
        return Case(channel: channel, items: items, schedule: schedule, calendar: calendar, start: start)
    }

    @Test func theRulesHoldAndEveryWalkAgrees() {
        var rng = SeededRandom(seed: 991)
        var checked = 0
        for trial in 0..<80 {
            guard let c = Self.randomCase(trial, &rng) else { continue }
            checked += 1
            let week = c.schedule.programmes(from: c.start, to: c.start.addingTimeInterval(7 * 86400))
            // Set the same film at two times close together, and it may be on twice in a row: that's the user's choice.
            let setTimes = Set(c.schedule.setTimeAirings(from: c.start.addingTimeInterval(-86400), to: c.start.addingTimeInterval(8 * 86400)).map(\.start))
            for (a, b) in zip(week, week.dropFirst()) {
                let bothSet = setTimes.contains(a.start) && setTimes.contains(b.start)
                #expect(a.item.id != b.item.id || bothSet, "trial \(trial): \(a.item.name) twice at \(b.start)")
                #expect(a.slotEnd == b.start, "trial \(trial): back to back")
            }
            // Looked up on its own, each programme is the same as in the long walk
            // (every one on channels with set times, where covering makes this hardest).
            for programme in week.dropFirst().prefix(c.channel.fixed.isEmpty ? 20 : week.count) {
                let alone = c.schedule.programme(at: programme.start.addingTimeInterval(1))
                #expect(alone.item.id == programme.item.id && alone.start == programme.start, "trial \(trial)")
            }
        }
        #expect(checked > 50)
    }

    @Test func whatsPlayingIsWhatTheGuideShows() {
        // Films have mid-roll breaks, so a set time can end between two parts of one.
        var rng = SeededRandom(seed: 4242)
        var checked = 0
        for trial in 0..<80 {
            guard let c = Self.randomCase(trial, &rng), !c.channel.fixed.isEmpty else { continue }
            let cells = c.schedule.programmes(from: c.start, to: c.start.addingTimeInterval(2 * 86400))
            for minute in stride(from: 0, to: 2 * 24 * 60, by: 13) {
                let t = c.start.addingTimeInterval(Double(minute) * 60)
                let tuned = c.schedule.tune(at: t).airing
                guard !tuned.isFiller, let cell = cells.first(where: { $0.start <= t && t < $0.slotEnd }) else { continue }
                #expect(cell.item.id == tuned.item.id, "trial \(trial) at \(t): the guide shows \(cell.item.name), \(tuned.item.name) is on")
                #expect(c.schedule.programme(at: t).item.id == tuned.item.id, "trial \(trial) at \(t)")
                checked += 1
            }
        }
        #expect(checked > 3000)
    }

    @Test func setTimesAreKeptUnlessTheyClash() {
        var rng = SeededRandom(seed: 991)
        var pins = 0
        for trial in 0..<80 {
            guard let c = Self.randomCase(trial, &rng) else { continue }
            for day in 1..<5 {
                let midnight = c.calendar.startOfDay(for: c.start.addingTimeInterval(Double(day) * 86400))
                // This day's set times, and the day before's (one may run past midnight).
                var times: [(Date, FixedProgramme)] = []
                for date in [c.calendar.date(byAdding: .day, value: -1, to: midnight)!, midnight] {
                    let weekday = c.calendar.component(.weekday, from: date)
                    for entry in c.channel.fixed where entry.airsEveryDay || entry.weekdays.contains(weekday) {
                        times += entry.times.map { (c.calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: date)!, entry) }
                    }
                }
                var busyUntil = Date.distantPast
                var lastPinned: MediaItem?
                for (time, entry) in times.sorted(by: { $0.0 < $1.0 }) {
                    let programme = c.schedule.programme(at: time.addingTimeInterval(1))
                    if programme.start == time && entry.matches(programme.item) {
                        busyUntil = programme.slotEnd
                        lastPinned = programme.item
                        continue
                    }
                    // Left out only if it overlaps the one before, or is the same
                    // programme again straight after it.
                    let sameAgain = lastPinned.map { entry.matches($0) && time == busyUntil } ?? false
                    #expect(time < midnight || time < busyUntil || sameAgain, "trial \(trial): \(entry.match) at \(time)")
                }
                pins += times.count
            }
        }
        #expect(pins > 300)
    }

    @Test func atEveryOtherTimeItsTheSharedSchedule() {
        // Set times of films on channels of episodes: the films never air in the
        // shared schedule, so nothing is covered and every other moment must match.
        var rng = SeededRandom(seed: 5150)
        var compared = 0
        for trial in 0..<40 {
            let shows = (0..<(2 + rng.int(below: 3))).flatMap { k in
                Fixtures.series("S\(k)", seasons: 1, episodes: 2 + rng.int(below: 6), minutes: Double([22, 30, 44, 60][rng.int(below: 4)]))
            }
            let films = (0..<3).map { Fixtures.movie("F\($0)", minutes: Double(40 + rng.int(below: 140))) }
            let zone = TimeZone(identifier: Self.zones[trial % Self.zones.count])!
            let times = Set((0..<(1 + rng.int(below: 4))).map { _ in rng.int(below: 96) * 15 }).sorted()
            let shared = Channel(number: 1, name: "T", itemTypes: [.episode], source: AllItemsSource(),
                                 strategyID: Self.strategies[trial % Self.strategies.count], seed: UInt64(trial),
                                 padToMinutes: rng.int(below: 2) == 0 ? 30 : nil)
            let withSetTimes = shared.adding([FixedProgramme(match: .item("F\(rng.int(below: 3))"), times: times, timeZone: zone)])
            guard let a = ChannelSchedule(channel: withSetTimes, items: shows + films),
                  let c = ChannelSchedule(channel: shared, items: shows + films) else { continue }
            let start = Channel.defaultEpoch.addingTimeInterval(Double(rng.int(below: 1200)) * 86400 + Double(rng.int(below: 86400)))
            let windows = a.setTimeAirings(from: start.addingTimeInterval(-86400), to: start.addingTimeInterval(3 * 86400))
            for minute in stride(from: 0, to: 2 * 24 * 60, by: 11) {
                let t = start.addingTimeInterval(Double(minute) * 60)
                guard !windows.contains(where: { $0.start <= t && t < $0.slotEnd }) else { continue }
                let ta = a.tune(at: t), tc = c.tune(at: t)
                // Blank airtime after a programme looks the same whichever programme it follows.
                if t >= ta.airing.end && t >= tc.airing.end && !ta.airing.isFiller && !tc.airing.isFiller { continue }
                #expect(ta.airing.item.id == tc.airing.item.id, "trial \(trial) at \(t)")
                #expect(abs((ta.airing.mediaOffset + ta.offset) - (tc.airing.mediaOffset + tc.offset)) < 0.01, "trial \(trial) at \(t)")
                compared += 1
            }
        }
        #expect(compared > 5000)
    }
}
