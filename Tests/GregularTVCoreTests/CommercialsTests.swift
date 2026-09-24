import Foundation
import Testing
@testable import GregularTVCore

struct CommercialsTests {
    let ads = (0..<6).map { MediaItem(id: "ad\($0)", kind: .video, name: "Ad \($0)", duration: 30 + Double($0) * 15) }

    @Test func bundledLineupNamesTheCommercialsLibraryAndUsesItEverywhere() throws {
        let lineup = try ChannelLineup.bundled()
        #expect(lineup.commercialsLibrary == "Commercials")
        #expect(lineup.channels.allSatisfy { $0.fillerID == "derangement" })
    }

    @Test func turningCommercialsOffLeavesProgrammeTimesExactlyTheSame() throws {
        let json = #"[{ "number": 10, "name": "Movies", "itemTypes": ["Movie"], "source": { "type": "all" }, "strategy": "derangement", "seed": 1, "padTo": 30, "filler": "derangement" }]"#
        let lineup = try ChannelLineup.load(from: Data(json.utf8))
        let on = try #require(lineup.schedules(for: Fixtures.library, fillerPool: ads).first)
        let off = try #require(lineup.schedules(for: Fixtures.library, fillerPool: ads, playsCommercials: false).first)
        let week = (Channel.defaultEpoch, Channel.defaultEpoch.addingTimeInterval(7 * 24 * 3600))
        let onDay = on.airings(from: week.0, to: week.1)
        let offDay = off.airings(from: week.0, to: week.1)
        #expect(onDay.contains { $0.isFiller })
        #expect(!offDay.contains { $0.isFiller }, "Breaks are blank")
        #expect(onDay.filter { !$0.isFiller }.map(\.item.id) == offDay.map(\.item.id))
        #expect(onDay.filter { !$0.isFiller }.map(\.start) == offDay.map(\.start), "Same programmes, same start times")
    }

    @Test func thePlainListFormatStillLoads() throws {
        let json = #"[{ "number": 1, "name": "X", "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 1 }]"#
        let lineup = try ChannelLineup.load(from: Data(json.utf8))
        #expect(lineup.channels.count == 1)
        #expect(lineup.commercialsLibrary == nil)
    }

    @Test func clipsNeverAirAsProgrammes() throws {
        // The same video in the library and in the commercials pool (a library
        // set up as "Movies" instead of "Home Videos"): it only ever plays as an ad.
        let clipAlsoInLibrary = MediaItem(id: "ad0", kind: .movie, name: "Ad 0", duration: 30)
        let json = #"[{ "number": 10, "name": "Movies", "itemTypes": ["Movie"], "source": { "type": "all" }, "strategy": "random-shuffle", "seed": 1, "padTo": 30, "filler": "derangement" }]"#
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8))
            .schedules(for: Fixtures.library + [clipAlsoInLibrary], fillerPool: ads).first)
        let day = schedule.airings(from: Channel.defaultEpoch, to: Channel.defaultEpoch.addingTimeInterval(24 * 3600))
        #expect(day.filter { !$0.isFiller }.allSatisfy { !$0.item.id.hasPrefix("ad") })
        #expect(day.contains { $0.isFiller }, "Padding gaps are filled with the ads")
    }

    @Test func commercialsFillTheRunEndGapOnUnpaddedChannelsToo() throws {
        // 50-minute episodes: 28 fit in a day, leaving 40 minutes for ads.
        let json = #"[{ "number": 1, "name": "T", "source": { "type": "all" }, "strategy": "sequential-by-series", "seed": 1, "filler": "derangement" }]"#
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8))
            .schedules(for: Fixtures.series("Fifty", seasons: 1, episodes: 6, minutes: 50), fillerPool: ads).first)
        let day = schedule.airings(from: Channel.defaultEpoch, to: Channel.defaultEpoch.addingTimeInterval(24 * 3600 - 1))
        let breakTime = day.filter(\.isFiller).reduce(0) { $0 + $1.length }
        // Up to the next day's first episode, less any tail too short to get halfway through a clip (ads are at most 105 s).
        #expect(breakTime <= 40 * 60 && breakTime > 40 * 60 - 53)
    }

    @Test func aBreakRunsFromItsFirstClipToTheNextProgramme() throws {
        let json = #"[{ "number": 1, "name": "T", "source": { "type": "all" }, "strategy": "sequential-by-series", "seed": 1, "filler": "derangement" }]"#
        let schedule = try #require(try ChannelLineup.load(from: Data(json.utf8))
            .schedules(for: Fixtures.series("Fifty", seasons: 1, episodes: 6, minutes: 50), fillerPool: ads).first)
        let lastHour = schedule.airings(from: Channel.defaultEpoch.addingTimeInterval(23 * 3600),
                                        to: Channel.defaultEpoch.addingTimeInterval(24 * 3600 - 1))
        let clips = lastHour.filter(\.isFiller)
        try #require(clips.count >= 2)
        let expected = DateInterval(start: clips[0].start, end: try #require(clips.last).slotEnd)
        // The same span from any clip in the break, not just that clip's end.
        for clip in clips {
            #expect(schedule.commercialBreak(at: clip.start.addingTimeInterval(1)) == expected)
        }
        #expect(schedule.commercialBreak(at: lastHour[0].start.addingTimeInterval(60)) == nil, "Not during a programme")
    }
}

struct CommercialsLibraryTests {
    let mock = MockJellyfin()

    @Test func findsTheLibraryByNameAndLoadsItsVideos() async throws {
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v1", "Name": "Movies", "Type": "CollectionFolder" }, { "Id": "v2", "Name": "commercials", "Type": "CollectionFolder" }], "TotalRecordCount": 2 }"#)
        mock.on("GET", "/Items") { request in
            #expect(request.queryValue("ParentId") == "v2")
            #expect(request.queryValue("IncludeItemTypes")?.contains("Video") == true)
            return (200, #"{ "Items": [{ "Id": "a1", "Name": "Soda 1978", "Type": "Video", "RunTimeTicks": 300000000 }], "TotalRecordCount": 1 }"#)
        }
        let clips = try #require(try await JellyfinFixtures.client(mock).fetchLibrary(named: "Commercials"))
        #expect(clips.map(\.id) == ["a1"])
        #expect(clips[0].kind == .video && clips[0].duration == 30)
    }

    @Test func aMissingLibraryIsNil() async throws {
        mock.on("GET", "/UserViews", json: #"{ "Items": [{ "Id": "v1", "Name": "Movies", "Type": "CollectionFolder" }], "TotalRecordCount": 1 }"#)
        #expect(try await JellyfinFixtures.client(mock).fetchLibrary(named: "Commercials") == nil)
    }
}
