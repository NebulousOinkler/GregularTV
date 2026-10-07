import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// Every channel with what's on now, or, in a break, what's up next: the
/// channel list, and on a phone the lineup under the picture. A tap, or
/// Enter, tunes.
@MainActor final class ChannelRows {
    private(set) var rows: [(row: El, schedule: ChannelSchedule)]
    private let onSelect: (Int) -> Void

    init(channels: [ChannelSchedule], onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        rows = []
        rows = channels.map(makeRow)
    }

    /// Shows `channels`, rebuilt after a setting changed (a schedule code,
    /// a custom channel): the same rows with their new schedules when the
    /// channels are the same numbers, so focus stays put, or new rows.
    /// - Returns: whether the rows are new, to be put on the page.
    @discardableResult
    func show(_ channels: [ChannelSchedule]) -> Bool {
        guard channels.map(\.channel.number) != rows.map(\.schedule.channel.number) else {
            rows = zip(rows, channels).map { ($0.row, $1) }
            return false
        }
        rows = channels.map(makeRow)
        return true
    }

    private func makeRow(_ schedule: ChannelSchedule) -> (row: El, schedule: ChannelSchedule) {
        let row = El("button", "channel-row")
        let number = schedule.channel.number
        row.attribute("type", "button").attribute("data-number", String(number))
        row.on("click") { [onSelect] _ in onSelect(number) }
        return (row, schedule)
    }

    /// The row of channel `number`.
    func row(for number: Int) -> El? {
        rows.first { $0.schedule.channel.number == number }?.row
    }

    func draw(at date: Date, current: Int) {
        for (row, schedule) in rows {
            Self.draw(row, schedule, at: date, isCurrent: schedule.channel.number == current)
        }
    }

    private static func draw(_ row: El, _ schedule: ChannelSchedule, at date: Date, isCurrent: Bool) {
        row.classed("current", isCurrent)
        let lines: [El]
        let label: String
        switch schedule.nowShowing(at: date) {
        case .programme(let airing):
            lines = [
                El("span", "row-programme", text: airing.item.displayTitle),
                progress(from: airing.start, to: airing.end, at: date),
                El("span", "row-when", text: "Until \(airing.end.clockTime)"),
            ]
            label = "\(airing.item.displayTitle), until \(airing.end.clockTime)"
        case .inBreak(let ended, let next):
            // The programme is over: say what's next, not what ended.
            lines = [
                El("span", "row-programme", text: "Up next: \(next.item.displayTitle)"),
                progress(from: ended.end, to: next.start, at: date, faint: true),
                El("span", "row-when", text: "\(BreakText.title) · starts \(next.start.clockTime)"),
            ]
            label = "\(BreakText.title). Up next, \(next.item.displayTitle), at \(next.start.clockTime)"
        }
        let name = El("span", "row-name", text: schedule.channel.name)
        if isCurrent { name.append(El("span", "live-dot")) }
        row.replaceChildren([
            El("span", "row-number", text: String(schedule.channel.number)),
            El("span", "row-lines", [name] + lines),
        ])
        row.attribute("aria-label", "Channel \(schedule.channel.number), \(schedule.channel.name)\(isCurrent ? ", playing" : ""). \(label)")
        row.attribute("aria-current", isCurrent ? "true" : nil)
    }

    private static func progress(from start: Date, to end: Date, at date: Date, faint: Bool = false) -> El {
        let fraction = DateInterval(start: start, end: max(start, end)).progress(at: date)
        let fill = El("span", "fill")
        fill.style("width", "\((fraction * 1000).rounded() / 10)%")
        return El("span", "row-progress" + (faint ? " faint" : ""), [fill]).attribute("aria-hidden", "true")
    }
}
