import Foundation
import Testing
@testable import GregularTVCore

struct GapFillerTests {
    /// Commercials of 30, 60 and 90 seconds.
    let pool = [30.0, 60, 90, 30, 60].enumerated().map { i, seconds in
        MediaItem(id: "ad\(i)", kind: .movie, name: "Ad \(i)", duration: seconds)
    }
    let epoch = Channel.defaultEpoch

    /// One 22-minute episode padded to 30 minutes: an 8-minute gap.
    private func schedule(filler: String = DerangedCommercials.id, pool: [MediaItem]? = nil) throws -> ChannelSchedule {
        let channel = Channel(number: 1, name: "Test", source: AllItemsSource(), strategyID: RandomShuffle.id,
                              seed: 7, padToMinutes: 30, fillerID: filler)
        return try #require(ChannelSchedule(channel: channel, items: [Fixtures.episode("Show", s: 1, e: 1)],
                                            fillerPool: pool ?? self.pool))
    }

    // MARK: Fillers on their own

    static let fillerIDs = GapFillerRegistry.all.map { $0.id }
    /// A channel's content: 7 shows, keyed as channel seed 7 with the standard code.
    let content = ChannelContent(items: (0..<7).map { Fixtures.episode("Show \($0)", s: 1, e: 1) },
                                 seed: ScheduleCode.standard.key(forChannelSeed: 7))

    @Test(arguments: fillerIDs)
    func fillersAreDeterministic(id: String) throws {
        let filler = try #require(GapFillerRegistry.filler(withID: id))
        let first = Array(filler.clips(from: pool, for: content, startingAt: 12).prefix(40))
        #expect(first == Array(filler.clips(from: pool, for: content, startingAt: 12).prefix(40)))
    }

    @Test func derangementUsesTheShowsAAndB() {
        let shows = LazyDerangement(count: content.series.count, key: content.seed)
        let order = DerangedCommercials.order(forPoolOf: pool.count, content: content)
        #expect(order.a == shows.a && order.b == shows.b, "The same a and b as the channel's shows")
        #expect(order.prime > pool.count && order.prime > order.a && order.prime > order.b)
        // Clip number (a·x + b) mod q at step x, keeping those below the pool size.
        let expected = (0..<order.prime).map { (order.a * $0 + order.b) % order.prime }.filter { $0 < pool.count }
        let clips = Array(DerangedCommercials().clips(from: pool, for: content, startingAt: 0).prefix(pool.count))
        #expect(clips.map(\.id) == expected.map { pool[$0].id })
    }

    @Test func derangementPlaysEveryClipOncePerPassInTheSameOrder() {
        let clips = Array(DerangedCommercials().clips(from: pool, for: content, startingAt: 0).prefix(pool.count * 3))
        let passes = stride(from: 0, to: clips.count, by: pool.count).map { clips[$0..<$0 + pool.count].map(\.id) }
        #expect(Set(passes[0]).count == pool.count, "Every clip once")
        #expect(passes.allSatisfy { $0 == passes[0] }, "Each pass repeats the same order")
    }

    @Test func shufflePlaysEveryClipOncePerPassInANewOrder() {
        let big = (0..<12).map { MediaItem(id: "c\($0)", kind: .video, name: "C\($0)", duration: 30) }
        let clips = Array(ShuffledCommercials().clips(from: big, for: content, startingAt: 0).prefix(big.count * 4))
        let passes = stride(from: 0, to: clips.count, by: big.count).map { clips[$0..<$0 + big.count].map(\.id) }
        #expect(passes.allSatisfy { Set($0).count == big.count })
        #expect(Set(passes).count > 1, "The order changes between passes")
        // Starting partway gives the same clips as reading from the start.
        let fromSeven = Array(ShuffledCommercials().clips(from: big, for: content, startingAt: 7).prefix(20))
        #expect(fromSeven == Array(clips[7..<27]))
    }

    // MARK: In the schedule

    @Test func fillerAiringsFollowTheProgrammeInsideTheSlot() throws {
        // Exactly one slot: the next one starts at 30:00, and `to` is exclusive.
        let airings = try schedule().airings(from: epoch, to: epoch.addingTimeInterval(30 * 60))
        let programme = airings[0]
        let fillers = Array(airings.dropFirst())

        #expect(!programme.isFiller)
        #expect(programme.slotEnd == programme.end, "The first clip starts right as the programme ends")
        #expect(!fillers.isEmpty && fillers.allSatisfy(\.isFiller))
        for (a, b) in zip(airings, airings.dropFirst()) {
            #expect(a.slotEnd == b.start)
        }
        // The last clip owns what's left of the slot, and never runs past it.
        let nextProgramme = epoch.addingTimeInterval(30 * 60)
        #expect(fillers.last!.slotEnd == nextProgramme)
        #expect(fillers.last!.end <= nextProgramme)
        #expect(fillers.dropLast().allSatisfy { $0.length == $0.item.duration }, "Only the last clip can be cut")
    }

    @Test func breaksFollowTheCutAndHalfwayRules() throws {
        let s = try schedule()
        let day = s.airings(from: epoch, to: epoch.addingTimeInterval(24 * 3600))
        var sawACut = false
        for (a, b) in zip(day, day.dropFirst()) where a.isFiller && !b.isFiller {
            #expect(a.end <= b.start, "Never runs into the next programme")
            // At least half of every clip plays.
            #expect(a.length * 2 >= a.item.duration)
            // Stopped early only when the next clip couldn't get halfway (clips are at most 90 s).
            #expect(b.start.timeIntervalSince(a.end) < 45)
            if a.length < a.item.duration {
                sawACut = true
                #expect(a.end == b.start, "A cut clip is cut exactly at the programme")
                #expect(!s.tune(at: a.end.addingTimeInterval(-1)).isInPadding)
            }
        }
        #expect(sawACut, "Over a day, some break ends with a clip cut off")
    }

    @Test func aClipOnlyStartsIfMoreThanHalfOfItWillPlay() throws {
        // A 21-minute episode in a 30-minute slot leaves a 9-minute gap, filled with one clip length.
        // 5-minute clips: the second gets 4 of its 5 minutes, so it starts and is cut.
        // 10-minute clips: 9 of 10, cut. 20-minute clips: 9 of 20 is under half, so the gap stays blank.
        func fillers(clip minutes: Double) throws -> [Airing] {
            let clip = MediaItem(id: "long", kind: .video, name: "Long", duration: minutes * 60)
            let channel = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: RandomShuffle.id,
                                  seed: 7, padToMinutes: 30, fillerID: DerangedCommercials.id)
            let show = Fixtures.episode("S", s: 1, e: 1, minutes: 21)
            let s = try #require(ChannelSchedule(channel: channel, items: [show], fillerPool: [clip]))
            return s.airings(from: epoch, to: epoch.addingTimeInterval(30 * 60 - 1)).filter(\.isFiller)
        }
        #expect(try fillers(clip: 5).map(\.length) == [300, 240])
        #expect(try fillers(clip: 10).map(\.length) == [540])
        #expect(try fillers(clip: 20).isEmpty)
        #expect(try fillers(clip: 18).map(\.length) == [540], "Exactly half left: it still plays")
    }

    @Test func theOrderCarriesOnFromBreakToBreak() throws {
        // All the day's clips, break after break, are the filler's stream read
        // straight through: nothing restarts per break, and a clip that
        // doesn't get halfway opens the next break instead of being dropped.
        let s = try schedule()
        let day = s.airings(from: epoch, to: epoch.addingTimeInterval(24 * 3600 - 1)).filter(\.isFiller)
        let channelContent = ChannelContent(items: [Fixtures.episode("Show", s: 1, e: 1)],
                                            seed: ScheduleCode.standard.key(forChannelSeed: 7))
        let stream = DerangedCommercials().clips(from: pool, for: channelContent, startingAt: 0)
        #expect(day.map(\.item.id) == Array(stream.prefix(day.count)).map(\.id))
    }

    @Test func aMinuteOrLessGetsNoCommercials() throws {
        func clipCount(gapSeconds: Double) throws -> Int {
            let channel = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: RandomShuffle.id,
                                  seed: 7, padToMinutes: 30, fillerID: DerangedCommercials.id)
            let show = Fixtures.episode("S", s: 1, e: 1, minutes: 30 - gapSeconds / 60)
            let s = try #require(ChannelSchedule(channel: channel, items: [show], fillerPool: pool))
            return s.airings(from: epoch, to: epoch.addingTimeInterval(30 * 60 - 1)).filter(\.isFiller).count
        }
        #expect(try clipCount(gapSeconds: 45) == 0)
        #expect(try clipCount(gapSeconds: 60) == 0)
        #expect(try clipCount(gapSeconds: 61) > 0)
    }

    @Test func tuningDuringTheGapLandsOnAClip() throws {
        let s = try schedule()
        let tuning = s.tune(at: epoch.addingTimeInterval(22 * 60 + 5))
        #expect(tuning.airing.isFiller)
        #expect(s.programme(at: epoch.addingTimeInterval(22 * 60 + 5)).item.id == "Show-s1e1")
    }

    @Test func guideListingsCanLeaveOutFillers() throws {
        let airings = try schedule().airings(from: epoch, to: epoch.addingTimeInterval(90 * 60), includingFillers: false)
        #expect(airings.count == 3)
        #expect(airings.allSatisfy { !$0.isFiller })
    }

    @Test func sameGapIsFilledTheSameWayEveryTime() throws {
        let window = (epoch, epoch.addingTimeInterval(3 * 3600))
        #expect(try schedule().airings(from: window.0, to: window.1) == schedule().airings(from: window.0, to: window.1))
    }

    @Test func noFillerOrEmptyPoolLeavesThePlainGap() throws {
        for s in [try schedule(filler: NoGapFiller.id), try schedule(pool: [])] {
            let airings = s.airings(from: epoch, to: epoch.addingTimeInterval(29 * 60))
            #expect(airings.count == 1)
            #expect(airings[0].slotEnd == epoch.addingTimeInterval(30 * 60))
        }
    }

    @Test func channelConfigAcceptsKnownFillersOnly() throws {
        let ok = #"[{ "number": 1, "name": "X", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 1, "padTo": 30, "filler": "shuffle" }]"#
        #expect(try ChannelLineup.load(from: Data(ok.utf8)).channels[0].fillerID == "shuffle")
        let bad = ok.replacingOccurrences(of: #""filler": "shuffle""#, with: #""filler": "nope""#)
        #expect(throws: DecodingError.self) { try ChannelLineup.load(from: Data(bad.utf8)) }
    }
}
