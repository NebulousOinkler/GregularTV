import SwiftUI

// MARK: - What each button does. Edit these tables.
//
// Each screen has a table of `button: action`. To change what a button does,
// change its action; to make a button do nothing, delete its line. One action
// can have several buttons. The hints on screen (the banner, the channel list,
// the guide, Settings) are written from these tables, so they stay correct.
//
// Buttons: .up .down .left .right .click .clickAndHold .touchTap .playPause .menu
// Actions: .channelUp .channelDown .showInfo .pauseOrJumpToLive
//          .openChannelList .openGuide .openSettings .close .stepBack
//
// Fixed, not in the tables:
// - In the channel list, guide and Settings, the arrows always move the
//   highlight and a click always chooses the highlighted item. An arrow you
//   map there does its action *as well*, so only map one that has nowhere to
//   go (like Right in the channel list, whose rows are one column).
// - `.clickAndHold` and `.touchTap` only work while watching.
// - `.touchTap` isn't used as shipped: a light tap near the top or bottom of
//   the touch surface also counts as Up or Down, so it was easy to change
//   channel when you meant to show the banner.
// - The guide is the app's main screen. Menu (or Back ‹) goes back to it
//   while watching, and from the guide leaves the app, as tvOS expects: Apple
//   asks that Menu on an app's main screen always goes to the Home screen.
//   Keep a way to leave from the guide if you change these.
// - Digits on a keyboard always type a channel number.

enum RemoteControls {
    /// Watching live TV, with nothing open.
    static let watching: [RemoteButton: RemoteAction] = [
        .up: .channelUp,
        .down: .channelDown,
        .left: .openChannelList,
        .right: .showInfo,
        .click: .showInfo,
        .clickAndHold: .openSettings,
        .playPause: .pauseOrJumpToLive,
        .menu: .openGuide,
    ]

    /// The channel list (opened with Left while watching).
    static let channelList: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .right: .close,
        .playPause: .openSettings,
    ]

    /// The programme guide (opened with Menu while watching).
    static let guide: [RemoteButton: RemoteAction] = [
        .menu: .stepBack,
        .playPause: .openSettings,
    ]

    /// Settings.
    static let settings: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .playPause: .close,
    ]
}

// MARK: - Buttons and actions

/// The Siri Remote's buttons. In the simulator, the keyboard's arrow keys,
/// Return (click), Escape (Menu) and Space (Play/Pause) act the same.
enum RemoteButton: Hashable, CaseIterable {
    case up, down, left, right
    /// Clicking the touch surface, or the centre of the click pad.
    case click
    /// Holding a click for over half a second.
    case clickAndHold
    /// A light touch on the touch surface, without clicking.
    case touchTap
    case playPause
    /// Menu, or Back (‹) on newer remotes.
    case menu

    /// How hints show the button.
    var symbol: String {
        switch self {
        case .up: "▲"
        case .down: "▼"
        case .left: "◀"
        case .right: "▶"
        case .click: "click"
        case .clickAndHold: "hold click"
        case .touchTap: "tap"
        case .playPause: "Play/Pause"
        case .menu: "Menu"
        }
    }
}

/// Everything a button can do. `WatchView.perform(_:)` carries them out.
enum RemoteAction: Hashable, CaseIterable {
    case channelUp
    case channelDown
    /// The info banner; again while it's up, switch end time / time left.
    case showInfo
    /// Pause, or if paused, jump back to live.
    case pauseOrJumpToLive
    case openChannelList
    case openGuide
    case openSettings
    /// Close whatever's open (the channel list, guide or Settings).
    case close
    /// One step back. In the guide: from the programmes to the Settings
    /// button (highlighted, not pressed), then out of the app. Elsewhere, `.close`.
    case stepBack

    /// How hints describe the action.
    var label: String {
        switch self {
        case .channelUp: "channel up"
        case .channelDown: "channel down"
        case .showInfo: "info"
        case .pauseOrJumpToLive: "pause"
        case .openChannelList: "channel list"
        case .openGuide: "guide"
        case .openSettings: "Settings"
        case .close: "close"
        case .stepBack: "back"
        }
    }
}

extension RemoteControls {
    /// A one-line hint from a table, such as
    /// "▲▼ channels · ▶ or click: info · ◀: channel list".
    static func hint(for map: [RemoteButton: RemoteAction]) -> String {
        // The usual pairing reads better as one.
        let paired = map[.up] == .channelUp && map[.down] == .channelDown
        var parts = paired ? ["▲▼ channels"] : []
        for action in RemoteAction.allCases {
            let buttons = RemoteButton.allCases.filter { map[$0] == action && !(paired && [.up, .down].contains($0)) }
            guard !buttons.isEmpty else { continue }
            parts.append(buttons.map(\.symbol).joined(separator: " or ") + ": " + action.label)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Attaching a table to a view

extension View {
    /// Sends the table's buttons to `perform` while this view (or something
    /// inside it) has focus. Buttons not in the table keep their usual tvOS behaviour.
    /// `.touchTap` is handled separately, by `RemoteSurfaceTap`.
    /// - Parameter takesClicks: whether `.click` and `.clickAndHold` apply. Only
    ///   for a view with no buttons inside, since it would take their clicks.
    func remoteControls(_ map: [RemoteButton: RemoteAction], takesClicks: Bool = false,
                        perform: @escaping (RemoteAction) -> Void) -> some View {
        modifier(RemoteControlsModifier(map: map, takesClicks: takesClicks, perform: perform))
    }
}

private struct RemoteControlsModifier: ViewModifier {
    let map: [RemoteButton: RemoteAction]
    let takesClicks: Bool
    let perform: (RemoteAction) -> Void

    func body(content: Content) -> some View {
        let onMove: ((MoveCommandDirection) -> Void)? = hasArrows ? { move($0) } : nil
        let onPlayPause: (() -> Void)? = handler(for: .playPause)
        // Leaving this nil keeps Menu's usual job (going back, or Home).
        let onMenu: (() -> Void)? = handler(for: .menu)
        let clicks = ClickGestures(click: takesClicks ? handler(for: .click) : nil,
                                   hold: takesClicks ? handler(for: .clickAndHold) : nil)
        return content
            .onMoveCommand(perform: onMove)
            .onPlayPauseCommand(perform: onPlayPause)
            .onExitCommand(perform: onMenu)
            .modifier(clicks)
    }

    private var hasArrows: Bool {
        [.up, .down, .left, .right].contains { map[$0] != nil }
    }

    private func move(_ direction: MoveCommandDirection) {
        let button: RemoteButton? = switch direction {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        @unknown default: nil
        }
        if let button, let action = map[button] { perform(action) }
    }

    private func handler(for button: RemoteButton) -> (() -> Void)? {
        guard let action = map[button] else { return nil }
        let perform = perform
        return { perform(action) }
    }
}

/// Click and click-and-hold, only when mapped: a tap gesture on a container
/// would otherwise take clicks meant for the buttons inside it.
private struct ClickGestures: ViewModifier {
    let click: (() -> Void)?
    let hold: (() -> Void)?

    func body(content: Content) -> some View {
        switch (click, hold) {
        case let (click?, hold?):
            // The hold is declared first, so a quick click isn't taken as the start of one.
            content.onLongPressGesture(minimumDuration: 0.6, perform: hold).onTapGesture(perform: click)
        case let (click?, nil):
            content.onTapGesture(perform: click)
        case let (nil, hold?):
            content.onLongPressGesture(minimumDuration: 0.6, perform: hold)
        case (nil, nil):
            content
        }
    }
}
