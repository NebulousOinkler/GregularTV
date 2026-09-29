import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Settings › Your channels and Set times: the editors, and saving through `AppModel`.
@MainActor
struct ChannelEditorTests {
    static let library: [MediaItem] = [
        MediaItem(id: "e1", kind: .episode, name: "Pilot", duration: 1320, seriesID: "s1", seriesName: "Taskmaster",
                  seasonNumber: 1, episodeNumber: 1, productionYear: 2015, genres: ["Comedy"], tags: ["British"]),
        MediaItem(id: "e2", kind: .episode, name: "Two", duration: 1320, seriesID: "s1", seriesName: "Taskmaster",
                  seasonNumber: 1, episodeNumber: 2, productionYear: 2015, genres: ["comedy"]),
        MediaItem(id: "m1", kind: .movie, name: "Old Film", duration: 5400, productionYear: 1950, genres: ["Drama"]),
        MediaItem(id: "m2", kind: .movie, name: "New Film", duration: 6000, productionYear: 2020, genres: ["Comedy"], tags: ["Christmas"]),
    ]

    private func editor(editing channel: CustomChannel? = nil, lineup: ChannelLineup? = nil) throws -> ChannelEditorModel {
        ChannelEditorModel(editing: channel, library: Self.library, lineup: try lineup ?? ChannelLineup.bundled(),
                           code: ScheduleCode("7KQM2-X9PDA")!)
    }

    @Test func theChoicesComeFromTheLibrary() throws {
        let model = try editor()
        #expect(model.choices.genres == ["Comedy", "Drama"], "Sorted, with case-insensitive duplicates merged")
        #expect(model.choices.seriesNames == ["Taskmaster"])
        #expect(model.choices.tags == ["British", "Christmas"])
        #expect(model.choices.movieNames == ["New Film", "Old Film"])
        #expect(model.choices.years == 1950...2020)
    }

    @Test func aNewChannelTakesTheFirstFreeNumber() throws {
        let taken = try ChannelLineup.bundled().adding([CustomChannel(number: 20, name: "A")])
        let model = try editor(lineup: taken)
        #expect(model.number == 21)
        model.stepNumber(by: -1)
        #expect(model.number == 99, "Wraps round the free numbers")
        #expect(!model.freeNumbers.contains(20))
    }

    @Test func itSaysWhatsMissingThenPreviewsTheChannel() throws {
        let model = try editor()
        model.ruleKind = .genre
        #expect(model.problem == "Choose a genre for the channel.")
        model.genre = "Comedy"
        #expect(model.problem == "Give the channel a name.")
        model.name = "  Laughs "
        #expect(model.problem == nil)
        #expect(model.channel?.name == "Laughs")
        #expect(model.matchingCount == 3, "Both episodes and the new film")
        model.content = .movies
        #expect(model.matchingCount == 1)
        #expect(!model.upcoming(from: Date(timeIntervalSince1970: 1_790_000_000)).isEmpty)
        #expect(model.upcoming().allSatisfy { $0.title == "New Film" })
    }

    @Test func aRuleMatchingNothingCantBeSaved() throws {
        let model = try editor()
        model.name = "Old Comedies"
        model.ruleKind = .years
        model.toYear = 1900
        #expect(model.problem == "Nothing in your library matches yet.")
    }

    @Test func editingStartsFromTheChannel() throws {
        let channel = CustomChannel(number: 42, name: "Tasks", kinds: [.episode], rule: .series("Taskmaster"), commercials: false)
        let model = try editor(editing: channel)
        #expect(model.channel == channel)
        #expect(model.content == .episodes && model.ruleKind == .series && !model.commercials)
    }

    // MARK: Saving

    private func app() -> AppModel {
        AppModel(deviceName: "Test Device", store: InMemoryCredentialStore(), preferences: Fixture.preferences(), makeDecks: FakeDeck.pair)
    }

    @Test func theAppNamesItsDevice() {
        #expect(app().identity.deviceName == "Test Device")
        #expect(app().signOutConfirmation.detail.hasSuffix("stay on this Test Device."))
    }

    @Test func everythingThatCantBeUndoneAsksFirst() throws {
        #expect(app().signOutConfirmation.action == "Sign Out")
        let editor = try self.editor(editing: CustomChannel(number: 30, name: "Mine"))
        editor.stepNumber(by: 1)
        #expect(editor.deleteConfirmation.question == "Delete channel 30?", "The channel being deleted, not its new number")
        #expect(try setTimesEditor().deleteConfirmation.question == "Delete the set times on channel 2?")
    }

    @Test func savedChannelsAreKeptAndNumbersChecked() {
        let app = app()
        let channel = CustomChannel(number: 30, name: "Comedy", rule: .genre("Comedy"))
        #expect(app.save(channel) == nil)
        #expect(app.customChannels == [channel])
        #expect(app.save(CustomChannel(number: 30, name: "Again")) == "Channel 30 is already taken.")
        #expect(app.save(CustomChannel(number: 3, name: "Low")) == "Custom channels are numbered 20 to 99.")
        let renamed = CustomChannel(number: 31, name: "Laughs", rule: .genre("Comedy"))
        #expect(app.save(renamed, replacing: channel) == nil)
        #expect(app.customChannels == [renamed])
        app.delete(renamed)
        #expect(app.customChannels.isEmpty)
    }

    @Test func aChannelCodeAddsTheChannel() {
        let app = app()
        let shared = CustomChannel(number: 44, name: "Shared", rule: .tag("Christmas"))
        #expect(app.addChannel(code: shared.code) == nil)
        #expect(app.customChannels == [shared])
        #expect(app.addChannel(code: "NOT-A-CODE") != nil)
    }

    // MARK: Set times

    static let newYork = TimeZone(identifier: "America/New_York")!

    private func setTimesEditor(editing original: SetTimes? = nil) throws -> SetTimesEditorModel {
        let lineup = try ChannelLineup.bundled()
        return SetTimesEditorModel(channel: try #require(lineup.channels.first { $0.number == 2 }), editing: original,
                                   library: Self.library, lineup: lineup, code: ScheduleCode("7KQM2-X9PDA")!,
                                   timeZone: Self.newYork)
    }

    @Test func setTimesAreAddedCheckedAndRemoved() throws {
        let model = try setTimesEditor()
        #expect(model.channelName == "Comedy")
        #expect(model.problem == "Add a set time first.")
        #expect(model.addDraft() == "Choose a series or film to set at a time.")
        model.draftProgramme = .series("Taskmaster")
        model.draftTimes = "18:00, 25:00"
        #expect(model.addDraft() == "Enter times like \(SetTimesEditorModel.example(1)), or several like \(SetTimesEditorModel.example(2)).")
        model.draftTimes = "18:00, 18:30"
        model.draftWeekdays = [2, 3]
        #expect(model.addDraft() == nil)
        #expect(model.programmes == [FixedProgramme(match: .series("Taskmaster"), times: [1080, 1110], weekdays: [2, 3],
                                                    timeZone: Self.newYork)])
        #expect(model.draftProgramme == nil && model.draftTimes.isEmpty, "The form clears for the next one")
        #expect(model.programmes[0].summary.hasPrefix("\(SetTimesEditorModel.example(2)) · "))

        model.draftProgramme = .item("New Film")
        model.draftTimes = "18:30"
        #expect(model.addDraft() == "Something else is already set at \(FixedProgramme.clockText(forMinutes: 1110)).")
        model.draftWeekdays = [7]
        #expect(model.addDraft() == nil, "Another day may share the time")
        #expect(model.problem == nil)
        #expect(model.setTimes.channelNumber == 2 && model.setTimes.programmes.count == 2)
        #expect(!model.upcoming(from: Date(timeIntervalSince1970: 1_790_000_000), days: 7).isEmpty)

        model.remove(model.programmes[0])
        #expect(model.programmes.count == 1)
    }

    @Test func setTimesAreTypedInEitherClock() {
        let us = Locale(identifier: "en_US"), uk = Locale(identifier: "en_GB")
        #expect(FixedProgramme.typedTimes("18:00, 18:30", locale: us) == [1080, 1110])
        #expect(FixedProgramme.typedTimes("18:00 18:30", locale: us) == [1080, 1110])
        #expect(FixedProgramme.typedTimes("6:00 PM, 6:30 PM", locale: us) == [1080, 1110])
        #expect(FixedProgramme.typedTimes("6pm 6:30pm", locale: us) == [1080, 1110])
        #expect(FixedProgramme.typedTimes("6 p.m., 12 am, 12:15 PM", locale: us) == [1080, 0, 735])
        #expect(FixedProgramme.typedTimes(FixedProgramme.clockText(forMinutes: 1110, locale: us), locale: us) == [1110],
                "What the screen shows reads back")
        #expect(FixedProgramme.clockText(forMinutes: 1110, locale: uk) == "18:30")
        for bad in ["", "6", "13 pm", "25:00", "6:3 pm", "pm", "6:00 PM, later", "0 am"] {
            #expect(FixedProgramme.typedTimes(bad, locale: us) == nil, "\(bad)")
        }
    }

    @Test func aSetTimesRowSaysWhatWontAir() {
        let times = SetTimes(channelNumber: 6, programmes: [FixedProgramme(match: .series("Far Signal"), times: [720]),
                                                            FixedProgramme(match: .series("Orbit & Pip"), times: [1080])])
        let row = AppModel.SetTimesChannel(number: 6, title: "6  Kids", setTimes: times, missing: ["Orbit & Pip"])
        #expect(row.detail == "Far Signal, Orbit & Pip · Not in your library: Orbit & Pip")
    }

    @Test func setTimesKnowWhetherTheyreInThisTimeZone() throws {
        #expect(try setTimesEditor().isInLocalTimeZone == (Self.newYork == .current))
        let away = TimeZone(identifier: TimeZone.current.identifier == "Asia/Tokyo" ? "Europe/London" : "Asia/Tokyo")!
        let shared = SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .series("Taskmaster"), times: [60])], timeZone: away)
        #expect(try setTimesEditor(editing: shared).isInLocalTimeZone == false)
    }

    @Test func renumberingAChannelMovesItsSetTimes() {
        let app = app()
        let custom = CustomChannel(number: 30, name: "Mine")
        #expect(app.save(custom) == nil)
        let setTimes = SetTimes(channelNumber: 30, programmes: [FixedProgramme(match: .series("Taskmaster"), times: [1080])],
                                timeZone: Self.newYork)
        #expect(app.save(setTimes) == nil)
        let renumbered = CustomChannel(number: 31, name: "Mine")
        #expect(app.save(renumbered, replacing: custom) == nil)
        #expect(app.setTimes.map(\.channelNumber) == [31])
        #expect(app.setTimes.first?.programmes == setTimes.programmes)
    }

    @Test func theEditorStopsAtTheMostTimes() throws {
        let model = try setTimesEditor()
        model.draftProgramme = .series("Taskmaster")
        model.draftTimes = (0..<FixedProgramme.mostTimesPerChannel).map { FixedProgramme.text(forMinutes: $0 * 15) }.joined(separator: ", ")
        #expect(model.addDraft() == nil)
        model.draftProgramme = .item("Old Film")
        model.draftTimes = "23:45"
        #expect(model.addDraft() == "A channel's set times can list at most \(FixedProgramme.mostTimesPerChannel) times in all.")
    }

    @Test func setTimesSayWhatIsntInTheLibrary() throws {
        let model = try setTimesEditor()
        model.draftProgramme = .series("Not Here")
        model.draftTimes = "18:00"
        #expect(model.addDraft() == nil)
        model.draftProgramme = .series("Taskmaster")
        model.draftTimes = "19:00"
        #expect(model.addDraft() == nil)
        #expect(model.programmes.map(model.isMissing) == [true, false])
        #expect(SetTimes(channelNumber: 2, programmes: model.programmes + [FixedProgramme(match: .series("Taskmaster"), times: [1200])]).summary
                == "Not Here, Taskmaster", "Each name once")
    }

    @Test func savedSetTimesAreKeptCheckedAndShared() throws {
        let app = app()
        let setTimes = SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .series("Taskmaster"), times: [1080])],
                                timeZone: Self.newYork)
        #expect(app.save(setTimes) == nil)
        #expect(app.setTimes == [setTimes])
        #expect(app.save(SetTimes(channelNumber: 77, programmes: setTimes.programmes)) == "There's no channel 77 for these set times.")
        // A code from another device replaces this channel's set times.
        let shared = SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .item("New Film"), times: [1200])],
                              timeZone: Self.newYork)
        #expect(app.addSetTimes(code: shared.code) == nil)
        #expect(app.setTimes == [shared])
        #expect(app.addSetTimes(code: "NOPE") != nil)
        // Deleting a custom channel deletes the set times on it.
        let custom = CustomChannel(number: 30, name: "Mine")
        #expect(app.save(custom) == nil)
        let onCustom = SetTimes(channelNumber: 30, programmes: shared.programmes, timeZone: Self.newYork)
        #expect(app.save(onCustom) == nil)
        // Settings lists every channel, custom ones too, with its set times.
        let channels = app.setTimesChannels
        #expect(channels.first { $0.number == 30 }.map { $0.title == "30  Mine" && $0.setTimes == onCustom } == true)
        #expect(channels.first { $0.number == 2 }?.setTimes == shared)
        #expect(channels.filter { $0.setTimes != nil }.count == 2)
        #expect(channels.allSatisfy { $0.missing.isEmpty }, "Before the library loads, nothing is flagged")
        #expect(channels.first { $0.number == 30 }?.detail == "New Film")
        #expect(channels.first { $0.number == 3 }?.detail == nil, "No set times, no detail")
        app.delete(custom)
        #expect(app.setTimes == [shared])
        app.delete(shared)
        #expect(app.setTimes.isEmpty)
    }
}
