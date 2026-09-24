import Foundation

/// The time range a programme guide shows, and each channel's programmes laid
/// out within it.
///
/// It starts at the most recent half-hour mark in local time, like a TV
/// guide, and by default runs six and a half hours from there, so it always
/// reaches at least six hours past now.
public struct GuideWindow: Sendable, Equatable {
    public static let defaultSpan: TimeInterval = 6.5 * 3600

    public let start: Date
    public let end: Date
    /// Minutes between time marks on the ruler.
    public let stepMinutes: Int

    public init(containing now: Date, span: TimeInterval = defaultSpan, stepMinutes: Int = 30,
                calendar: Calendar = .current) {
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        parts.minute = (parts.minute ?? 0) / stepMinutes * stepMinutes
        let start = calendar.date(from: parts) ?? now
        self.start = start
        end = start.addingTimeInterval(span)
        self.stepMinutes = stepMinutes
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Ruler marks: the start, then every `stepMinutes`, before `end`.
    public var timeMarks: [Date] {
        stride(from: 0, to: duration, by: TimeInterval(stepMinutes * 60)).map { start.addingTimeInterval($0) }
    }

    /// Where `date` falls across the window, from 0 (start) to 1 (end), clamped.
    public func fraction(of date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    /// The channel's programmes in this window, back to back and clipped to
    /// its edges. Commercial breaks and padding count as part of the
    /// programme before them, so the guide lists programmes only.
    public func cells(for schedule: ChannelSchedule) -> [GuideCell] {
        var spans: [(programme: Airing, end: Date)] = []
        for airing in schedule.airings(from: start, to: end) {
            if airing.isFiller {
                if spans.isEmpty {
                    // The window opens mid-break; the programme began earlier.
                    spans.append((schedule.programme(at: airing.start), airing.slotEnd))
                } else {
                    spans[spans.count - 1].end = airing.slotEnd
                }
            } else {
                spans.append((airing, airing.slotEnd))
            }
        }
        return spans.map { span in
            GuideCell(programme: span.programme,
                      visibleStart: max(span.programme.start, start),
                      visibleEnd: min(span.end, end))
        }
    }
}

/// One programme's block in a guide row.
public struct GuideCell: Sendable, Hashable, Identifiable {
    public let programme: Airing
    /// The part inside the guide window, used for the block's position and width.
    public let visibleStart: Date
    public let visibleEnd: Date

    public var id: String { "\(programme.item.id)@\(programme.start.timeIntervalSince1970)" }

    /// True when the programme began before the window, so the block is cut off on the left.
    public var startsBeforeWindow: Bool { programme.start < visibleStart }

    public func contains(_ date: Date) -> Bool {
        visibleStart <= date && date < visibleEnd
    }
}
