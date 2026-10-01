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
}
