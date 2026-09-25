import Foundation

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
// Actions: .channelUp .channelDown .showInfo .hideInfo .hideInfoOrOpenGuide
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
// - These tables are shared by every version of the app; each one connects
//   its own input (the Siri Remote here) to them.
// - With the Apple TV's *Settings › Remotes and Devices › Clickpad* set to
//   "Click and Touch", tvOS reports a light tap on the edge of the pad as an
//   edge click. `RemoteGestures` tells them apart (a real click presses
//   while the finger's still down) and treats such a tap as `.touchTap`.
//   If that ever misfires, "Click Only" stops tvOS doing it.
// - Don't map both `.click` and `.touchTap` to `.showInfo`: a click also
//   touches the pad, so it would count twice (show, then switch the time).
// - While watching, Menu (or Back ‹) hides the banner if it's up, or else
//   opens the guide, and never leaves the app: the TV (Home) button does. (Apple asks that Menu on an app's main
//   screen goes to the Home screen; delete `.menu` from `watching` for that.)
// - Digits on a keyboard always type a channel number.

public enum RemoteControls {
    /// Watching live TV, with nothing open. The app starts here.
    public static let watching: [RemoteButton: RemoteAction] = [
        .clickLeft: .channelDown,
        .clickRight: .channelUp,
        .swipeLeft: .openChannelList,
        .touchTap: .showInfo,
        .clickAndHold: .openSettings,
        .playPause: .pauseOrJumpToLive,
        .menu: .hideInfoOrOpenGuide,
    ]

    /// The channel list (opened by sliding left while watching).
    public static let channelList: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .swipeRight: .close,
        .playPause: .openSettings,
    ]

    /// The programme guide (opened with Menu while watching).
    public static let guide: [RemoteButton: RemoteAction] = [
        .menu: .stepBack,
        .playPause: .openSettings,
    ]

    /// Settings.
    public static let settings: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .playPause: .close,
    ]
}

// MARK: - Buttons and actions

/// Which way an edge click or a slide goes.
public enum RemoteDirection: Sendable, Equatable {
    case up, down, left, right
}

/// The Siri Remote's buttons. In the simulator, the keyboard's arrow keys
/// are clicks on the edge of the pad, Return is a click, Escape is Menu and
/// Space is Play/Pause; the simulator has no swipes or light touches.
public enum RemoteButton: Hashable, CaseIterable, Sendable {
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
    public var symbol: String {
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
    public var direction: RemoteDirection? {
        switch self {
        case .clickUp, .swipeUp: .up
        case .clickDown, .swipeDown: .down
        case .clickLeft, .swipeLeft: .left
        case .clickRight, .swipeRight: .right
        default: nil
        }
    }
}

/// Everything a button can do. `WatchModel.perform(_:)` carries them out.
public enum RemoteAction: Hashable, CaseIterable, Sendable {
    case channelUp
    case channelDown
    /// The info banner; again while it's up, switch end time / time left.
    case showInfo
    /// Put the banner away at once.
    case hideInfo
    /// Put the banner away if it's up; otherwise open the guide.
    case hideInfoOrOpenGuide
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
    public var label: String {
        switch self {
        case .channelUp: "channel up"
        case .channelDown: "channel down"
        case .showInfo: "info"
        case .hideInfo: "hide info"
        case .hideInfoOrOpenGuide: "hide info, or guide"
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
    public static func hint(for map: [RemoteButton: RemoteAction]) -> String {
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
