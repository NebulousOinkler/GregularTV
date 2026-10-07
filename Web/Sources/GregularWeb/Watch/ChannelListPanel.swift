import Foundation
import GregularCore
import GregularScreens
import JavaScriptKit

/// The channel selector: every channel with what's on now, or, in a break,
/// what's up next (`ChannelRows`). Opened with `RemoteControls.watching` (L,
/// or the Channels button). A tap or Enter tunes. Close,
/// `RemoteControls.channelList`'s buttons (→ or Escape, as shipped), or 15 s
/// without activity, close it and stay on the current channel.
@MainActor final class ChannelListPanel: Page, KeyTarget {
    static let idleTimeout: TimeInterval = 15

    let element: El
    private let rows: ChannelRows
    private let currentNumber: Int
    private let onRemote: (RemoteAction) -> Void
    private let clock = Clock(every: 30)
    private var redraw: Redraw?
    private let idle: IdleTimer

    init(channels: [ChannelSchedule], currentNumber: Int, onSelect: @escaping (Int) -> Void,
         onRemote: @escaping (RemoteAction) -> Void) {
        self.currentNumber = currentNumber
        self.onRemote = onRemote
        idle = IdleTimer(after: Self.idleTimeout) { onRemote(.close) }
        rows = ChannelRows(channels: channels, onSelect: onSelect)
        let (sheet, body) = Parts.sheet("channel-list", title: "Channels") { onRemote(.close) }
        element = sheet
        body.append(El("p", "hint", text: RemoteControls.hint(for: RemoteControls.channelList, names: KeyboardControls.names)))
        for (row, _) in rows.rows { body.append(row) }
        redraw = Redraw { [clock, rows] in rows.draw(at: clock.now, current: currentNumber) }
        idle.watch(element)
        Keys.take(self)
    }

    /// Start on the channel being watched.
    func appeared() {
        guard let row = rows.row(for: currentNumber) ?? rows.rows.first?.row else { return }
        row.focus()
        _ = row.object.scrollIntoView!(JSObject.options(["block": "center"]))
    }

    func close() {
        redraw?.stop()
        clock.stop()
        idle.stop()
        Keys.release(self)
    }

    func press(_ button: RemoteButton) -> Bool {
        idle.reset()
        return Overlay.press(button, table: RemoteControls.channelList, within: element, onRemote: onRemote)
    }
}
