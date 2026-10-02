import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// The programme guide: channels down the side, from the current half hour
/// to at least six hours ahead, with the highlighted programme's details
/// above, as on Apple TV. The grid scrolls both ways (by touch too), the
/// channel names and times pinned. Each block's break (commercials or blank
/// airtime after the programme) is a hatched tail at its right edge. A tap
/// or Enter tunes. The bar has **Live TV**, back to the channel playing,
/// Settings and Close. Escape (`RemoteControls.guide`'s `.stepBack`) moves
/// up to Live TV, then from the bar up to the main page. 60 s without
/// activity closes it and stays on the current channel.
@MainActor final class GuidePanel: Page, KeyTarget {
    static let idleTimeout: TimeInterval = 60
    /// Three hours across a wide window.
    static let hourWidth = 380.0

    let element: El
    private let onRemote: (RemoteAction) -> Void
    private let channels: [ChannelSchedule]
    private let header = El("div", "guide-details").attribute("aria-live", "polite")
    private let resume: El
    private let settings: El
    private let grid = El("div", "guide-grid")
    private let window = GuideWindow(containing: .now)
    private var cells: [String: (ChannelSchedule, GuideCell)] = [:]
    private var startCell: String?
    private let idle: IdleTimer

    init(channels: [ChannelSchedule], currentNumber: Int, onSelect: @escaping (Int) -> Void,
         onRemote: @escaping (RemoteAction) -> Void) {
        self.channels = channels
        self.onRemote = onRemote
        idle = IdleTimer(after: Self.idleTimeout) { onRemote(.close) }
        resume = El.button("Live TV", icon: .play, "button primary") { onRemote(.close) }
        settings = El.button(SettingsText.title, icon: .settings, "icon-button", labelHidden: true) { onRemote(.openSettings) }
        let (sheet, body) = Parts.sheet("guide", title: "Guide", actions: [resume, settings]) { onRemote(.close) }
        element = sheet
        body.append(header, grid,
                    El("p", "hint", text: RemoteControls.hint(for: RemoteControls.guide, names: KeyboardControls.names)))
        drawGrid(currentNumber: currentNumber, onSelect: onSelect)
        drawDetails(for: nil)
        element.on("focusin") { [weak self] event in
            self?.drawDetails(for: event.target.object?.dataset.object?.cell.string)
        }
        idle.watch(element)
        Keys.take(self)
        startCell = cells.first { $0.value.0.channel.number == currentNumber && $0.value.1.contains(.now) }?.key
    }

    /// Start on what's on now on the channel being watched.
    func appeared() {
        let button = startCell.flatMap { id in Focus.focusable(in: grid).first { $0.object.dataset.cell.string == id } }
        (button ?? resume).focus()
        _ = button?.object.scrollIntoView!(JSObject.options(["block": "center", "inline": "nearest"]))
    }

    func close() {
        idle.stop()
        Keys.release(self)
    }

    func press(_ button: RemoteButton) -> Bool {
        idle.reset()
        if RemoteControls.guide[button] == .stepBack {
            stepBack()
            return true
        }
        return Overlay.press(button, table: RemoteControls.guide, within: element, onRemote: onRemote)
    }

    /// From a programme up to Live TV (highlighted, not pressed), and from
    /// the bar up to the main page.
    private func stepBack() {
        if let focused = DOM.focused, focused == resume.object || focused == settings.object
            || focused.parentElement.object?.classList.contains("sheet-bar").boolean == true {
            onRemote(.openMainPage)
        } else {
            resume.focus()
        }
    }

    private func x(_ date: Date) -> Double {
        window.fraction(of: date) * window.duration / 3600 * Self.hourWidth
    }

    private func drawGrid(currentNumber: Int, onSelect: @escaping (Int) -> Void) {
        let trackWidth = window.duration / 3600 * Self.hourWidth
        let ruler = El("div", "guide-ruler", window.timeMarks.map { mark in
            let label = El("span", text: mark.clockTime)
            label.style("left", "\(x(mark))px")
            return label
        })
        ruler.style("width", "\(trackWidth)px")
        var rows = [El("div", "guide-row ruler-row", [El("div", "guide-channel corner"), ruler])]
        for schedule in channels {
            let number = schedule.channel.number
            let track = El("div", "guide-track")
            track.style("width", "\(trackWidth)px")
            for cell in window.cells(for: schedule) {
                let id = "\(number)|\(cell.id)"
                cells[id] = (schedule, cell)
                let width = x(cell.visibleEnd) - x(cell.visibleStart)
                let now = cell.contains(.now)
                let block = El("button", "guide-cell" + (now ? " airing-now" : ""))
                block.attribute("type", "button").attribute("data-cell", id)
                    .attribute("aria-label", "Channel \(number), \(schedule.channel.name): \(cell.programme.item.displayTitle), "
                               + "\(cell.programme.start.clockTime) to \(cell.programme.end.clockTime)")
                block.style("left", "\(x(cell.visibleStart))px")
                block.style("width", "\(width)px")
                block.append(El("span", "cell-title", text: (cell.startsBeforeWindow ? "◀ " : "") + cell.programme.item.displayTitle))
                if width >= 110 { block.append(El("span", "cell-time", text: cell.programme.start.clockTime)) }
                if cell.breakFraction > 0 {
                    let tail = El("span", "cell-break").attribute("aria-hidden", "true")
                    tail.style("width", "\(cell.breakFraction * 100)%")
                    block.append(tail)
                }
                block.on("click") { _ in onSelect(number) }
                track.append(block)
            }
            let channel = El("div", "guide-channel" + (number == currentNumber ? " current" : ""), [
                El("span", "guide-number", text: String(number)),
                El("span", "guide-name", text: schedule.channel.name),
            ])
            rows.append(El("div", "guide-row", [channel, track]))
        }
        let nowLine = El("div", "now-line")
        nowLine.style("left", "\(x(.now))px")
        // Down through the rows, not the empty space under them.
        nowLine.style("height", "calc(2.25rem + \(channels.count) * (var(--row) + 1px))")
        nowLine.attribute("aria-hidden", "true")
        grid.replaceChildren(rows + [nowLine])
    }

    /// The highlighted programme's details. In its break, said on the channel line.
    private func drawDetails(for id: String?) {
        guard let id, let (schedule, cell) = cells[id] else {
            header.replaceChildren([El("p", "eyebrow", text: "Now and next"), El("h3", text: "Choose a programme to tune to its channel")])
            return
        }
        let now = Date.now
        var channelLine = "\(schedule.channel.number) · \(schedule.channel.name)"
        if let span = cell.breakSpan, span.start <= now, now < span.end {
            channelLine += " · \(BreakText.title) until \(span.end.clockTime)"
        }
        header.replaceChildren([
            El("p", "eyebrow", text: channelLine),
            El("h3", text: cell.programme.item.displayTitle),
            El("p", text: [cell.programme.item.displaySubtitle,
                           "\(cell.programme.start.clockTime) – \(cell.programme.end.clockTime)"]
                .compactMap { $0 }.joined(separator: " · ")),
        ])
    }
}
