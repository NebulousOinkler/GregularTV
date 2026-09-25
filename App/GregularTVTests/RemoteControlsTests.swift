import Testing
@testable import GregularTV

/// The remote's button tables in `RemoteControls`, and the hints written from them.
struct RemoteControlsTests {
    @Test func hintsAreWrittenFromTheTables() {
        #expect(RemoteControls.hint(for: RemoteControls.watching)
                == "▲▼ channels · ▶ or tap: info · Play/Pause: pause · ◀: channel list · click: guide · hold click: Settings")
        #expect(RemoteControls.hint(for: RemoteControls.guide) == "Play/Pause: Settings · Menu: close")
        #expect(RemoteControls.hint(for: [.left: .channelUp, .menu: .close]) == "◀: channel up · Menu: close")
    }

    @Test func everyMenuCanBeClosedFromTheRemote() {
        for map in [RemoteControls.channelList, RemoteControls.guide, RemoteControls.settings] {
            #expect(map.values.contains(.close))
        }
    }

    @Test func watchingCanReachEveryScreen() {
        let actions = Set(RemoteControls.watching.values)
        #expect(actions.isSuperset(of: [.openChannelList, .openGuide, .openSettings, .channelUp, .channelDown]))
    }
}
