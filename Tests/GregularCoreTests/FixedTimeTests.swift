import Foundation
import Testing
@testable import GregularCore

/// Programmes at set local times (TODO.md item 2, now built).
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
        #expect(c.timeZone == Self.zone)
        #expect(c.fixed[0] == FixedProgramme(match: .series("Alpha"), times: [18 * 60, 18 * 60 + 30]))
        #expect(c.fixed[1] == FixedProgramme(match: .item("Laughs"), times: [20 * 60], weekdays: [7],
                                             dates: [.init(month: 2, day: 2)], exclusive: true))
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

    @Test func theShuffleFillsTheGapsWithNoOverlaps() throws {
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

    @Test func anExclusiveProgrammeOnlyAirsAtItsTimes() throws {
        let s = try schedule(#"{ "item": "Laughs", "at": ["20:00"], "days": ["Sat"], "exclusive": true }"#)
        let week = s.programmes(from: local(day: 60, 0), to: local(day: 74, 0))
        let laughs = week.filter { $0.item.name == "Laughs" }
        #expect(laughs.count == 2)
        #expect(laughs.allSatisfy { calendar.component(.weekday, from: $0.start) == 7 && calendar.component(.hour, from: $0.start) == 20 })
    }

    @Test func aPinnedMovieIsNeverNextToItself() throws {
        // Two movies, one pinned but still in the shuffle.
        let movies = [Fixtures.movie("One", minutes: 95), Fixtures.movie("Two", minutes: 95)]
        let s = try schedule(#"{ "item": "One", "at": ["12:00", "20:00"] }"#, items: movies)
        let programmes = s.programmes(from: local(day: 10, 0), to: local(day: 20, 0))
        #expect(zip(programmes, programmes.dropFirst()).allSatisfy { $0.item.id != $1.item.id })
    }

    @Test func aProgrammeRunningPastMidnightPushesTheNextDayBack() throws {
        let s = try schedule(#"{ "item": "Explosions", "at": ["23:30"] }"#)   // 128 minutes, padded to 2:30
        let late = s.programme(at: local(day: 30, 23, 45))
        #expect(late.item.name == "Explosions" && late.start == local(day: 30, 23, 30))
        #expect(late.slotEnd == local(day: 31, 2, 0))
        let next = s.programme(at: local(day: 31, 2, 0))
        #expect(next.start == late.slotEnd)
    }

    @Test func tuningStillWalksAtMostTwoDays() throws {
        let items = (0..<5_000).map { MediaItem(id: "e\($0)", kind: .episode, name: "E\($0)", duration: 22 * 60, seriesID: "s\($0 % 50)", seriesName: "S\($0 % 50)") }
        let c = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: ScheduleEngineTests.CountingStrategy.id, seed: 3,
                        padToMinutes: 30, timeZone: Self.zone, fixed: [FixedProgramme(match: .series("S1"), times: [18 * 60, 19 * 60])])
        let s = try #require(ChannelSchedule(channel: c, items: items, fillerPool: [], strategy: ScheduleEngineTests.CountingStrategy()))
        ScheduleEngineTests.CountingStrategy.pulls = 0
        _ = s.tune(at: local(day: 200, 21))
        let run = 66 + ChannelSchedule.maxSkipsAtRunEnd + 1 + RuledStream.lookahead
        #expect(ScheduleEngineTests.CountingStrategy.pulls <= 2 * run)
    }
}
