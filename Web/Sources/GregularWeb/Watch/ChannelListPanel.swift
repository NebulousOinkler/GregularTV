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

/// What the channel list, guide and Settings do with a key: the arrows move
/// the highlight, and one with nowhere to go counts as the remote's click or
/// slide that way (as tvOS reports both as the same arrow there); the rest
/// do what `table` says. Enter is left to the highlighted button.
@MainActor enum Overlay {
    static func press(_ button: RemoteButton, table: [RemoteButton: RemoteAction], within container: El,
                      onRemote: (RemoteAction) -> Void) -> Bool {
        if let direction = button.direction {
            if Focus.move(direction, within: container) { return true }
            let action = RemoteButton.allCases.lazy.filter { $0.direction == direction }.compactMap { table[$0] }.first
            guard let action else { return false }
            onRemote(action)
            return true
        }
        guard button != .click, let action = table[button] else { return false }
        onRemote(action)
        return true
    }
}

/// Calls `action` after a while with no key, click or mouse movement.
@MainActor final class IdleTimer {
    private let seconds: TimeInterval
    private let action: () -> Void
    private var task: Task<Void, Never>?

    init(after seconds: TimeInterval, action: @escaping () -> Void) {
        self.seconds = seconds
        self.action = action
        reset()
    }

    /// Any activity in `element` starts the wait again.
    func watch(_ element: El) {
        for event in ["pointermove", "pointerdown", "wheel", "focusin"] {
            element.on(event) { [weak self] _ in self?.reset() }
        }
    }

    func reset() {
        task?.cancel()
        let seconds = seconds
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.action()
        }
    }

    func stop() {
        task?.cancel()
    }
}
