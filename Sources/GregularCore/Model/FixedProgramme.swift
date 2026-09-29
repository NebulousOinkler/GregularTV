import Foundation

/// A programme a channel airs at set local times ("appointment viewing"),
/// laid over its shared schedule. From the channel's `"fixed"` list in
/// `channels.json` (shared by everyone with that file), or a household's
/// `SetTimes`:
///
/// ```json
/// "timeZone": "America/New_York",
/// "fixed": [
///   { "series": "The Simpsons", "at": ["18:00", "18:30"] },
///   { "item": "Groundhog Day", "at": ["20:00"], "days": ["Feb 2"], "exclusive": true }
/// ]
/// ```
///
/// - `series` or `item` names what airs, by name (case-insensitive), as the
///   channel sources do. A series plays its next episode at each airing.
/// - `at` gives local times in the channel's `timeZone`.
/// - `days` (optional) limits it to weekdays (`"Mon"` … `"Sun"`) and dates
///   (`"Feb 2"`). Without it, it airs every day.
/// - `exclusive` (optional) keeps it to its set times: where the shared
///   schedule airs it otherwise, a stand-in takes that slot.
///
/// The rules for these are `PinnedProgrammes`,
/// `ExclusiveProgrammesOnlyAtSetTimes` and `FixedTimesAreValid`.
public struct FixedProgramme: Sendable, Hashable {
    public enum Match: Sendable, Hashable {
        case series(String)
        case item(String)
    }

    /// A month and day, such as February 2.
    public struct MonthDay: Sendable, Hashable {
        public let month: Int
        public let day: Int

        public init(month: Int, day: Int) {
            self.month = month
            self.day = day
        }

        /// Whether it's a date in some year (February 29 counts).
        public var isReal: Bool {
            (1...12).contains(month) && (1...Self.longestMonths[month - 1]).contains(day)
        }

        static let longestMonths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    }

    /// The most set times one channel can have, and the most times they can
    /// list in all. Plenty for a household, and they keep the work of
    /// placing them small, whatever a shared code holds.
    public static let mostPerChannel = 24
    public static let mostTimesPerChannel = 48

    public let match: Match
    /// Minutes after local midnight, in order.
    public let times: [Int]
    /// Weekdays it airs on (1 = Sunday … 7 = Saturday, as `Calendar` numbers them).
    public let weekdays: Set<Int>
    /// Dates it airs on.
    public let dates: Set<MonthDay>
    /// Its other airings in the shared schedule get a stand-in.
    public let exclusive: Bool
    /// Where `times` are read. Every Apple TV must agree on what "6:00 PM"
    /// means, so it's part of the set time, not the device's zone. Nil only
    /// until a channel gives it one (`FixedTimesAreValid` checks).
    public var timeZone: TimeZone?

    public init(match: Match, times: [Int], weekdays: Set<Int> = [], dates: Set<MonthDay> = [], exclusive: Bool = false,
                timeZone: TimeZone? = nil) {
        self.match = match
        self.times = times.sorted()
        self.weekdays = weekdays
        self.dates = dates
        self.exclusive = exclusive
        self.timeZone = timeZone
    }

    /// The same set time, read in `zone`.
    public func `in`(_ zone: TimeZone) -> FixedProgramme {
        var copy = self
        copy.timeZone = zone
        return copy
    }

    /// True when it has no `days`, so it airs every day.
    public var airsEveryDay: Bool { weekdays.isEmpty && dates.isEmpty }

    /// Whether it airs on a day with this weekday and date.
    func airs(onWeekday weekday: Int, date: MonthDay) -> Bool {
        airsEveryDay || weekdays.contains(weekday) || dates.contains(date)
    }

    /// Whether this could ever air on the same day as `other`.
    func sharesADay(with other: FixedProgramme) -> Bool {
        let onlyWeekdays = dates.isEmpty && other.dates.isEmpty
        return airsEveryDay || other.airsEveryDay || !onlyWeekdays || !weekdays.isDisjoint(with: other.weekdays)
    }

    /// Its times that clash: listed twice, or shared with one of `others` in
    /// the same time zone on a day they both air.
    public func clashes(with others: [FixedProgramme]) -> [Int] {
        var clashes = Set(times.filter { t in times.count { $0 == t } > 1 })
        for other in others where other.timeZone == timeZone && sharesADay(with: other) {
            clashes.formUnion(Set(times).intersection(other.times))
        }
        return clashes.sorted()
    }

    /// True when `item` is what this programme names.
    func matches(_ item: MediaItem) -> Bool {
        switch match {
        case .series(let name): item.seriesName?.caseInsensitiveCompare(name) == .orderedSame
        case .item(let name): item.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Whether `library` has anything it names, to play. A set time made
    /// with another library (from a shared code) may not.
    public func isAvailable(in library: [MediaItem]) -> Bool {
        library.contains { matches($0) && $0.duration > 0 }
    }

    /// What it can play from `library`: a series' episodes in aired order,
    /// or the one item (the earliest, if several share the name).
    func programmes(in library: [MediaItem]) -> [MediaItem] {
        let matching = library.filter { matches($0) && $0.duration > 0 }
        switch match {
        case .series: return matching.sorted(by: MediaItem.airedOrder)
        case .item:
            return matching.min { ($0.productionYear ?? .max, $0.id) < ($1.productionYear ?? .max, $1.id) }.map { [$0] } ?? []
        }
    }
}

// MARK: - Counting airings

extension FixedProgramme {
    /// How many times it aired on days `0..<day` (negative `day`: minus the
    /// airings on `day..<0`), so a series knows which episode is next without
    /// replaying the calendar. Day 0 is the channel's first local day.
    /// - Parameters:
    ///   - firstWeekday: day 0's weekday (1 = Sunday … 7 = Saturday).
    ///   - dayOf: the day number of a date in a given year.
    func airings(before day: Int, firstWeekday: Int, dayOf: (MonthDay, _ year: Int) -> Int?,
                 years: ClosedRange<Int>) -> Int {
        guard !airsEveryDay else { return day * times.count }
        let (from, to, sign) = day >= 0 ? (0, day, 1) : (day, 0, -1)
        // Days in from..<to with a listed weekday.
        var count = weekdays.reduce(0) { total, weekday in
            let first = from + ChannelContent.wrap(weekday - (firstWeekday + from), 7)
            return total + (first < to ? (to - 1 - first) / 7 + 1 : 0)
        }
        // Listed dates in from..<to that aren't already counted by their weekday.
        for year in years {
            for date in dates {
                guard let d = dayOf(date, year), d >= from, d < to else { continue }
                let weekday = ChannelContent.wrap(firstWeekday - 1 + d, 7) + 1
                if !weekdays.contains(weekday) { count += 1 }
            }
        }
        return sign * count * times.count
    }
}

// MARK: - Decoding

extension FixedProgramme: Decodable {
    private enum CodingKeys: String, CodingKey {
        case series, item, at, days, exclusive
    }

    static let weekdayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch (try c.decodeIfPresent(String.self, forKey: .series), try c.decodeIfPresent(String.self, forKey: .item)) {
        case (let series?, nil): match = .series(series)
        case (nil, let item?): match = .item(item)
        default:
            throw DecodingError.dataCorruptedError(forKey: .series, in: c,
                                                   debugDescription: "A fixed programme names one \"series\" or one \"item\".")
        }
        times = try c.decode([String].self, forKey: .at).map { text in
            guard let minutes = Self.minutes(from: text) else {
                throw DecodingError.dataCorruptedError(forKey: .at, in: c,
                                                       debugDescription: "'\(text)' isn't a time like \"18:30\".")
            }
            return minutes
        }.sorted()
        var weekdays = Set<Int>(), dates = Set<MonthDay>()
        for text in try c.decodeIfPresent([String].self, forKey: .days) ?? [] {
            if let weekday = Self.weekdayNames.firstIndex(of: text.lowercased().prefix(3).description) {
                weekdays.insert(weekday + 1)
            } else if let date = Self.monthDay(from: text) {
                dates.insert(date)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .days, in: c,
                                                       debugDescription: "'\(text)' isn't a weekday like \"Mon\" or a date like \"Feb 2\".")
            }
        }
        self.weekdays = weekdays
        self.dates = dates
        exclusive = try c.decodeIfPresent(Bool.self, forKey: .exclusive) ?? false
    }

    /// "18:30" → 1110. Nil unless it's a time within a day.
    public static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 1110 → "18:30".
    public static func text(forMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "Feb 2" → February 2. Nil unless it's a real date (February 29 counts).
    static func monthDay(from text: String) -> MonthDay? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let month = monthNames.firstIndex(of: parts[0].lowercased().prefix(3).description),
              let day = Int(parts[1]) else { return nil }
        let date = MonthDay(month: month + 1, day: day)
        return date.isReal ? date : nil
    }
}
