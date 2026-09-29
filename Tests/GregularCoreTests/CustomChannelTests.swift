import Foundation
import Testing
@testable import GregularCore

/// Channels made on the Apple TV (TODO.md item 1, now built).
struct CustomChannelTests {
    static let examples: [CustomChannel] = [
        CustomChannel(number: 20, name: "Everything"),
        CustomChannel(number: 25, name: "Comedy Classics", kinds: [.episode], rule: .genre("Comedy"), halfHourSlots: false),
        CustomChannel(number: 42, name: "Café Taskmaster ☕", kinds: [.episode], rule: .series("Taskmaster"), commercials: false),
        CustomChannel(number: 70, name: "Golden Age", kinds: [.movie], rule: .years(from: 1930, to: 1959)),
        CustomChannel(number: 71, name: "Since 2000", rule: .years(from: 2000, to: nil)),
        CustomChannel(number: 99, name: "Holidays", rule: .tag("Christmas"), halfHourSlots: false, commercials: false),
    ]

    @Test(arguments: examples)
    func aChannelCodeReadsBackTheSameChannel(channel: CustomChannel) {
        #expect(CustomChannel(code: channel.code) == channel)
        #expect(CustomChannel(code: channel.code.lowercased().replacingOccurrences(of: "-", with: " ")) == channel,
                "Typing is forgiving, as with the schedule code")
    }

    @Test func aMistypedCodeIsRejectedNotMisread() {
        let code = Array(Self.examples[1].code)
        var rejected = 0, positions = 0
        for i in code.indices where code[i] != "-" {
            positions += 1
            var typo = code
            typo[i] = typo[i] == "7" ? "8" : "7"
            if CustomChannel(code: String(typo)) == nil { rejected += 1 }
        }
        #expect(rejected == positions)
        #expect(CustomChannel(code: "") == nil && CustomChannel(code: "HELLO") == nil)
    }

    @Test func itTakesTheDefaults() {
        let channel = Self.examples[1].channel
        #expect(channel.strategyID == ShuffledShows.id && channel.padToMinutes == nil && channel.fillerID == ShuffledCommercials.id)
        #expect(channel.seed == 1025, "Seeded from its number, clear of the bundled channels")
        #expect(Self.examples[2].channel.fillerID == NoGapFiller.id && Self.examples[2].channel.padToMinutes == 30)
    }

    @Test func itPlaysWhatItsRuleMatches() {
        let comedy = Self.examples[1].channel
        #expect(Fixtures.library.filter(comedy.accepts).allSatisfy { $0.kind == .episode && $0.genres.contains("Comedy") })
        let classics = CustomChannel(number: 30, name: "Old", rule: .years(from: nil, to: 1970)).channel
        #expect(Fixtures.library.filter(classics.accepts).map(\.name) == ["Old Classic"])
    }

    // MARK: In the line-up

    @Test func customChannelsJoinTheLineUp() throws {
        let lineup = try ChannelLineup.bundled().adding(Array(Self.examples.prefix(3)))
        #expect(lineup.channels.map(\.number).contains(25))
        #expect(lineup.channels.map(\.number) == lineup.channels.map(\.number).sorted())
    }

    @Test(arguments: [5, 19, 100])
    func numbersOutsideTheCustomRangeAreRejected(number: Int) {
        #expect(throws: ChannelLineup.LoadError.self) { try ChannelLineup.bundled().adding([CustomChannel(number: number, name: "X")]) }
    }

    @Test func takenNumbersAreRejected() throws {
        let lineup = try ChannelLineup(channels: [Fixtures.channel(number: 25)])
        #expect(throws: ChannelLineup.LoadError.self) { try lineup.adding([CustomChannel(number: 25, name: "X")]) }
        #expect(throws: ChannelLineup.LoadError.self) {
            try ChannelLineup.bundled().adding([CustomChannel(number: 30, name: "A"), CustomChannel(number: 30, name: "B")])
        }
    }

    @Test func twoAppleTVsWithTheSameCodesShowTheSameSchedule() throws {
        let shared = Self.examples[1].code
        func device() throws -> [String] {
            let custom = try #require(CustomChannel(code: shared))
            let schedules = try ChannelLineup.bundled().adding([custom]).schedules(for: Fixtures.library, code: ScheduleCode("7KQM2-X9PDA")!)
            let now = Date(timeIntervalSince1970: 1_790_000_000)
            let channel = try #require(schedules.first { $0.channel.number == 25 })
            return channel.programmes(from: now, to: now.addingTimeInterval(12 * 3600)).map(\.item.id)
        }
        let first = try device()
        #expect(!first.isEmpty)
        #expect(first == (try device()))
    }
}

/// A household's set times, and their codes.
struct SetTimesCodeTests {
    @Test func longNamesAreKeptInFull() throws {
        // A film title past 60 characters must still match the library after a relaunch.
        let title = "Borat: Cultural Learnings of America for Make Benefit Glorious Nation of Kazakhstan"
        let setTimes = SetTimes(channelNumber: 12, programmes: [FixedProgramme(match: .item(title), times: [1200])],
                                timeZone: TimeZone(identifier: "Europe/London")!)
        #expect(SetTimes(code: setTimes.code) == setTimes)
        let series = CustomChannel(number: 40, name: "Long", rule: .series(String(repeating: "Series ", count: 12)))
        #expect(CustomChannel(code: series.code) == series)
    }

    @Test func aNameTooLongForACodeIsCutBetweenCharacters() throws {
        // 300 bytes of three-byte characters: cut to a whole number of them, so the code still reads.
        let name = String(repeating: "日", count: 100)
        let read = try #require(SetTimes(code: SetTimes(channelNumber: 1, programmes: [FixedProgramme(match: .series(name), times: [60])]).code))
        #expect(read.programmes[0].match == .series(String(repeating: "日", count: 85)))
    }

    static let example = SetTimes(channelNumber: 2, programmes: [
        FixedProgramme(match: .series("Alpha"), times: [18 * 60, 18 * 60 + 30]),
        FixedProgramme(match: .item("Laughs"), times: [20 * 60], weekdays: [2, 6],
                       dates: [.init(month: 2, day: 2), .init(month: 12, day: 25)], exclusive: true),
    ], timeZone: TimeZone(identifier: "America/New_York")!)

    @Test func aSetTimesCodeReadsBackTheSameSetTimes() throws {
        let read = try #require(SetTimes(code: Self.example.code))
        #expect(read == Self.example)
        #expect(read.programmes.allSatisfy { $0.timeZone?.identifier == "America/New_York" },
                "Every Apple TV reads the times in the zone they were made in")
        #expect(SetTimes(code: Self.example.code.lowercased()) == Self.example)
        #expect(SetTimes(code: CustomChannelTests.examples[0].code) == nil, "A channel code isn't a set-times code")
    }

    @Test func theyApplyToTheirChannelOnly() throws {
        let lineup = try ChannelLineup.bundled().adding([], setTimes: [Self.example])
        #expect(lineup.channels.first { $0.number == 2 }?.fixed.count == 2)
        #expect(lineup.channels.filter { $0.number != 2 }.allSatisfy { $0.fixed.isEmpty })
        #expect(throws: ChannelLineup.LoadError.self) {
            try ChannelLineup.bundled().adding([], setTimes: [SetTimes(channelNumber: 77, programmes: Self.example.programmes)])
        }
        #expect(throws: ChannelLineup.LoadError.self, "One set per channel") {
            try ChannelLineup.bundled().adding([], setTimes: [Self.example, Self.example])
        }
    }
}
