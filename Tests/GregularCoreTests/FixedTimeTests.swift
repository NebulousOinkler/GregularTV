import Foundation
import Testing
@testable import GregularCore

/// Programmes at set local times, laid over the shared schedule.
struct FixedTimeTests {
    static let zone = TimeZone(identifier: "America/New_York")!
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        return calendar
    }

    /// A channel from `channels.json` text, so decoding is tested too.
    private func channel(_ fixed: String, strategy: String = ShuffledShows.id, padTo: Int = 30,
                         zone: String? = "America/New_York") throws -> Channel {
        let zoneField = zone.map { #""timeZone": "\#($0)", "# } ?? ""
        let json = #"[{ "number": 1, "name": "T", "source": { "type": "all" }, "strategy": "\#(strategy)", "seed": 3, "padTo": \#(padTo), \#(zoneField)"fixed": [\#(fixed)] }]"#
        return try #require(try ChannelLineup.load(from: Data(json.utf8)).channels.first)
    }

    private func schedule(_ fixed: String, items: [MediaItem] = Fixtures.library, strategy: String = ShuffledShows.id) throws -> ChannelSchedule {
        try #require(ChannelSchedule(channel: try channel(fixed, strategy: strategy), items: items))
    }

    /// `hour:minute` local time on `day` (1 January 2026 + `day` days).
    private func local(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let first = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let date = calendar.date(byAdding: .day, value: day, to: first)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    // MARK: Configuration

    @Test func decodesSeriesItemsDaysAndExclusive() throws {
        let c = try channel(#"{ "series": "Alpha", "at": ["18:30", "18:00"] }, { "item": "Laughs", "at": ["20:00"], "days": ["Sat", "Feb 2"], "exclusive": true }"#)
        #expect(c.fixed[0] == FixedProgramme(match: .series("Alpha"), times: [18 * 60, 18 * 60 + 30], timeZone: Self.zone))
        #expect(c.fixed[1] == FixedProgramme(match: .item("Laughs"), times: [20 * 60], weekdays: [7],
                                             dates: [.init(month: 2, day: 2)], exclusive: true, timeZone: Self.zone))
    }

    @Test(arguments: [
        #"{ "series": "Alpha", "at": ["25:00"] }"#,                                   // not a time
        #"{ "series": "Alpha", "at": ["18:00"], "days": ["Funday"] }"#,               // not a day
        #"{ "series": "Alpha", "item": "Laughs", "at": ["18:00"] }"#,                 // two things
        #"{ "series": "Alpha", "at": [] }"#,                                          // no times
        #"{ "series": "Alpha", "at": ["18:00"] }, { "item": "Laughs", "at": ["18:00"] }"#,   // a clash
        #"{ "series": "Alpha", "at": ["18:00", "18:00"] }"#,                          // a clash with itself
    ])
    func rejectsBadConfiguration(fixed: String) {
        #expect(throws: (any Error).self) { try channel(fixed) }
    }

    @Test func needsATimeZone() {
        #expect(throws: ChannelLineup.LoadError.self) { try channel(#"{ "series": "Alpha", "at": ["18:00"] }"#, zone: nil) }
        #expect(throws: (any Error).self) { try channel(#"{ "series": "Alpha", "at": ["18:00"] }"#, zone: "Mars/Olympus") }
    }

    @Test func differentDaysMayShareATime() throws {
        _ = try channel(#"{ "series": "Alpha", "at": ["18:00"], "days": ["Mon"] }, { "item": "Laughs", "at": ["18:00"], "days": ["Tue"] }"#)
    }

    // MARK: Placement

    @Test func airsAtExactlyItsTimesEveryDayForAYearAcrossClockChanges() throws {
        let s = try schedule(#"{ "series": "Alpha", "at": ["18:00", "18:30"] }"#)
        for day in 0..<365 {   // 2026: clocks change on 8 March and 1 November
            for minute in [0, 30] {
                let time = local(day: day, 18, minute)
                let programme = s.programme(at: time.addingTimeInterval(60))
                #expect(programme.item.seriesName == "Alpha" && programme.start == time, "day \(day) 18:\(minute)")
            }
        }
    }

    @Test func aSeriesAdvancesOneEpisodePerAiring() throws {
        let s = try schedule(#"{ "series": "Alpha", "at": ["18:00", "18:30"] }"#)
        let alpha = Fixtures.series("Alpha", seasons: 2, episodes: 5).map(\.id)   // aired order
        // Each looked up on its own, so every day's count comes from the calendar.
        let airings = (100..<115).flatMap { day in [0, 30].map { s.programme(at: local(day: day, 18, $0)).item.id } }
        let positions = airings.map { alpha.firstIndex(of: $0)! }
        #expect(zip(positions, positions.dropFirst()).allSatisfy { ($0 + 1) % alpha.count == $1 })
    }

    @Test func daysLimitWhenItAirsAndEpisodesStillAdvanceOnePerAiring() throws {
        // Exclusive, so Charlie only airs at its set times.
        let s = try schedule(#"{ "series": "Charlie", "at": ["21:00"], "days": ["Mon", "Thu", "Jul 4"], "exclusive": true }"#)
        let charlie = Fixtures.series("Charlie", seasons: 3, episodes: 4, minutes: 30).map(\.id)
        var positions: [Int] = []
        for day in 150..<200 {
            let programme = s.programme(at: local(day: day, 21))
            let date = local(day: day, 21)
            let weekday = calendar.component(.weekday, from: date)
            let isJuly4 = calendar.dateComponents([.month, .day], from: date) == DateComponents(month: 7, day: 4)
            let pinned = programme.start == date && programme.item.seriesName == "Charlie"
            #expect(pinned == ([2, 5].contains(weekday) || isJuly4), "day \(day)")
            if pinned { positions.append(charlie.firstIndex(of: programme.item.id)!) }
        }
        #expect(positions.count > 10)
        #expect(zip(positions, positions.dropFirst()).allSatisfy { ($0 + 1) % charlie.count == $1 })
    }

    @Test func slotsStillMeetBackToBack() throws {
        let s = try schedule(#"{ "series": "Alpha", "at": ["18:00", "18:30"] }, { "item": "Explosions", "at": ["20:00"] }"#)
        let airings = s.airings(from: local(day: 40, 0), to: local(day: 43, 0))
        for (a, b) in zip(airings, airings.dropFirst()) {
            #expect(a.slotEnd == b.start, "Back to back")
            #expect(a.end <= a.slotEnd)
        }
        for day in 40..<43 {
            #expect(airings.contains { !$0.isFiller && $0.start == local(day: day, 20) && $0.item.name == "Explosions" })
        }
    }

    // MARK: Over the shared schedule

    @Test func outsideTheSetTimesItsExactlyTheSharedSchedule() throws {
        // Episodes only, with a film set at 20:00: the film never airs in the shared schedule,
        // so nothing is covered and every other moment must match exactly.
        let shared = Fixtures.channel(strategy: ShuffledShows.id, itemTypes: [.episode], padTo: 30)
        let withSetTime = shared.adding([FixedProgramme(match: .item("Explosions"), times: [20 * 60, 7 * 60 + 15], timeZone: Self.zone)])
        let a = try #require(ChannelSchedule(channel: withSetTime, items: Fixtures.library))
        let c = try #require(ChannelSchedule(channel: shared, items: Fixtures.library))
        let windows = a.setTimeAirings(from: local(day: 50, 0), to: local(day: 53, 0))
        #expect(windows.count == 6)
        var compared = 0
        for minute in stride(from: 0, to: 3 * 24 * 60, by: 7) {
            let t = local(day: 50, 0).addingTimeInterval(Double(minute) * 60)
            let inWindow = windows.contains { $0.start <= t && t < $0.slotEnd }
            let ta = a.tune(at: t), tc = c.tune(at: t)
            if inWindow {
                #expect(ta.airing.item.name == "Explosions" || ta.airing.isFiller)
            } else {
                compared += 1
                // The same item, at the same point in it: joined partway through after a set time.
                #expect(ta.airing.item.id == tc.airing.item.id, "\(t)")
                #expect(abs((ta.airing.mediaOffset + ta.offset) - (tc.airing.mediaOffset + tc.offset)) < 0.01, "\(t)")
            }
        }
        #expect(compared > 400)
    }

    @Test func aProgrammeCutByASetTimeIsJoinedPartwayThroughAfterIt() throws {
        // A 22-minute set time at 18:15, inside a film's slot: its window runs to the half hour after, 19:00.
        let shared = Fixtures.channel(strategy: ShuffledShows.id, itemTypes: [.movie], padTo: 30)
        let a = try #require(ChannelSchedule(channel: shared.adding([FixedProgramme(match: .series("Alpha"), times: [18 * 60 + 15], timeZone: Self.zone)]),
                                             items: Fixtures.library))
        let c = try #require(ChannelSchedule(channel: shared, items: Fixtures.library))
        // A day when one film's slot runs from before 18:15 to after 19:00.
        let day = try #require((60..<120).first { day in
            let film = c.programme(at: local(day: day, 18, 14))
            return film.start < local(day: day, 18, 10) && film.slotEnd > local(day: day, 19, 1)
        })
        let before = c.programme(at: local(day: day, 18, 14))
        let after = a.programme(at: local(day: day, 19, 1))
        #expect(a.programme(at: local(day: day, 18, 20)).item.seriesName == "Alpha")
        #expect(after.item.id == before.item.id && after.start == local(day: day, 19), "The film carries on, joined partway")
        #expect(a.tune(at: local(day: day, 19, 1)).airing.mediaOffset > 0)
        #expect(a.programme(at: local(day: day, 18, 10)).slotEnd == local(day: day, 18, 15), "Cut at the set time")
    }

    @Test func anExclusiveProgrammesOtherAiringsGetAStandIn() throws {
        let s = try schedule(#"{ "item": "Laughs", "at": ["20:00"], "days": ["Sat"], "exclusive": true }"#)
        let week = s.programmes(from: local(day: 60, 0), to: local(day: 74, 0))
        let laughs = week.filter { $0.item.name == "Laughs" }
        #expect(laughs.count == 2)
        #expect(laughs.allSatisfy { calendar.component(.weekday, from: $0.start) == 7 && calendar.component(.hour, from: $0.start) == 20 })
    }

    @Test func aSetMovieIsNeverNextToItself() throws {
        // Two movies, one set at two times but also in the shared schedule.
        let movies = [Fixtures.movie("One", minutes: 95), Fixtures.movie("Two", minutes: 95)]
        let s = try schedule(#"{ "item": "One", "at": ["12:00", "20:00"] }"#, items: movies)
        let programmes = s.programmes(from: local(day: 10, 0), to: local(day: 20, 0))
        #expect(zip(programmes, programmes.dropFirst()).allSatisfy { $0.item.id != $1.item.id })
    }

    @Test func aSetProgrammeRunningPastMidnightThenRejoinsTheSharedSchedule() throws {
        let s = try schedule(#"{ "item": "Explosions", "at": ["23:30"] }"#)   // 128 minutes, padded to 2:30
        let late = s.programme(at: local(day: 30, 23, 45))
        #expect(late.item.name == "Explosions" && late.start == local(day: 30, 23, 30))
        #expect(late.slotEnd == local(day: 31, 2, 0))
        #expect(s.programme(at: local(day: 31, 2, 0)).start == local(day: 31, 2, 0))
    }

    @Test func tuningStillWalksAtMostTwoDays() throws {
        let items = (0..<5_000).map { MediaItem(id: "e\($0)", kind: .episode, name: "E\($0)", duration: 22 * 60, seriesID: "s\($0 % 50)", seriesName: "S\($0 % 50)") }
        let c = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: ScheduleEngineTests.CountingStrategy.id, seed: 3,
                        padToMinutes: 30, fixed: [FixedProgramme(match: .series("S1"), times: [18 * 60, 19 * 60], timeZone: Self.zone)])
        let s = try #require(ChannelSchedule(channel: c, items: items, fillerPool: [], strategy: ScheduleEngineTests.CountingStrategy()))
        ScheduleEngineTests.CountingStrategy.pulls = 0
        _ = s.tune(at: local(day: 200, 21))
        let run = 66 + ChannelSchedule.maxSkipsAtRunEnd + 1 + RuledStream.lookahead
        #expect(ScheduleEngineTests.CountingStrategy.pulls <= 2 * run)
    }
}
