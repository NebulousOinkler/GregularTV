import Testing
@testable import GregularTV

/// The remote's button tables in `RemoteControls`, and the hints written from them.
struct RemoteControlsTests {
    @Test func hintsAreWrittenFromTheTables() {
        #expect(RemoteControls.hint(for: RemoteControls.watching)
                == "click ◀▶: channels · slide ▲ or click or touch: info · slide ▼: hide info · Play/Pause: pause · slide ◀: channel list · Menu: guide · hold click: Settings")
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
        #expect(map[.swipeLeft] == .openChannelList && map[.swipeUp] == .showInfoSlowly && map[.swipeDown] == .hideInfo)
        #expect(map[.touchTap] == .showInfo && map[.clickAndHold] == .openSettings)
    }

    @Test func everyMenuCanBeClosedFromTheRemote() {
        for map in [RemoteControls.channelList, RemoteControls.guide, RemoteControls.settings] {
            #expect(map.values.contains(.close) || map.values.contains(.stepBack))
        }
    }

    @Test func watchingCanReachEveryScreen() {
        let actions = Set(RemoteControls.watching.values)
        #expect(actions.isSuperset(of: [.openChannelList, .openGuide, .openSettings, .channelUp, .channelDown]))
    }
}
