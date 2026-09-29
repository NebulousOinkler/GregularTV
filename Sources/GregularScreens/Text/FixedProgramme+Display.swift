import Foundation
import GregularCore

extension FixedProgramme.Match {
    /// The series or film's name.
    public var title: String {
        switch self {
        case .series(let name), .item(let name): name
        }
    }
}

extension FixedProgramme {
    /// When it airs, in the viewer's own clock format: "6:00 PM, 6:30 PM ·
    /// Mon, Thu", or "20:00 · Every day · Only then".
    public var summary: String {
        let days = weekdays.isEmpty && dates.isEmpty
            ? "Every day"
            : weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: ", ")
        let parts = [times.map { Self.clockText(forMinutes: $0) }.joined(separator: ", "), days, exclusive ? "Only then" : nil]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Mon" for 2, in the viewer's language (1 = Sunday … 7 = Saturday).
    public static func weekdayName(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }
}

extension FixedProgramme {
    /// 1110 → "6:30 PM", or "18:30", as every screen shows times.
    public static func clockText(forMinutes minutes: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: .gmt)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(minutes * 60)).formatted(style)
    }

    /// Times as a viewer types them, in either clock: "18:00, 18:30",
    /// "6:00 PM, 6:30 PM", "6pm 6:30pm" or "6 p.m.". Nil if any of it isn't a
    /// time. A time without a colon needs am or pm ("6" could be either).
    public static func typedTimes(_ text: String, locale: Locale = .autoupdatingCurrent) -> [Int]? {
        let formatter = DateFormatter()
        formatter.locale = locale
        let simplify = { (word: String) in word.lowercased().replacingOccurrences(of: ".", with: "") }
        let am = Set(["am", "a", simplify(formatter.amSymbol)])
        let pm = Set(["pm", "p", simplify(formatter.pmSymbol)])
        let words = simplify(text).split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        var times: [Int] = []
        var index = 0
        while index < words.count {
            var word = words[index]
            var isPM: Bool?
            // "6:30pm": am or pm written on.
            for suffix in (am.union(pm)).sorted(by: { $0.count > $1.count })
            where word.count > suffix.count && word.hasSuffix(suffix) && word.dropLast(suffix.count).last?.isNumber == true {
                isPM = pm.contains(suffix)
                word.removeLast(suffix.count)
                break
            }
            // "6:30 pm": am or pm as the next word.
            if isPM == nil, index + 1 < words.count, am.contains(words[index + 1]) || pm.contains(words[index + 1]) {
                isPM = pm.contains(words[index + 1])
                index += 1
            }
            guard let minutes = minutes(fromClock: word, isPM: isPM) else { return nil }
            times.append(minutes)
            index += 1
        }
        return times.isEmpty ? nil : times
    }

    /// "18:30" (no am or pm), or "6:30" or "6" with one.
    private static func minutes(fromClock word: String, isPM: Bool?) -> Int? {
        guard let isPM else { return minutes(from: word) }
        let parts = word.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = Int(parts[0]), (1...12).contains(hour) else { return nil }
        var minute = 0
        if parts.count == 2 {
            guard parts[1].count == 2, let m = Int(parts[1]), (0..<60).contains(m) else { return nil }
            minute = m
        }
        return (hour % 12 + (isPM ? 12 : 0)) * 60 + minute
    }
}
