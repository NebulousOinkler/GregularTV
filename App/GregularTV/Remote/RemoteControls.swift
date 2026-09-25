import SwiftUI

// MARK: - What each button does. Edit these tables.
//
// Each screen has a table of `button: action`. To change what a button does,
// change its action; to make a button do nothing, delete its line. One action
// can have several buttons. The hints on screen (the banner, the channel list,
// the guide, Settings) are written from these tables, so they stay correct.
//
// Buttons:
//   .clickUp .clickDown .clickLeft .clickRight   pressing the edge of the click pad
//   .swipeUp .swipeDown .swipeLeft .swipeRight   sliding a finger across the touch surface
//   .click .clickAndHold                          the centre (or the touch surface)
//   .touchTap                                     a light touch, without clicking
//   .playPause .menu
// Actions: .channelUp .channelDown .showInfo .showInfoSlowly .hideInfo
//          .pauseOrJumpToLive .openChannelList .openGuide .openSettings
//          .close .stepBack
//
// Fixed, not in the tables:
// - Clicks and swipes are told apart only while watching. In the channel
//   list, guide and Settings, tvOS reports both as the same arrow, so
//   `.clickRight` and `.swipeRight` there are the same thing. Arrows there
//   always move the highlight too, so only map one that has nowhere to go
//   (like right in the channel list, whose rows are one column), and a click
//   always chooses the highlighted item.
// - `.clickAndHold`, `.touchTap` and the swipes only work while watching.
// - With the Apple TV's *Settings › Remotes and Devices › Clickpad* set to
//   "Click and Touch", a light touch on the edge of the pad counts as a click
//   there. Set it to "Click Only" to keep light touches for `.touchTap`.
// - While watching, Menu (or Back ‹) opens the guide, and never leaves the
//   app: the TV (Home) button does. (Apple asks that Menu on an app's main
//   screen goes to the Home screen; delete `.menu` from `watching` for that.)
// - Digits on a keyboard always type a channel number.

enum RemoteControls {
    /// Watching live TV, with nothing open. The app starts here.
    static let watching: [RemoteButton: RemoteAction] = [
        .clickLeft: .channelDown,
        .clickRight: .channelUp,
        .swipeLeft: .openChannelList,
        .swipeUp: .showInfoSlowly,
        .swipeDown: .hideInfo,
        .touchTap: .showInfo,
        .click: .showInfo,
        .clickAndHold: .openSettings,
        .playPause: .pauseOrJumpToLive,
        .menu: .openGuide,
    ]

    /// The channel list (opened by sliding left while watching).
    static let channelList: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .swipeRight: .close,
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

/// The Siri Remote's buttons. In the simulator, the keyboard's arrow keys
/// are clicks on the edge of the pad, Return is a click, Escape is Menu and
/// Space is Play/Pause; the simulator has no swipes or light touches.
enum RemoteButton: Hashable, CaseIterable {
    case clickUp, clickDown, clickLeft, clickRight
    case swipeUp, swipeDown, swipeLeft, swipeRight
    /// Clicking the centre of the click pad, or the touch surface.
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
        case .clickUp: "click ▲"
        case .clickDown: "click ▼"
        case .clickLeft: "click ◀"
        case .clickRight: "click ▶"
        case .swipeUp: "slide ▲"
        case .swipeDown: "slide ▼"
        case .swipeLeft: "slide ◀"
        case .swipeRight: "slide ▶"
        case .click: "click"
        case .clickAndHold: "hold click"
        case .touchTap: "touch"
        case .playPause: "Play/Pause"
        case .menu: "Menu"
        }
    }

    /// The arrow direction, for the edge clicks and swipes.
    var direction: MoveCommandDirection? {
        switch self {
        case .clickUp, .swipeUp: .up
        case .clickDown, .swipeDown: .down
        case .clickLeft, .swipeLeft: .left
        case .clickRight, .swipeRight: .right
        default: nil
        }
    }
}

/// Everything a button can do. `WatchView.perform(_:)` carries them out.
enum RemoteAction: Hashable, CaseIterable {
    case channelUp
    case channelDown
    /// The info banner; again while it's up, switch end time / time left.
    case showInfo
    /// The info banner, fading in slowly.
    case showInfoSlowly
    /// Put the banner away at once.
    case hideInfo
    /// Pause, or if paused, jump back to live.
    case pauseOrJumpToLive
    case openChannelList
    case openGuide
    case openSettings
    /// Close whatever's open (the channel list, guide or Settings).
    case close
    /// One step back. In the guide: from the programmes to the Settings
    /// button (highlighted, not pressed), then back to watching. Elsewhere, `.close`.
    case stepBack

    /// How hints describe the action.
    var label: String {
        switch self {
        case .channelUp: "channel up"
        case .channelDown: "channel down"
        case .showInfo, .showInfoSlowly: "info"
        case .hideInfo: "hide info"
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
    /// "click ◀▶: channels · slide ◀: channel list · click or touch: info".
    static func hint(for map: [RemoteButton: RemoteAction]) -> String {
        // The usual pairings read better as one.
        let pairs: [(RemoteButton, RemoteButton, String)] = [
            (.clickDown, .clickUp, "click ▼▲"), (.clickLeft, .clickRight, "click ◀▶"),
            (.swipeDown, .swipeUp, "slide ▼▲"), (.swipeLeft, .swipeRight, "slide ◀▶"),
        ]
        let paired = pairs.filter { map[$0.0] == .channelDown && map[$0.1] == .channelUp }
        let pairedButtons = Set(paired.flatMap { [$0.0, $0.1] })
        var parts = paired.isEmpty ? [] : [paired.map(\.2).joined(separator: " or ") + ": channels"]
        // Labels shared by several actions (info) are listed once.
        var labels: [String] = []
        var buttonsByLabel: [String: [RemoteButton]] = [:]
        for action in RemoteAction.allCases {
            let buttons = RemoteButton.allCases.filter { map[$0] == action && !pairedButtons.contains($0) }
            guard !buttons.isEmpty else { continue }
            if buttonsByLabel[action.label] == nil { labels.append(action.label) }
            buttonsByLabel[action.label, default: []] += buttons
        }
        for label in labels {
            let buttons = RemoteButton.allCases.filter { buttonsByLabel[label]!.contains($0) }
            parts.append(buttons.map(\.symbol).joined(separator: " or ") + ": " + label)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Attaching a table to a view

extension View {
    /// Sends the table's buttons to `perform` while this view (or something
    /// inside it) has focus. Buttons not in the table keep their usual tvOS behaviour.
    /// Edge clicks, swipes and `.touchTap` while watching are handled
    /// separately, by `RemoteGestures`, which can tell them apart.
    /// - Parameter takesClicks: whether `.click` and `.clickAndHold` apply. Only
    ///   for a view with no buttons inside, since it would take their clicks.
    /// - Parameter takesArrows: whether edge clicks and swipes are handled here,
    ///   as SwiftUI's arrows (which can't tell a click from a swipe).
    func remoteControls(_ map: [RemoteButton: RemoteAction], takesClicks: Bool = false, takesArrows: Bool = true,
                        perform: @escaping (RemoteAction) -> Void) -> some View {
        modifier(RemoteControlsModifier(map: map, takesClicks: takesClicks, takesArrows: takesArrows, perform: perform))
    }
}

private struct RemoteControlsModifier: ViewModifier {
    let map: [RemoteButton: RemoteAction]
    let takesClicks: Bool
    let takesArrows: Bool
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
        takesArrows && map.keys.contains { $0.direction != nil }
    }

    /// An arrow here is a click or a swipe: whichever is mapped (the click if both).
    private func move(_ direction: MoveCommandDirection) {
        let action = RemoteButton.allCases.lazy.filter { $0.direction == direction }.compactMap { map[$0] }.first
        if let action { perform(action) }
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
