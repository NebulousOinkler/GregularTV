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

    @Test func emptyChannelIsNil() {
        #expect(ChannelSchedule(channel: Fixtures.channel(), items: []) == nil)
        let noRuntime = MediaItem(id: "x", kind: .movie, name: "x", duration: 0)
        #expect(ChannelSchedule(channel: Fixtures.channel(), items: [noRuntime]) == nil)
    }

    // MARK: Runs

    @Test func runsAreADayUnlessAProgrammeIsLonger() throws {
        #expect(try schedule().runDuration == 24 * 3600)
        let marathon = Fixtures.movie("Marathon", minutes: 1500)
        #expect(try schedule([marathon]).runDuration == 25 * 3600, "A 25-hour programme needs a 25-hour run")
    }

    @Test func programmesNeverCrossARunBoundary() throws {
        let s = try schedule()
        let run = s.runDuration
        for airing in s.airings(from: later, to: later.addingTimeInterval(3 * 24 * 3600)) {
            let runStart = floor(airing.start.timeIntervalSince(epoch) / run) * run
            #expect(airing.slotEnd.timeIntervalSince(epoch) <= runStart + run)
        }
    }

    @Test func eachRunStartsWithAProgramme() throws {
        let s = try schedule()
        let airings = s.airings(from: later, to: later.addingTimeInterval(4 * 24 * 3600))
        // Compare whole milliseconds; Double seconds can differ in the last bit.
        let starts = Set(airings.filter { !$0.isFiller }.map { Int64(($0.start.timeIntervalSince(epoch) * 1000).rounded()) })
        let run = Int64(s.runDuration * 1000)
        let firstRun = (Int64(later.timeIntervalSince(epoch) * 1000) / run + 1) * run
        for k in 0..<3 {
            #expect(starts.contains(firstRun + Int64(k) * run))
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
        // Mixed-length films in half-hour slots: the only longer gap is at the end of a run.
        let movies = (0..<40).map { Fixtures.movie("M\($0)", minutes: Double(85 + ($0 * 23) % 70)) }
        let s = try schedule(movies, strategy: DerangedShows.id, padTo: 30)
        let run = s.runDuration
        for airing in s.airings(from: later, to: later.addingTimeInterval(3 * 24 * 3600)) {
            let isLastInRun = airing.slotEnd.timeIntervalSince(epoch).truncatingRemainder(dividingBy: run) == 0
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

    @Test func tuningAtEpochIsStartOfFirstProgramme() throws {
        let tuning = try schedule().tune(at: epoch)
        #expect(tuning.offset == 0)
        #expect(tuning.airing.start == epoch)
    }

    @Test func offsetIsTimeSinceAiringStarted() throws {
        let s = try schedule(Fixtures.series("Alpha", seasons: 2, episodes: 5), strategy: SequentialBySeries.id)
        let tuning = s.tune(at: epoch.addingTimeInterval(23 * 60))
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
                              seed: 42, padToMinutes: 30, fillerID: DerangedCommercials.id)
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

    /// The parts and breaks of the first film's slot.
    private func filmSlot(minutes: Double) throws -> (parts: [Airing], breaks: [DateInterval], slotEnd: Date) {
        let film = Fixtures.movie("Film", minutes: minutes)
        let s = try withCommercials([film])
        let programme = s.programme(at: epoch)
        let airings = s.airings(from: epoch, to: programme.slotEnd.addingTimeInterval(-1))
        let parts = airings.filter { !$0.isFiller }
        // Each break: from a part's end to the next part (or the next programme).
        let breaks = parts.map { DateInterval(start: $0.end, end: nextStart(after: $0, in: airings, slotEnd: programme.slotEnd)) }
        return (parts, breaks, programme.slotEnd)
    }

    private func nextStart(after part: Airing, in airings: [Airing], slotEnd: Date) -> Date {
        airings.first { !$0.isFiller && $0.start > part.start }?.start ?? slotEnd
    }

    @Test(arguments: [(95.0, 2), (100, 1), (105, 1), (91, 2), (78, 1), (125, 2), (82, 0), (58, 0),
                      // Short films: parts of at least 15 minutes, so fewer mid-rolls, or none.
                      (35, 1), (40, 1), (13, 0), (2, 0)])
    func filmsGetUpToTwoMidRollsOfTenMinutesOrLess(minutes: Double, midRolls: Int) throws {
        let (parts, breaks, slotEnd) = try filmSlot(minutes: minutes)
        #expect(parts.count == midRolls + 1)
        // The whole film plays, each part resuming where the last stopped.
        var resumeAt: TimeInterval = 0
        for part in parts {
            #expect(abs(part.mediaOffset - resumeAt) < 0.01)
            resumeAt += part.length
        }
        #expect(abs(resumeAt - minutes * 60) < 0.01)
        #expect(parts.allSatisfy { $0.programmeStart == epoch })
        // Mid-rolls are 10 minutes or less, with at least 15 minutes of film
        // between breaks; all the breaks together fill the half-hour slot.
        for midRoll in breaks.dropLast() { #expect(midRoll.duration <= 600 && midRoll.duration > 0) }
        if parts.count > 1 { #expect(parts.allSatisfy { $0.length >= 15 * 60 }) }
        let total = breaks.reduce(0) { $0 + $1.duration }
        #expect(abs(total - (slotEnd.timeIntervalSince(epoch) - minutes * 60)) < 0.01)
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

    @Test func runLeftoverBecomesAGapAfterTheLastProgramme() throws {
        // 50-minute episodes play back to back: 28 fit in a day, leaving 40 minutes.
        let s = try schedule(Fixtures.series("Fifty", seasons: 1, episodes: 6, minutes: 50), strategy: SequentialBySeries.id)
        let day = s.airings(from: epoch, to: epoch.addingTimeInterval(24 * 3600 - 1))
        #expect(day.count == 28)
        #expect(day.dropLast().allSatisfy { $0.slotEnd == $0.end }, "No gaps before the end of the run")
        #expect(day.last!.end == epoch.addingTimeInterval(28 * 50 * 60))
        #expect(day.last!.slotEnd == epoch.addingTimeInterval(24 * 3600))
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

    @Test func pullsAtMostADayOfProgrammesWhateverTheLibrarySize() throws {
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
        #expect(huge <= 66 + ChannelSchedule.maxSkipsAtRunEnd + 1, "At most one run: a day of 22-minute programmes, plus any passed over at its end")
    }

    @Test func noProgrammeRepeatsBackToBackWithinARun() throws {
        // 60 movies of mixed lengths: a day holds far fewer, so none should air twice in a run.
        let movies = (0..<60).map { Fixtures.movie("M\($0)", minutes: Double(80 + ($0 * 37) % 90)) }
        for strategy in [RandomShuffle.id, DerangedShows.id] {
            let s = try schedule(movies, strategy: strategy, padTo: 30)
            let runStart = Channel.defaultEpoch.addingTimeInterval(3 * s.runDuration)
            // Whole programmes: the parts of a film split by mid-roll breaks aren't repeats.
            let day = s.programmes(from: runStart, to: runStart.addingTimeInterval(s.runDuration - 1))
            #expect(Set(day.map(\.item.id)).count == day.count, "\(strategy) repeated a movie within a run")
        }
    }

    @Test func floorDivideRoundsTowardsNegativeInfinity() {
        #expect(ChannelSchedule.floorDivide(7, 3) == 2)
        #expect(ChannelSchedule.floorDivide(-7, 3) == -3)
        #expect(ChannelSchedule.floorDivide(-6, 3) == -2)
        #expect(ChannelSchedule.floorDivide(0, 3) == 0)
    }
}

struct LazyPermutationTests {
    @Test(arguments: [1, 2, 3, 5, 16, 17, 100, 1_000])
    func coversEveryIndexExactlyOnce(count: Int) {
        let permutation = LazyPermutation(count: count, seed: 9)
        let indices = (0..<count).map { permutation.index(at: $0) }
        #expect(indices.sorted() == Array(0..<count))
    }

    @Test func isDeterministicAndSeedDependent() {
        let a = (0..<50).map { LazyPermutation(count: 50, seed: 1).index(at: $0) }
        #expect(a == (0..<50).map { LazyPermutation(count: 50, seed: 1).index(at: $0) })
        #expect(a != (0..<50).map { LazyPermutation(count: 50, seed: 2).index(at: $0) })
        #expect(a != Array(0..<50), "Actually shuffled")
    }

    @Test func positionsWrap() {
        let p = LazyPermutation(count: 7, seed: 3)
        #expect(p.index(at: 9) == p.index(at: 2))
        #expect(p.index(at: -1) == p.index(at: 6))
    }
}
