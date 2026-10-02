import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Your channels and set times in the app: listed in Settings, and replaced
/// as a whole from the editing page (`EditingPageTests` covers the page).
@MainActor
struct YourChannelsTests {
    static let newYork = TimeZone(identifier: "America/New_York")!

    private func app() -> AppModel { Fixture.app() }

    private func document(_ channels: [CustomChannel], _ setTimes: [SetTimes] = []) -> EditingDocument {
        EditingDocument(channels: channels, setTimes: setTimes)
    }

    @Test func theAppNamesItsDevice() {
        #expect(app().deviceName == "Test Device")
        let server = AppModel.Server(id: "s", address: "nas:8096", isLastWatched: true)
        #expect(app().signOutConfirmation(for: server).detail.hasSuffix("stay on this Test Device."))
        #expect(app().signOutConfirmation(for: server).action == "Sign Out")
    }

    @Test func channelsAreReplacedWholeAndChecked() {
        let app = app()
        let channel = CustomChannel(number: 30, name: "Comedy", rule: .genre("Comedy"))
        #expect(app.replaceUserChannels(with: document([channel])) == nil)
        #expect(app.customChannels == [channel])
        #expect(app.replaceUserChannels(with: document([channel, CustomChannel(number: 30, name: "Again")])) == "Channel 30 is already taken.")
        #expect(app.replaceUserChannels(with: document([CustomChannel(number: 3, name: "Low")])) == "Custom channels are numbered 20 to 99.")
        #expect(app.customChannels == [channel], "Nothing changes when it can't be saved")
        #expect(app.replaceUserChannels(with: document([])) == nil)
        #expect(app.customChannels.isEmpty)
    }

    @Test func setTimesNeedTheirChannel() {
        let app = app()
        let setTimes = SetTimes(channelNumber: 77, programmes: [FixedProgramme(match: .series("Taskmaster"), times: [1080])],
                                timeZone: Self.newYork)
        #expect(app.replaceUserChannels(with: document([], [setTimes])) == "There's no channel 77 for these set times.")
        let custom = CustomChannel(number: 77, name: "Mine")
        #expect(app.replaceUserChannels(with: document([custom], [setTimes])) == nil)
        #expect(app.setTimes == [setTimes])
    }

    @Test func settingsListsTheChannelsWithSetTimes() {
        let app = app()
        let custom = CustomChannel(number: 30, name: "Mine")
        let onCustom = SetTimes(channelNumber: 30, programmes: [FixedProgramme(match: .item("New Film"), times: [1200])], timeZone: Self.newYork)
        let onBundled = SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .series("Taskmaster"), times: [1080])], timeZone: Self.newYork)
        #expect(app.replaceUserChannels(with: document([custom], [onBundled, onCustom])) == nil)
        let rows = app.setTimesChannels
        #expect(rows.map(\.number) == [2, 30], "Only channels with set times, in order")
        #expect(rows.last.map { $0.title == "30  Mine" && $0.detail == "New Film" } == true)
        #expect(rows.allSatisfy { $0.missing.isEmpty }, "Before the library loads, nothing is flagged")
    }

    @Test func aSetTimesRowSaysWhatWontAir() {
        let times = SetTimes(channelNumber: 6, programmes: [FixedProgramme(match: .series("Far Signal"), times: [720]),
                                                            FixedProgramme(match: .series("Orbit & Pip"), times: [1080])])
        let row = AppModel.SetTimesChannel(number: 6, title: "6  Kids", setTimes: times, missing: ["Orbit & Pip"])
        #expect(row.detail == "Far Signal, Orbit & Pip · Not in your library: Orbit & Pip")
    }

    @Test func aChannelSaysWhatItPlays() {
        let channel = CustomChannel(number: 30, name: "M", kinds: [.movie], rule: CustomChannel.Rule([
            .init(.anyOf, .genre("Comedy")), .init(.anyOf, .series("Taskmaster")), .init(.noneOf, .tag("Christmas")),
        ]))
        #expect(channel.summary == "Comedy or Taskmaster, not Christmas · Movies")
        #expect(CustomChannel(number: 31, name: "E").summary == "Everything · Episodes and Movies")
    }

    @Test func timesShowInTheViewersClock() {
        #expect(FixedProgramme.clockText(forMinutes: 1110, locale: Locale(identifier: "en_GB")) == "18:30")
        #expect(FixedProgramme.clockText(forMinutes: 1110, locale: Locale(identifier: "en_US")).hasPrefix("6:30"))
    }
}
