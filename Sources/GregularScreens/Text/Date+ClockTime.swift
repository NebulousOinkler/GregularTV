import Foundation

extension Date {
    /// The time as every screen shows it, in the viewer's own format:
    /// "9:30 PM", or "21:30".
    public var clockTime: String {
        formatted(date: .omitted, time: .shortened)
    }
}
