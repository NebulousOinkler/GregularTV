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
        model.perform(.hideInfoOrOpenGuide)
        #expect(!model.bannerIsShowing && !model.showingGuide)
        model.perform(.hideInfoOrOpenGuide)
        #expect(model.showingGuide)
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
