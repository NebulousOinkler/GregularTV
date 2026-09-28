import Foundation
import GregularCore
import Observation

/// Making or editing a custom channel (Settings › Channels). The choices
/// (genres, series, tags and years) come from the library already in
/// memory, and the preview is worked out on the device with no server
/// calls. Nothing is saved until `AppModel.save(_:replacing:)`.
@MainActor @Observable
public final class ChannelEditorModel {
    public enum Content: CaseIterable, Sendable {
        case episodes, movies, both

        public var label: String {
            switch self {
            case .episodes: "Episodes"
            case .movies: "Movies"
            case .both: "Episodes and Movies"
            }
        }

        var kinds: Set<MediaItem.Kind> {
            switch self {
            case .episodes: [.episode]
            case .movies: [.movie]
            case .both: [.episode, .movie]
            }
        }

        init(kinds: Set<MediaItem.Kind>) {
            self = Self.allCases.first { $0.kinds == kinds } ?? .both
        }
    }

    public enum RuleKind: CaseIterable, Sendable {
        case everything, genre, series, years, tag

        public var label: String {
            switch self {
            case .everything: "Everything"
            case .genre: "A Genre"
            case .series: "A Series"
            case .years: "Years"
            case .tag: "A Tag"
            }
        }
    }

    /// What airs in the next few hours, for the preview.
    public struct Upcoming: Sendable, Identifiable {
        public let start: Date
        public let title: String
        public var id: Date { start }
    }

    public var name: String
    public private(set) var number: Int
    public var content: Content
    public var ruleKind: RuleKind
    public var genre: String?
    public var series: String?
    public var tag: String?
    public var fromYear: Int?
    public var toYear: Int?
    public var halfHourSlots: Bool
    public var commercials: Bool
    /// Programmes at set times, in `timeZone`.
    public private(set) var fixed: [FixedProgramme]
    /// Where the set times are read: the zone the channel was made in.
    public let timeZone: TimeZone

    /// A set time being added: what (a series or a movie), when ("18:00,
    /// 18:30"), on which weekdays (none means every day), and whether it's
    /// kept out of the shuffle.
    public var draftProgramme: FixedProgramme.Match?
    public var draftTimes = ""
    public var draftWeekdays = Set<Int>()
    public var draftExclusive = false

    /// The channel being edited, or nil for a new one.
    public let original: CustomChannel?
    /// The library's genres, series and tags, to pick from.
    public let genres: [String]
    public let seriesNames: [String]
    public let tags: [String]
    /// The library's films, to set at a time.
    public let movieNames: [String]
    /// The library's earliest and latest production years.
    public let years: ClosedRange<Int>?

    private let library: [MediaItem]
    /// The line-up without this channel, to check the number against.
    private let lineup: ChannelLineup
    private let code: ScheduleCode

    /// - Parameters:
    ///   - lineup: the line-up without the channel being edited.
    ///   - code: the schedule code, so the preview matches what will air.
    public init(editing original: CustomChannel?, library: [MediaItem], lineup: ChannelLineup, code: ScheduleCode) {
        self.original = original
        self.library = library
        self.lineup = lineup
        self.code = code
        genres = Self.distinct(library.flatMap(\.genres))
        seriesNames = Self.distinct(library.compactMap(\.seriesName))
        tags = Self.distinct(library.flatMap(\.tags))
        movieNames = Self.distinct(library.filter { $0.kind == .movie }.map(\.name))
        let allYears = library.compactMap(\.productionYear)
        years = allYears.min().flatMap { low in allYears.max().map { low...$0 } }

        let channel = original ?? CustomChannel(number: 0, name: "")
        name = channel.name
        content = Content(kinds: channel.kinds)
        halfHourSlots = channel.halfHourSlots
        commercials = channel.commercials
        fixed = channel.fixed
        timeZone = channel.timeZone
        switch channel.rule {
        case .everything: ruleKind = .everything
        case .genre(let value): ruleKind = .genre; genre = value
        case .series(let value): ruleKind = .series; series = value
        case .years(let from, let to): ruleKind = .years; fromYear = from; toYear = to
        case .tag(let value): ruleKind = .tag; tag = value
        }
        number = original?.number ?? 0
        if original == nil { number = freeNumbers.first ?? CustomChannel.numbers.lowerBound }
    }

    /// Numbers a custom channel may use that aren't taken.
    public var freeNumbers: [Int] {
        let taken = Set(lineup.channels.map(\.number))
        return CustomChannel.numbers.filter { !taken.contains($0) }
    }

    /// Moves to the next free number up or down, wrapping round.
    public func stepNumber(by step: Int) {
        let free = freeNumbers
        guard !free.isEmpty else { return }
        let index = free.firstIndex(of: number) ?? 0
        number = free[ChannelContent.wrap(index + step, free.count)]
    }

    /// The channel as it stands, or nil while its rule is missing a choice.
    public var channel: CustomChannel? {
        let rule: CustomChannel.Rule
        switch ruleKind {
        case .everything: rule = .everything
        case .genre: guard let genre else { return nil }; rule = .genre(genre)
        case .series: guard let series else { return nil }; rule = .series(series)
        case .years: rule = .years(from: fromYear, to: toYear)
        case .tag: guard let tag else { return nil }; rule = .tag(tag)
        }
        return CustomChannel(number: number, name: name.trimmingCharacters(in: .whitespaces), kinds: content.kinds,
                             rule: rule, halfHourSlots: halfHourSlots, commercials: commercials, fixed: fixed,
                             timeZone: timeZone)
    }

    // MARK: - Set times

    /// Adds the draft set time. Returns why it can't be added, or nil.
    @discardableResult
    public func addDraft() -> String? {
        guard let match = draftProgramme else { return "Choose a series or film to set at a time." }
        let parts = draftTimes.split(whereSeparator: { $0 == "," || $0 == " " })
        let times = parts.compactMap { FixedProgramme.minutes(from: String($0)) }
        guard !times.isEmpty, times.count == parts.count else {
            return "Enter times like 18:00, or several like 18:00, 18:30."
        }
        let entry = FixedProgramme(match: match, times: times, weekdays: draftWeekdays, exclusive: draftExclusive)
        if let clash = entry.clashes(with: fixed).first {
            return "Something else is already set at \(FixedProgramme.text(forMinutes: clash))."
        }
        fixed.append(entry)
        draftProgramme = nil
        draftTimes = ""
        draftWeekdays = []
        draftExclusive = false
        return nil
    }

    public func removeFixed(_ entry: FixedProgramme) {
        fixed.removeAll { $0 == entry }
    }

    /// Why it can't be saved yet, in plain words, or nil if it can.
    public var problem: String? {
        guard let channel else { return "Choose \(ruleKind.label.lowercased()) for the channel." }
        if channel.name.isEmpty { return "Give the channel a name." }
        do {
            _ = try lineup.adding([channel])
        } catch {
            return "\(error)"
        }
        return matchingCount == 0 ? "Nothing in your library matches yet." : nil
    }

    /// How many programmes the channel would play.
    public var matchingCount: Int {
        guard let channel = channel?.channel else { return 0 }
        return library.count { channel.accepts($0) && $0.duration > 0 }
    }

    /// The next few hours, as they'd air.
    public func upcoming(from now: Date = .now, hours: Double = 3) -> [Upcoming] {
        guard let channel = channel?.channel, let schedule = ChannelSchedule(channel: channel, items: library, code: code)
        else { return [] }
        return schedule.programmes(from: now, to: now.addingTimeInterval(hours * 3600))
            .map { Upcoming(start: $0.start, title: $0.item.displayTitle) }
    }

    /// Sorted, with case-insensitive duplicates removed.
    private static func distinct(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
