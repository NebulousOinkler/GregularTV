import Foundation
import Testing
@testable import GregularCore

struct ScheduleEngineTests {
    let epoch = Channel.defaultEpoch
    let later = Date(timeIntervalSince1970: 1_790_000_000)

    private func schedule(_ items: [MediaItem] = Fixtures.library, strategy: String = RandomShuffle.id,
                          seed: UInt64 = 42, padTo: Int? = nil) throws -> ChannelSchedule {
        try #require(ChannelSchedule(channel: Fixtures.channel(strategy: strategy, seed: seed, padTo: padTo), items: items))
    }

    /// When the first day's first programme starts: after that day's time
    /// left over, a break just after the day boundary.
    private func firstProgramme(of s: ChannelSchedule) throws -> Date {
        try #require(s.programmes(from: epoch, to: epoch.addingTimeInterval(86_400)).first { $0.start >= epoch }).start
    }

    @Test func emptyChannelIsNil() {
        #expect(ChannelSchedule(channel: Fixtures.channel(), items: []) == nil)
        let noRuntime = MediaItem(id: "x", kind: .movie, name: "x", duration: 0)
        #expect(ChannelSchedule(channel: Fixtures.channel(), items: [noRuntime]) == nil)
    }

    // MARK: Runs

    @Test func runsAreADayUnlessAProgrammeIsLonger() throws {
        #expect(try schedule().run(containing: later).duration == 24 * 3600)
        let marathon = Fixtures.movie("Marathon", minutes: 1500)
        #expect(try schedule([marathon]).run(containing: later).duration == 48 * 3600, "A 25-hour programme needs a two-day run")
    }

    /// Every run starts at the day boundary (midnight Pacific), so on the days
    /// the clocks change a run is 23 or 25 hours.
    @Test func runsStartAtTheDayBoundaryThroughDaylightSaving() throws {
        let s = try schedule()
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = DayBoundary.standard.timeZone
        let springForward = pacific.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let fallBack = pacific.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        #expect(s.run(containing: springForward).duration == 23 * 3600)
        #expect(s.run(containing: fallBack).duration == 25 * 3600)
        for day in stride(from: 0.0, to: 400, by: 7) {
            let run = s.run(containing: later.addingTimeInterval(day * 86_400))
            for edge in [run.start, run.end] {
                let time = pacific.dateComponents([.hour, .minute, .second], from: edge)
                #expect(time.hour == DayBoundary.standard.hour && time.minute == DayBoundary.standard.minute
                        && time.second == 0, "\(edge)")
            }
            #expect(run.contains(later.addingTimeInterval(day * 86_400)))
        }
        #expect(s.run(containing: epoch).start == epoch && s.run(containing: epoch.addingTimeInterval(-1)).end == epoch)
    }

    /// A programme never crosses the day boundary; only the break after the
    /// day's last one may.
    /// The day boundary is one setting (`DayBoundary.standard`): the epoch
    /// follows from it, unchanged since it was midnight Pacific.
    @Test func theEpochIsTheFirstDaysBoundary() {
        #expect(Channel.defaultEpoch == DayBoundary.standard.firstDay)
        #expect(DayBoundary(timeZone: DayBoundary.standard.timeZone, hour: 0).firstDay
                == Date(timeIntervalSince1970: 1_704_096_000))   // 2024-01-01T00:00:00-08:00
    }

    /// Moved to 2 am, every day runs from 2 am to 2 am, with its programmes
    /// playing right up to 2 am. The day the clocks go forward has no 2 am,
    /// so that day starts at 3 am.
    @Test func theDayBoundaryCanMoveTo2AM() throws {
        let twoAM = DayBoundary(timeZone: DayBoundary.standard.timeZone, hour: 2)
        let channel = Channel(number: 1, name: "Late", source: AllItemsSource(), strategyID: RandomShuffle.id, seed: 42,
                              padToMinutes: 30, epoch: twoAM.firstDay)
        let s = try #require(ChannelSchedule(channel: channel, items: Fixtures.library))
        let calendar = twoAM.calendar
        for day in [0.0, 68, 69, 70, 120, 306, 307, 308] {   // 2024: clocks change on days 69 and 307
            let run = s.run(containing: twoAM.firstDay.addingTimeInterval(day * 86_400 + 12 * 3600))
            #expect([23, 24, 25].contains(run.duration / 3600))
            for edge in [run.start, run.end] {
                let time = calendar.dateComponents([.month, .day, .hour, .minute], from: edge)
                let springForward = time.month == 3 && time.day == 10
                #expect(time.hour == (springForward ? 3 : 2) && time.minute == 0, "\(edge)")
            }
            let programmes = s.programmes(from: run.start, to: run.end).filter { $0.start >= run.start && $0.start < run.end }
            #expect(programmes.last?.slotEnd ?? .distantPast >= run.end && (programmes.last?.end ?? .distantFuture) <= run.end)
        }
    }

    @Test func programmesEndByTheDayBoundary() throws {
        let s = try schedule()
        for airing in s.airings(from: later, to: later.addingTimeInterval(3 * 24 * 3600)) where !airing.isFiller {
            #expect(airing.end <= s.run(containing: airing.start).end)
        }
    }

    /// Each day's programmes play right up to the boundary: the last ends on it.
    @Test func eachDayEndsWithAProgrammeAtTheBoundary() throws {
        let s = try schedule()
        let airings = s.airings(from: later, to: later.addingTimeInterval(4 * 24 * 3600))
        // Compare whole milliseconds; Double seconds can differ in the last bit.
        func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince(epoch) * 1000).rounded()) }
        let ends = Set(airings.filter { !$0.isFiller }.map { ms($0.end) })
        var run = s.run(containing: later)
        for _ in 0..<3 {
            #expect(ends.contains(ms(run.end)))
            run = s.run(containing: run.end)
        }
    }

    @Test func airingsAreContiguousAcrossRuns() throws {
        let airings = try schedule().airings(from: later, to: later.addingTimeInterval(48 * 3600))
        #expect(airings.first!.start <= later)
        for (a, b) in zip(airings, airings.dropFirst()) {
            #expect(a.slotEnd == b.start)
        }
    }

    @Test func movieSlotsOnlyRoundUpToTheHalfHour() throws {
        // Mixed-length films in half-hour slots: the only longer gap is the
        // break after a day's last film, past the day boundary.
        let movies = (0..<40).map { Fixtures.movie("M\($0)", minutes: Double(85 + ($0 * 23) % 70)) }
        let s = try schedule(movies, strategy: ShuffledShows.id, padTo: 30)
        for airing in s.airings(from: later, to: later.addingTimeInterval(3 * 24 * 3600)) {
            let isLastInRun = airing.slotEnd >= s.run(containing: airing.start).end
            if !isLastInRun {
                #expect(airing.slotEnd.timeIntervalSince(airing.end) < 30 * 60)
            }
        }
    }

    @Test func tuneAgreesWithGuide() throws {
        let s = try schedule(strategy: ShuffledSeriesInOrder.id)
        for airing in s.airings(from: later, to: later.addingTimeInterval(12 * 3600)) {
            let midpoint = airing.start.addingTimeInterval(airing.item.duration / 2)
            #expect(s.tune(at: midpoint).airing == airing)
        }
    }

    @Test func tuningAsAProgrammeStartsIsOffsetZero() throws {
        let s = try schedule()
        let start = try firstProgramme(of: s)
        let tuning = s.tune(at: start)
        #expect(tuning.offset == 0)
        #expect(tuning.airing.start == start)
    }

    @Test func offsetIsTimeSinceAiringStarted() throws {
        let s = try schedule(Fixtures.series("Alpha", seasons: 2, episodes: 5), strategy: SequentialBySeries.id)
        let tuning = s.tune(at: try firstProgramme(of: s).addingTimeInterval(23 * 60))
        #expect(tuning.airing.item.id == "Alpha-s1e2")
        #expect(tuning.offset == 60)
    }

    @Test func sameAnswerRegardlessOfInputOrder() throws {
        #expect(try schedule(Fixtures.library).tune(at: later) == schedule(Fixtures.library.reversed()).tune(at: later))
    }

    @Test func differentSeedsGiveDifferentSchedules() throws {
        let window = (later, later.addingTimeInterval(24 * 3600))
        #expect(try schedule(seed: 1).airings(from: window.0, to: window.1).map(\.item.id)
                != schedule(seed: 2).airings(from: window.0, to: window.1).map(\.item.id))
    }

    @Test func timesBeforeEpochStillWork() throws {
        let before = epoch.addingTimeInterval(-3.7 * 3600)
        let tuning = try schedule().tune(at: before)
        #expect(tuning.offset >= 0)
        #expect(tuning.airing.start <= before && before < tuning.airing.slotEnd)
    }

    @Test func sequentialPlaysBackToBack() throws {
        // 100 half-hour episodes: 8 in the first four hours.
        let s = try schedule(Fixtures.series("Long", seasons: 1, episodes: 100, minutes: 30), strategy: SequentialBySeries.id)
        let numbers = s.airings(from: epoch, to: epoch.addingTimeInterval(4 * 3600)).map { $0.item.episodeNumber! }
        #expect(numbers == Array(1...8))
    }

    // MARK: Padding and gaps

    /// A padded channel with commercials, so films get mid-rolls.
    private func withCommercials(_ items: [MediaItem], strategy: String = SequentialBySeries.id) throws -> ChannelSchedule {
        let ads = (0..<6).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 30 + Double($0) * 15) }
        let channel = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: strategy,
                              seed: 42, padToMinutes: 30, fillerID: ShuffledCommercials.id)
        return try #require(ChannelSchedule(channel: channel, items: items, fillerPool: ads))
    }

    @Test func everyProgrammeStartsOnTheHalfHour() throws {
        for s in [try schedule(padTo: 30), try withCommercials(Fixtures.library, strategy: RandomShuffle.id)] {
            for programme in s.programmes(from: later, to: later.addingTimeInterval(24 * 3600)) {
                #expect(programme.start.timeIntervalSince(epoch).truncatingRemainder(dividingBy: 1800) == 0)
                #expect(programme.slotEnd.timeIntervalSince(programme.end) < 1800)
            }
        }
    }

    @Test func episodesHaveTheirWholeBreakAfterThem() throws {
        let s = try withCommercials(Fixtures.series("Drama", seasons: 1, episodes: 6, minutes: 44))
        let slot = s.airings(from: epoch, to: epoch.addingTimeInterval(3600 - 1))
        #expect(slot.filter { !$0.isFiller }.count == 1, "No mid-rolls in an episode")
        #expect(slot[0].end == epoch.addingTimeInterval(44 * 60))
        #expect(slot.dropFirst().allSatisfy { $0.isFiller }, "16 minutes of commercials after it")
    }

    @Test(arguments: [(44.0, 0), (59, 0), (65, 2), (70, 1), (75, 1), (82, 0), (95, 2)])
    func episodesOfAnHourOrMoreGetMidRollsLikeFilms(minutes: Double, midRolls: Int) throws {
        let s = try withCommercials(Fixtures.series("Epic", seasons: 1, episodes: 3, minutes: minutes))
        let programme = s.programme(at: epoch)
        let parts = s.airings(from: epoch, to: programme.slotEnd.addingTimeInterval(-1)).filter { !$0.isFiller }
        #expect(parts.count == midRolls + 1)
        #expect(abs(parts.map(\.length).reduce(0, +) - minutes * 60) < 0.01, "The whole episode plays")
        #expect(parts.allSatisfy { $0.programmeStart == epoch })
    }

    /// The parts and breaks of the first day's first film's slot, and where it starts.
    private func filmSlot(minutes: Double) throws -> (parts: [Airing], breaks: [DateInterval], slotEnd: Date, start: Date) {
        let film = Fixtures.movie("Film", minutes: minutes)
        let s = try withCommercials([film])
        let start = try firstProgramme(of: s)
        let programme = s.programme(at: start)
        let airings = s.airings(from: start, to: programme.slotEnd.addingTimeInterval(-1))
        let parts = airings.filter { !$0.isFiller }
        // Each break: from a part's end to the next part (or the next programme).
        let breaks = parts.map { DateInterval(start: $0.end, end: nextStart(after: $0, in: airings, slotEnd: programme.slotEnd)) }
        return (parts, breaks, programme.slotEnd, start)
    }

    private func nextStart(after part: Airing, in airings: [Airing], slotEnd: Date) -> Date {
        airings.first { !$0.isFiller && $0.start > part.start }?.start ?? slotEnd
    }

    @Test(arguments: [(95.0, 2), (100, 1), (105, 1), (91, 2), (78, 1), (125, 2), (82, 0), (58, 0),
                      // Short films: parts of at least 15 minutes, so fewer mid-rolls, or none.
                      (35, 1), (40, 1), (13, 0), (2, 0)])
    func filmsGetUpToTwoMidRollsOfTenMinutesOrLess(minutes: Double, midRolls: Int) throws {
        let (parts, breaks, slotEnd, start) = try filmSlot(minutes: minutes)
        #expect(parts.count == midRolls + 1)
        // The whole film plays, each part resuming where the last stopped.
        var resumeAt: TimeInterval = 0
        for part in parts {
            #expect(abs(part.mediaOffset - resumeAt) < 0.01)
            resumeAt += part.length
        }
        #expect(abs(resumeAt - minutes * 60) < 0.01)
        #expect(parts.allSatisfy { $0.programmeStart == start })
        // Mid-rolls are 10 minutes or less, with at least 15 minutes of film
        // between breaks; all the breaks together fill the half-hour slot.
        for midRoll in breaks.dropLast() { #expect(midRoll.duration <= 600 && midRoll.duration > 0) }
        if parts.count > 1 { #expect(parts.allSatisfy { $0.length >= 15 * 60 }) }
        let total = breaks.reduce(0) { $0 + $1.duration }
        #expect(abs(total - (slotEnd.timeIntervalSince(start) - minutes * 60)) < 0.01)
        #expect(total < 1800)
        #expect(slotEnd.timeIntervalSince(epoch).truncatingRemainder(dividingBy: 1800) == 0)
    }

    @Test func noBreakHasMoreThanTwentyMinutesOfCommercials() throws {
        // A 5-minute episode leaves 25 minutes: 20 of commercials, then blank until the half hour.
        let s = try withCommercials(Fixtures.series("Short", seasons: 1, episodes: 4, minutes: 5))
        let slot = s.airings(from: epoch, to: epoch.addingTimeInterval(30 * 60 - 1))
        let clips = slot.filter(\.isFiller)
        let lastClip = try #require(clips.last)
        #expect(lastClip.end <= epoch.addingTimeInterval(25 * 60), "Commercials stop 20 minutes into the break")
        #expect(lastClip.end > epoch.addingTimeInterval(24 * 60), "…and fill it until then")
        #expect(lastClip.slotEnd == epoch.addingTimeInterval(30 * 60), "Blank to the next programme")
        #expect(s.tune(at: epoch.addingTimeInterval(27 * 60)).isInPadding, "The Up next card, not a commercial")
        // Across a day of mixed programmes, no run of commercials passes 20 minutes.
        let mixed = try withCommercials(Fixtures.library + [Fixtures.movie("Tiny", minutes: 3)], strategy: RandomShuffle.id)
        let day = mixed.airings(from: epoch, to: epoch.addingTimeInterval(24 * 3600))
        var run: TimeInterval = 0
        for airing in day {
            run = airing.isFiller ? run + airing.length : 0
            #expect(run <= 20 * 60)
        }
    }

    @Test func withCommercialsOffAFilmsMidRollsAreTheSameButBlank() throws {
        let film = Fixtures.movie("Film", minutes: 92)
        let on = try withCommercials([film])
        let off = try schedule([film], padTo: 30)   // no filler
        let window = (epoch, epoch.addingTimeInterval(120 * 60 - 1))
        let onParts = on.airings(from: window.0, to: window.1).filter { !$0.isFiller }
        let offAirings = off.airings(from: window.0, to: window.1)
        #expect(!offAirings.contains { $0.isFiller })
        #expect(offAirings.count == 3, "Two mid-rolls, blank")
        #expect(offAirings.map(\.start) == onParts.map(\.start))
        #expect(offAirings.map(\.mediaOffset) == onParts.map(\.mediaOffset))
    }

    @Test func aSplitFilmIsOneProgrammeInTheGuideAndOnScreen() throws {
        let s = try withCommercials([Fixtures.movie("Film", minutes: 92)])
        let programme = s.programme(at: epoch.addingTimeInterval(40 * 60))   // in a mid-roll or part 2
        #expect(programme.start == epoch)
        #expect(programme.slotEnd == epoch.addingTimeInterval(120 * 60))
        #expect(programme.end > epoch.addingTimeInterval(92 * 60), "Ends after its mid-rolls, not at 92 minutes")
        #expect(s.programmes(from: epoch, to: epoch.addingTimeInterval(120 * 60 - 1)).count == 1)
        // During a mid-roll: the film's still on, and the break ends at its next part.
        let parts = s.airings(from: epoch, to: epoch.addingTimeInterval(120 * 60 - 1)).filter { !$0.isFiller }
        let midRoll = parts[0].end.addingTimeInterval(30)
        #expect(s.nowShowing(at: midRoll) == .programme(programme))
        #expect(s.commercialBreak(at: midRoll)?.end == parts[1].start)
    }

    @Test func nowShowingTellsProgrammesFromBreaks() throws {
        // A 22-minute episode padded to 30 minutes: minutes 22–30 are a break.
        let s = try schedule([Fixtures.episode("Solo", s: 1, e: 1)], padTo: 30)
        let programme = s.programme(at: epoch)
        #expect(s.nowShowing(at: epoch.addingTimeInterval(22 * 60 - 1)) == .programme(programme))
        let inBreak = s.nowShowing(at: epoch.addingTimeInterval(22 * 60))
        guard case .inBreak(let ended, let next) = inBreak else {
            Issue.record("Expected a break, not \(inBreak)")
            return
        }
        #expect(ended == programme)
        #expect(next.start == epoch.addingTimeInterval(30 * 60) && !next.isFiller)
        #expect(inBreak.breakSpan == DateInterval(start: programme.end, end: next.start))
        #expect(s.nowShowing(at: next.start) == .programme(next))
        // No padding: never a break.
        let plain = try schedule([Fixtures.episode("Solo", s: 1, e: 1)])
        #expect(plain.nowShowing(at: epoch.addingTimeInterval(22 * 60)).breakSpan == nil)
    }

    @Test func tuningDuringPaddingIsFlagged() throws {
        // A 22-minute episode padded to 30 minutes: minutes 22–30 are padding.
        let s = try schedule([Fixtures.episode("Solo", s: 1, e: 1)], padTo: 30)
        #expect(!s.tune(at: epoch.addingTimeInterval(21 * 60)).isInPadding)
        #expect(s.tune(at: epoch.addingTimeInterval(25 * 60)).isInPadding)
        #expect(s.tune(at: epoch.addingTimeInterval(31 * 60)).offset == 60)
    }

    @Test func aDaysLeftoverIsABreakJustAfterTheBoundary() throws {
        // 50-minute episodes play back to back: 28 fit in a day, leaving 40
        // minutes, which come first: the day's programmes end on the boundary.
        let s = try schedule(Fixtures.series("Fifty", seasons: 1, episodes: 6, minutes: 50), strategy: SequentialBySeries.id)
        let dayEnd = epoch.addingTimeInterval(24 * 3600)
        let day = s.airings(from: epoch, to: dayEnd - 1).filter { $0.start >= epoch }
        #expect(day.count == 28)
        #expect(day.first!.start == epoch.addingTimeInterval(40 * 60))
        #expect(day.dropLast().allSatisfy { $0.slotEnd == $0.end }, "No gaps between the day's programmes")
        #expect(day.last!.end == dayEnd)
        // The 40 minutes are the break after the day before's last episode.
        let before = s.programme(at: epoch)
        #expect(before.end == epoch && before.slotEnd == day.first!.start)
        // And after this day's last: the next day's leftover, the same 40 minutes.
        #expect(s.programme(at: dayEnd).slotEnd == dayEnd.addingTimeInterval(40 * 60))
    }

    // MARK: Laziness

    /// Counts how many programmes the engine pulls.
    final class CountingStrategy: ScheduleStrategy, @unchecked Sendable {
        static let id = "counting"
        static let displayName = "Counting"
        nonisolated(unsafe) static var pulls = 0
        init() {}
        func programmes(from content: ChannelContent, startingAt position: Int, rng: SeededRandom) -> AnyIterator<MediaItem> {
            var position = position
            return AnyIterator {
                Self.pulls += 1
                defer { position += 1 }
                return content.items[ChannelContent.wrap(position, content.items.count)]
            }
        }
    }

    @Test func pullsAtMostTwoDaysOfProgrammesWhateverTheLibrarySize() throws {
        func pullsToTune(libraryOf count: Int) throws -> Int {
            let items = (0..<count).map { MediaItem(id: "e\($0)", kind: .episode, name: "E", duration: 22 * 60) }
            let s = try #require(ChannelSchedule(channel: Fixtures.channel(), items: items, fillerPool: [],
                                                 strategy: CountingStrategy()))
            CountingStrategy.pulls = 0
            _ = s.tune(at: later)
            return CountingStrategy.pulls
        }
        let small = try pullsToTune(libraryOf: 200)
        let huge = try pullsToTune(libraryOf: 20_000)
        #expect(small == huge, "Work depends on the time of day, not the library size")
        // This run and the one before it (for what aired last): each a day of
        // 22-minute programmes, plus any passed over at its end or held back by a rule.
        let run = 66 + ChannelSchedule.maxSkipsAtRunEnd + 1 + RuledStream.lookahead
        #expect(huge <= 2 * run, "At most two runs")
    }

    @Test func noProgrammeRepeatsBackToBackWithinARun() throws {
        // 60 movies of mixed lengths: a day holds far fewer, so none should air twice in a run.
        let movies = (0..<60).map { Fixtures.movie("M\($0)", minutes: Double(80 + ($0 * 37) % 90)) }
        for strategy in [RandomShuffle.id, ShuffledShows.id] {
            let s = try schedule(movies, strategy: strategy, padTo: 30)
            let run = s.run(containing: Channel.defaultEpoch.addingTimeInterval(3.5 * 86_400))
            // Whole programmes: the parts of a film split by mid-roll breaks aren't repeats.
            let day = s.programmes(from: run.start, to: run.end.addingTimeInterval(-1))
            #expect(Set(day.map(\.item.id)).count == day.count, "\(strategy) repeated a movie within a run")
        }
    }

    /// A channel of one very short clip, with no half-hour slots, used to lay
    /// out tens of thousands of airings a day, and look ahead 64 items for
    /// each, which froze the channel editor's preview. Slots are now at least
    /// `shortestSlot`, and a single programme has no sequence rules to try.
    @Test func veryShortProgrammesKeepADayShort() throws {
        let clip = MediaItem(id: "e", kind: .episode, name: "Sting", duration: 1, seriesID: "s", seriesName: "S",
                             seasonNumber: 1, episodeNumber: 1)
        let tiny = MediaItem(id: "ad", kind: .video, name: "Blip", duration: 1)
        for padTo in [nil, 30] {
            let s = try #require(ChannelSchedule(channel: Fixtures.channel(strategy: ShuffledShows.id, padTo: padTo),
                                                 items: [clip], fillerPool: [tiny]))
            let day = s.programmes(from: later, to: later.addingTimeInterval(24 * 3600))
            #expect(day.count <= 24 * 60 / 5 + 1)
            #expect(day.allSatisfy { $0.slotEnd.timeIntervalSince($0.start) >= 5 * 60 })
            #expect(s.fillerPool.isEmpty, "A one-second commercial isn't used")
            #expect(s.programmeRules.isEmpty, "One programme: no rules to try")
        }
    }

    @Test func floorDivideRoundsTowardsNegativeInfinity() {
        #expect(ChannelSchedule.floorDivide(7, 3) == 2)
        #expect(ChannelSchedule.floorDivide(-7, 3) == -3)
        #expect(ChannelSchedule.floorDivide(-6, 3) == -2)
        #expect(ChannelSchedule.floorDivide(0, 3) == 0)
    }
}

extension ScheduleEngineTests {
    /// Where one day meets the next, the new day's first programme may be the
    /// film that just ended (the day's stream starts at an estimate). A stand-in
    /// takes its slot, and the slot keeps its times, so the stand-in must fill
    /// it: another film, not a half-hour episode followed by an hour and a half
    /// of commercials.
    @Test func aStandInAtMidnightFillsTheSlot() throws {
        // Every padded length has two films, so there's always one that fills.
        let films = [110, 115, 140, 145, 160, 170].map { Fixtures.movie("F\($0)", minutes: Double($0)) }
        let episodes = ["A", "B", "C"].flatMap { Fixtures.series($0, seasons: 1, episodes: 12, minutes: 26) }
        let json = #"[{ "number": 1, "name": "Mix", "source": { "type": "all" }, "strategy": "shuffled-mix", "films": 0.35, "seed": 1, "padTo": 30 }]"#
        let lineup = try ChannelLineup.load(from: Data(json.utf8))
        var opening = 0
        for code in ["7KQM2-X9PDA", "2B8DQ-K4MWT", "Z3H5P-6JC2R"].compactMap(ScheduleCode.init) {
            let schedule = try #require(lineup.schedules(for: films + episodes, fillerPool: [], code: code).first)
            let start = schedule.run(containing: Channel.defaultEpoch.addingTimeInterval(400 * 86_400)).start
            for programme in schedule.programmes(from: start, to: start.addingTimeInterval(60 * 86_400))
            where programme.start == schedule.run(containing: programme.start).start {
                opening += 1
                let left = programme.slotEnd.timeIntervalSince(programme.end)
                #expect(left < 30 * 60, "\(programme.item.name) opens the day with \(Int(left / 60)) min left in its slot")
            }
        }
        #expect(opening > 150, "Checked the start of every day")
    }
}
