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
        CustomChannel(number: 50, name: "Mixed", rule: CustomChannel.Rule([
            .init(.anyOf, .genre("Comedy")), .init(.anyOf, .series("Bravo")),
            .init(.allOf, .years(from: 1990, to: nil)), .init(.noneOf, .tag("Christmas")),
        ])),
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

    /// Any of Comedy or Bravo, all of 1990 on, none of Christmas.
    @Test func conditionsJoinAnyAllAndNone() {
        let mixed = Self.examples.last!.channel
        let names = Set(Fixtures.library.filter(mixed.accepts).map(\.name))
        // Alpha is a comedy and Bravo is named, but neither episode has a year,
        // so "all of 1990 on" leaves them out; "Laughs" is a 2005 comedy but tagged Christmas.
        #expect(names.isEmpty)
        let noYears = CustomChannel(number: 51, name: "M", rule: CustomChannel.Rule([
            .init(.anyOf, .genre("Comedy")), .init(.anyOf, .series("Bravo")), .init(.noneOf, .tag("Christmas")),
        ])).channel
        let matched = Fixtures.library.filter(noYears.accepts)
        #expect(Set(matched.compactMap(\.seriesName)) == ["Alpha", "Bravo"])
        #expect(!matched.contains { $0.name == "Laughs" }, "None of Christmas")
        let onlyNone = CustomChannel(number: 52, name: "N", rule: CustomChannel.Rule([.init(.noneOf, .tag("Christmas"))])).channel
        #expect(Fixtures.library.filter(onlyNone.accepts).count == Fixtures.library.count - 1, "Everything but Christmas")
    }

    @Test func aFirstVersionCodeStillReads() {
        // A code saved before rules had several conditions: version 1, the rule's kind in the flags.
        var writer = CodeWriter(version: 1)
        writer.byte(25)
        writer.byte(1 | 4 | 1 << 4)   // episodes, half-hour slots, a genre rule
        writer.text("Comedy Classics")
        writer.text("Comedy")
        #expect(CustomChannel(code: writer.code)
                    == CustomChannel(number: 25, name: "Comedy Classics", kinds: [.episode], rule: .genre("Comedy"), commercials: false))
    }

    @Test func aCodeWithTooManyConditionsIsRejected() {
        let many = CustomChannel.Rule((0...CustomChannel.Rule.mostConditions).map { .init(.anyOf, .genre("G\($0)")) })
        var writer = CodeWriter(version: 2)
        writer.byte(30); writer.byte(3); writer.text("Many")
        writer.byte(UInt8(many.conditions.count))
        for condition in many.conditions {
            writer.byte(0)
            if case .genre(let name) = condition.match { writer.text(name) }
        }
        #expect(CustomChannel(code: writer.code) == nil)
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
    /// A code anyone could craft: it decodes, but the line-up won't take it.
    private func rejected(_ programmes: [FixedProgramme]) throws -> String? {
        let crafted = try #require(SetTimes(code: SetTimes(channelNumber: 1, programmes: programmes,
                                                           timeZone: TimeZone(identifier: "Europe/London")!).code))
        do {
            _ = try ChannelLineup.bundled().adding([], setTimes: [crafted])
            return nil
        } catch {
            return "\(error)"
        }
    }

    @Test func craftedCodesWithImpossibleTimesOrDatesAreRejected() throws {
        #expect(try rejected([FixedProgramme(match: .item("Film"), times: [5000])]) == "Channel 1: set times must be between 00:00 and 23:59.")
        #expect(try rejected([FixedProgramme(match: .item("Film"), times: [60], dates: [.init(month: 200, day: 99)])])
                == "Channel 1: set times can only be on real days and dates.")
        #expect(try rejected([FixedProgramme(match: .item("Film"), times: [60], dates: [.init(month: 2, day: 29)])]) == nil)
    }

    @Test func craftedCodesWithTooManySetTimesAreRejected() throws {
        // Each would make placing the channel's set times slow on every look at the channel.
        let many = (0...FixedProgramme.mostPerChannel).map { FixedProgramme(match: .item("Film \($0)"), times: [$0]) }
        #expect(try rejected(many) == "Channel 1 can have at most \(FixedProgramme.mostPerChannel) set times.")
        let manyTimes = [FixedProgramme(match: .item("Film"), times: Array(0...FixedProgramme.mostTimesPerChannel))]
        #expect(try rejected(manyTimes) == "Channel 1's set times can list at most \(FixedProgramme.mostTimesPerChannel) times in all.")
        let most = [FixedProgramme(match: .item("Film"), times: Array(0..<FixedProgramme.mostTimesPerChannel))]
        #expect(try rejected(most) == nil)
    }

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
