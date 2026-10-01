import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// The watch screen's rules, without drawing anything.
@MainActor @Suite(.serialized)
struct WatchModelTests {
    private func playing() async throws -> WatchModel {
        let model = WatchModel(surfer: try Fixture.surfer())
        model.player.tune()
        try await Fixture.settle(model.player)
        return model
    }

    /// Menu while watching: the banner goes first, then the app goes up to
    /// the main page, with everything closed.
    @Test func menuHidesTheBannerFirstThenGoesUpToTheMainPage() async throws {
        let model = try await playing()
        var opened = 0
        model.onOpenMainPage = { opened += 1 }
        #expect(model.bannerIsShowing, "Up as the programme starts")
        model.perform(.hideInfoOrOpenMainPage)
        #expect(!model.bannerIsShowing && opened == 0)
        model.perform(.hideInfoOrOpenMainPage)
        #expect(opened == 1 && !model.overlayOpen && !model.showingSettings)
        let trigger = model.bannerTrigger
        model.returnedFromMainPage()
        #expect(model.bannerTrigger != trigger, "Back from the main page, the banner says where you are")
        model.perform(.watchLastServer)
        #expect(opened == 1, "Only the main page watches a server")
        model.player.stop()
    }

    /// The guide opens with its own buttons and Menu closes it, back to the
    /// channel: it never passes the main page.
    @Test func menuClosesTheGuideBackToTheChannel() async throws {
        let model = try await playing()
        var opened = 0
        model.onOpenMainPage = { opened += 1 }
        let opens = RemoteControls.watching.filter { $0.value == .openGuide }.keys
        #expect(Set(opens) == [.clickDown, .swipeUp])
        model.perform(.openGuide)
        #expect(model.showingGuide)
        model.perform(try #require(RemoteControls.guide[.menu]))
        #expect(!model.overlayOpen && opened == 0)
        model.player.stop()
    }

    @Test func aSecondChangeWithinHalfASecondIsIgnored() async throws {
        let model = try await playing()
        model.show(.guide)
        model.show(.channelList)
        #expect(model.showingGuide && !model.showingList, "A double-click can't jump straight to another overlay")
        model.player.stop()
    }

    @Test func choosingAChannelTunesAndClosesTheGuide() async throws {
        let model = try await playing()
        model.show(.guide)
        try await Task.sleep(for: .seconds(WatchModel.clickGuard + 0.1))
        model.select(channel: 2)
        #expect(!model.overlayOpen)
        #expect(model.player.schedule.channel.number == 2)
        model.player.stop()
    }

    @Test func settingsFromTheGuideGoesBackToIt() async throws {
        let model = try await playing()
        model.show(.guide)
        try await Task.sleep(for: .seconds(WatchModel.clickGuard + 0.1))
        model.perform(.openSettings)
        #expect(model.showingSettings && !model.showingGuide)
        model.showingSettings = false
        #expect(model.settingsClosed() == false, "Focus stays with the guide")
        #expect(model.showingGuide)
        model.player.stop()
    }

    @Test func thePictureFadesOutWhileChangingChannelAndBackOnceItPlays() async throws {
        let model = try await playing()
        #expect(!model.changingChannel)
        model.perform(.channelUp)
        #expect(model.changingChannel, "Fades as soon as surfing starts")
        #expect(model.bannerIsShowing, "The banner previews the channel meanwhile")
        try await Task.sleep(for: ChannelSurfer.settleDelay + .milliseconds(100))
        try await Fixture.settle(model.player)
        #expect(model.player.schedule.channel.number == 2)
        #expect(!model.changingChannel, "Back once the new channel plays")
        model.player.stop()
    }

    @Test func surfingBackToTheSameChannelBringsThePictureBack() async throws {
        let model = try await playing()
        model.perform(.channelUp)
        model.perform(.channelDown)
        try await Task.sleep(for: ChannelSurfer.settleDelay + .milliseconds(100))
        #expect(model.player.schedule.channel.number == 1)
        #expect(!model.changingChannel)
        model.player.stop()
    }

    @Test func touchingWhileTheBannerIsUpSwitchesTheTime() async throws {
        let model = try await playing()
        let before = try #require(model.banner(at: .now).programme?.time)
        #expect(before.hasPrefix("Ends"))
        model.perform(.showInfo)
        let after = try #require(model.banner(at: .now).programme?.time)
        #expect(after.hasSuffix("left"))
        model.player.stop()
    }

    @Test func theBannerNamesTheChannelAndProgramme() async throws {
        let model = try await playing()
        let banner = model.banner(at: .now)
        #expect(banner.channelNumber == 1 && banner.channelName == "C1")
        #expect(banner.programme?.title.hasPrefix("Film") == true)
        #expect(banner.hint == RemoteControls.hint(for: RemoteControls.watching))
        model.player.stop()
    }
}
