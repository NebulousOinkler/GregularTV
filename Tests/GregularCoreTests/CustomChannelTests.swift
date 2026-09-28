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
        CustomChannel(number: 50, name: "Sitcoms at Six", kinds: [.episode], rule: .genre("Comedy"),
                      fixed: [FixedProgramme(match: .series("Alpha"), times: [18 * 60, 18 * 60 + 30]),
                              FixedProgramme(match: .item("Laughs"), times: [20 * 60], weekdays: [2, 6],
                                             dates: [.init(month: 2, day: 2), .init(month: 12, day: 25)], exclusive: true)],
                      timeZone: TimeZone(identifier: "America/New_York")!),
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

    @Test func setTimesAreInTheTimeZoneItWasMadeIn() throws {
        let made = try #require(CustomChannel(code: Self.examples[6].code))
        #expect(made.timeZone.identifier == "America/New_York", "Every Apple TV reads the times the same way")
        #expect(made.channel.timeZone == made.timeZone && made.channel.fixed.count == 2)
        let schedule = try #require(ChannelSchedule(channel: made.channel, items: Fixtures.library))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = made.timeZone
        let six = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 18))!
        #expect(schedule.programme(at: six).item.seriesName == "Alpha" && schedule.programme(at: six).start == six)
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
