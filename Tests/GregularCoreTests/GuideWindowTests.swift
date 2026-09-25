import Foundation
import Testing
@testable import GregularCore

struct GuideWindowTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let epoch = Channel.defaultEpoch   // 2024-01-01 00:00 UTC

    @Test func startsAtTheLastHalfHour() {
        let window = GuideWindow(containing: epoch.addingTimeInterval(47 * 60 + 12), calendar: utc)
        #expect(window.start == epoch.addingTimeInterval(30 * 60))
        #expect(window.end == window.start.addingTimeInterval(6.5 * 3600), "At least 6 hours past now")
        #expect(window.timeMarks.count == 13)
        #expect(window.timeMarks.first == window.start)
    }

    @Test func fractionIsClamped() {
        let window = GuideWindow(containing: epoch, calendar: utc)
        #expect(window.fraction(of: epoch.addingTimeInterval(-60)) == 0)
        #expect(window.fraction(of: epoch.addingTimeInterval(195 * 60)) == 0.5)
        #expect(window.fraction(of: epoch.addingTimeInterval(10 * 3600)) == 1)
    }

    @Test func cellsTileTheWindowExactly() throws {
        let schedule = try #require(ChannelSchedule(channel: Fixtures.channel(), items: Fixtures.library))
        let window = GuideWindow(containing: Date(timeIntervalSince1970: 1_790_000_123), calendar: utc)
        let cells = window.cells(for: schedule)

        #expect(cells.first?.visibleStart == window.start)
        #expect(cells.last?.visibleEnd == window.end)
        for (a, b) in zip(cells, cells.dropFirst()) {
            #expect(a.visibleEnd == b.visibleStart)
        }
        #expect(Set(cells.map(\.id)).count == cells.count)
    }

    @Test func firstCellIsClippedWhenAProgrammeIsAlreadyRunning() throws {
        // One 22-minute episode repeated: at 00:40 it's 18 minutes in.
        let schedule = try #require(ChannelSchedule(channel: Fixtures.channel(),
                                                    items: [Fixtures.episode("Show", s: 1, e: 1)]))
        let cells = GuideWindow(containing: epoch.addingTimeInterval(40 * 60), calendar: utc).cells(for: schedule)
        #expect(cells[0].startsBeforeWindow)
        #expect(cells[0].programme.start == epoch.addingTimeInterval(22 * 60))
        #expect(!cells[1].startsBeforeWindow)
    }

    @Test func commercialBreaksFoldIntoTheirProgramme() throws {
        let ads = (0..<6).map { MediaItem(id: "ad\($0)", kind: .movie, name: "Ad", duration: 60) }
        let channel = Channel(number: 1, name: "T", source: AllItemsSource(), strategyID: RandomShuffle.id,
                              seed: 1, padToMinutes: 30, fillerID: DerangedCommercials.id)
        let schedule = try #require(ChannelSchedule(channel: channel, items: [Fixtures.episode("Show", s: 1, e: 1)],
                                                    fillerPool: ads))

        // Opening the window mid-break must still give the programme, not an ad.
        let window = GuideWindow(containing: epoch.addingTimeInterval(24 * 60), stepMinutes: 1, calendar: utc)
        let cells = window.cells(for: schedule)
        #expect(cells.allSatisfy { !$0.programme.isFiller })
        #expect(cells[0].programme.start == epoch)
        #expect(cells[0].visibleEnd == epoch.addingTimeInterval(30 * 60), "The break belongs to the programme's block")
        #expect(cells[1].programme.start == epoch.addingTimeInterval(30 * 60))
    }
}
