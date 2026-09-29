import Foundation

extension Date {
    /// The time as every screen shows it, in the viewer's own format:
    /// "9:30 PM", or "21:30".
    public var clockTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    /// The time with its day, for lists that run past today: "9:30 PM"
    /// today, "Tomorrow 9:30 PM", then "Wed 9:30 PM".
    public func dayAndTime(from now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: self)).day ?? 0
        switch days {
        case 0: return clockTime
        case 1: return "Tomorrow \(clockTime)"
        default: return "\(formatted(.dateTime.weekday(.abbreviated))) \(clockTime)"
        }
    }
}
