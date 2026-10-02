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
//          .close .stepBack .openMainPage .watchLastServer
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
// - Most Siri Remotes report any click on the pad as a centre click; the
//   Apple TV app's `RemoteGestures` reads where the finger is to tell an
//   edge click from a centre one. With *Settings › Remotes and Devices ›
//   Clickpad* set to "Click and Touch", tvOS also turns a light tap on the
//   edge into an arrow press; `RemoteGestures` ignores those, so the tap is
//   just `.touchTap`. If that ever misfires, "Click Only" stops tvOS doing it.
// - Don't map both `.click` and `.touchTap` to `.showInfo`: a click also
//   touches the pad, so it would count twice (show, then switch the time).
// - How Menu moves around the app, one step at a time:
//
//     live TV ─Menu─▶ guide ─Menu─▶ Resume ─Menu─▶ main page ─Menu─▶ Home screen
//
//   While watching, Menu hides the banner if it's up; otherwise it opens
//   the guide. In the guide, Menu moves up to the top row, onto **Resume
//   Live TV** (next to Settings): a click there goes back to the channel.
//   Menu again, from anywhere on that top row, goes
//   up to the main page (the servers), with the channel still playing
//   behind it and its server highlighted, so a click (or Play/Pause) carries
//   on without re-tuning. The main page is the app's first screen, so Menu
//   there goes to the Apple TV Home screen, as Apple asks (`mainPage` leaves
//   `.menu` to tvOS). The channel list and Settings close with Menu.
//   (`.openMainPage` and `.watchLastServer` are carried out by the app, and
//   `.stepBack` in the guide by `GuideView`, which knows where focus is.)
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
    ]

    /// The main page: the servers, and adding one. The app opens here. Menu
    /// isn't in the table: it goes to the Home screen.
    public static let mainPage: [RemoteButton: RemoteAction] = [
        .playPause: .watchLastServer,
    ]

    /// Settings.
    public static let settings: [RemoteButton: RemoteAction] = [
        .menu: .close,
        .playPause: .close,
    ]

    #if DEBUG || (REMOTE_KEYS && targetEnvironment(simulator))
    /// Debug builds, and Release builds for the simulator made with the
    /// `REMOTE_KEYS` flag (README, *Debug options*), which never reach a
    /// device: letter keys for the remote's buttons, for the simulator, where some can't be pressed from a keyboard (slides, a
    /// light touch, click and hold) and a host may keep Escape for itself.
    /// Each key does whatever its button does on the screen showing. The
    /// arrow keys, Return, Escape and Space still work as usual.
    public static let debugKeys: [Character: RemoteButton] = [
        "m": .menu,
        "p": .playPause,
        "h": .clickAndHold,
        "t": .touchTap,
        "w": .swipeUp,
        "a": .swipeLeft,
        "s": .swipeDown,
        "d": .swipeRight,
    ]
    #endif
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
    /// One step back. In the guide: from the programmes up to Resume Live TV
    /// (highlighted, not pressed), and from that top row up to the main page.
    /// Elsewhere, `.close`.
    case stepBack
    /// The main page: the servers, with the channel playing on behind it.
    /// Carried out by the app.
    case openMainPage
    /// From the main page, watch the server watched last. Carried out by the app.
    case watchLastServer

    /// How hints describe the action while paused, if that's different.
    public var pausedLabel: String {
        self == .pauseOrJumpToLive ? "jump to live" : label
    }

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
        case .openMainPage: "servers"
        case .watchLastServer: "watch"
        }
    }
}

extension RemoteControls {
    /// A one-line hint from a table, such as
    /// "click ◀▶: channels · slide ◀: channel list · click or touch: info".
    /// - Parameters:
    ///   - paused: live TV is paused, so Play/Pause jumps to live.
    ///   - onScreen: buttons on the screen that do an action too, listed
    ///     with the remote's: `[.close: "Done"]` gives "Menu or Done: close".
    public static func hint(for map: [RemoteButton: RemoteAction], paused: Bool = false,
                            onScreen: [RemoteAction: String] = [:]) -> String {
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
        var namesByLabel: [String: [String]] = [:]
        for action in RemoteAction.allCases {
            let buttons = RemoteButton.allCases.filter { map[$0] == action && !pairedButtons.contains($0) }
            let name = onScreen[action]
            guard !buttons.isEmpty || name != nil else { continue }
            let label = paused ? action.pausedLabel : action.label
            if buttonsByLabel[label] == nil { labels.append(label) }
            buttonsByLabel[label, default: []] += buttons
            if let name { namesByLabel[label, default: []].append(name) }
        }
        for label in labels {
            let buttons = RemoteButton.allCases.filter { buttonsByLabel[label]!.contains($0) }
            parts.append(orList(buttons.map(\.symbol) + namesByLabel[label, default: []]) + ": " + label)
        }
        return parts.joined(separator: " · ")
    }

    /// The main page's hint: its table, what a click and holding a click do
    /// to the highlighted server, and Menu, which tvOS takes to the Home screen.
    public static var mainPageHint: String {
        "click: watch · hold click: sign out · " + hint(for: mainPage) + " · Menu: Home screen"
    }

    /// "A", "A or B", "A, B or C".
    private static func orList(_ names: [String]) -> String {
        guard names.count > 2 else { return names.joined(separator: " or ") }
        return names.dropLast().joined(separator: ", ") + " or " + names.last!
    }
}
