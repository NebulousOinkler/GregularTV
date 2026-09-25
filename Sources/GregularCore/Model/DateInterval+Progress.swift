import Foundation

extension DateInterval {
    /// How far through the interval `date` is, from 0 (start) to 1 (end),
    /// clamped. An empty interval counts as done.
    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}
