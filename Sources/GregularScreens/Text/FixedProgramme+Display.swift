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
    /// When it airs: "18:00, 18:30 · Mon, Thu", or "20:00 · Every day · Only then".
    public var summary: String {
        let days = weekdays.isEmpty && dates.isEmpty
            ? "Every day"
            : weekdays.sorted().map { Self.weekdayName($0) }.joined(separator: ", ")
        let parts = [times.map(Self.text(forMinutes:)).joined(separator: ", "), days, exclusive ? "Only then" : nil]
        return parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Mon" for 2, in the viewer's language (1 = Sunday … 7 = Saturday).
    public static func weekdayName(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }
}
