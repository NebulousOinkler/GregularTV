import Testing
@testable import GregularScreens
@testable import GregularTV

/// The remote's button tables in `RemoteControls`, and the hints written from them.
struct RemoteControlsTests {
    @Test func hintsAreWrittenFromTheTables() {
        #expect(RemoteControls.hint(for: RemoteControls.watching)
                == "click ◀▶: channels · touch: info · Menu: hide info, or guide · Play/Pause: pause · slide ◀: channel list · hold click: Settings")
        #expect(RemoteControls.hint(for: RemoteControls.watching, paused: true).contains("Play/Pause: jump to live"))
        #expect(RemoteControls.hint(for: RemoteControls.settings, onScreen: [.close: "Done"]) == "Play/Pause, Menu or Done: close")
        #expect(RemoteControls.hint(for: [:], onScreen: [.close: "Done"]) == "Done: close")
        #expect(RemoteControls.hint(for: RemoteControls.channelList) == "Play/Pause: Settings · slide ▶ or Menu: close")
        #expect(RemoteControls.hint(for: RemoteControls.guide) == "Play/Pause: Settings · Menu: back")
        #expect(RemoteControls.hint(for: [.clickLeft: .channelUp, .menu: .close]) == "click ◀: channel up · Menu: close")
    }

    @Test func clicksAndSwipesShareAnArrowDirection() {
        #expect(RemoteButton.clickLeft.direction == .left && RemoteButton.swipeLeft.direction == .left)
        #expect(RemoteButton.click.direction == nil && RemoteButton.touchTap.direction == nil)
    }

    @Test func watchingTellsClicksFromSwipes() {
        let map = RemoteControls.watching
        #expect(map[.clickLeft] == .channelDown && map[.clickRight] == .channelUp)
        #expect(map[.swipeLeft] == .openChannelList && map[.swipeUp] == nil && map[.swipeDown] == nil)
        #expect(map[.touchTap] == .showInfo && map[.clickAndHold] == .openSettings)
        #expect(map[.menu] == .hideInfoOrOpenGuide)
        #expect(map[.click] == nil, "A click touches the pad too: mapping both would count it twice")
    }

    @Test func everyMenuCanBeClosedFromTheRemote() {
        for map in [RemoteControls.channelList, RemoteControls.guide, RemoteControls.settings] {
            #expect(map.values.contains(.close) || map.values.contains(.stepBack))
        }
    }

    #if DEBUG || (REMOTE_KEYS && targetEnvironment(simulator))
    @Test func debugKeysReachWhatTheKeyboardCant() {
        let keys = RemoteControls.debugKeys
        #expect(Set(keys.values).count == keys.count, "One key per button")
        #expect(keys.keys.allSatisfy { !$0.isNumber }, "Digits type channel numbers")
        #expect(Set(keys.values).isSuperset(of: [.menu, .playPause, .clickAndHold, .touchTap,
                                                 .swipeUp, .swipeDown, .swipeLeft, .swipeRight]))
    }
    #endif

    @Test func watchingCanReachEveryScreen() {
        let actions = Set(RemoteControls.watching.values)
        #expect(actions.isSuperset(of: [.openChannelList, .openSettings, .channelUp, .channelDown]))
        #expect(actions.contains(.openGuide) || actions.contains(.hideInfoOrOpenGuide))
    }
}
