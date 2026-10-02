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

    @Test func menuHidesTheBannerFirstThenOpensTheGuide() async throws {
        let model = try await playing()
        #expect(model.bannerIsShowing, "Up as the programme starts")
        model.perform(try #require(RemoteControls.watching[.menu]))
        #expect(!model.bannerIsShowing && !model.showingGuide)
        model.perform(try #require(RemoteControls.watching[.menu]))
        #expect(model.showingGuide)
        model.player.stop()
    }

    /// Resume Live TV in the guide closes it, back to the channel as it is.
    @Test func resumeClosesTheGuideBackToTheChannel() async throws {
        let model = try await playing()
        var opened = 0
        model.onOpenMainPage = { opened += 1 }
        model.show(.guide)
        let tunes = model.player.tuneCount
        model.perform(.close)
        #expect(!model.overlayOpen && opened == 0 && model.player.tuneCount == tunes)
        model.player.stop()
    }

    /// Menu from the guide's top row: everything closes and the app takes
    /// over, with the channel playing on behind the main page.
    @Test func upToTheMainPageHandsOverToTheApp() async throws {
        let model = try await playing()
        var opened = 0
        model.onOpenMainPage = { opened += 1 }
        model.show(.guide)
        model.perform(.openMainPage)
        #expect(opened == 1 && !model.overlayOpen && !model.showingSettings)
        let trigger = model.bannerTrigger
        model.returnedFromMainPage()
        #expect(model.bannerTrigger != trigger, "Back from the main page, the banner says where you are")
        model.perform(.watchLastServer)
        #expect(opened == 1, "Only the main page watches a server")
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
