import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Settings › Channels: the editor, and saving through `AppModel`.
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
        #expect(model.genres == ["Comedy", "Drama"], "Sorted, with case-insensitive duplicates merged")
        #expect(model.seriesNames == ["Taskmaster"])
        #expect(model.tags == ["British", "Christmas"])
        #expect(model.years == 1950...2020)
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

    @Test func setTimesAreAddedCheckedAndRemoved() throws {
        let model = try editor()
        #expect(model.addDraft() == "Choose a series or film to set at a time.")
        model.draftProgramme = .series("Taskmaster")
        model.draftTimes = "18:00, 25:00"
        #expect(model.addDraft() == "Enter times like 18:00, or several like 18:00, 18:30.")
        model.draftTimes = "18:00, 18:30"
        model.draftWeekdays = [2, 3]
        #expect(model.addDraft() == nil)
        #expect(model.fixed == [FixedProgramme(match: .series("Taskmaster"), times: [1080, 1110], weekdays: [2, 3])])
        #expect(model.draftProgramme == nil && model.draftTimes.isEmpty, "The form clears for the next one")
        #expect(model.fixed[0].summary.hasPrefix("18:00, 18:30 · "))

        model.draftProgramme = .item("New Film")
        model.draftTimes = "18:30"
        #expect(model.addDraft() == "Something else is already set at 18:30.")
        model.draftWeekdays = [7]
        #expect(model.addDraft() == nil, "Another day may share the time")

        model.name = "Tasks"
        #expect(model.channel?.fixed.count == 2 && model.problem == nil)
        model.removeFixed(model.fixed[0])
        #expect(model.fixed.count == 1)
    }

    @Test func editingStartsFromTheChannel() throws {
        let channel = CustomChannel(number: 42, name: "Tasks", kinds: [.episode], rule: .series("Taskmaster"), commercials: false)
        let model = try editor(editing: channel)
        #expect(model.channel == channel)
        #expect(model.content == .episodes && model.ruleKind == .series && !model.commercials)
    }

    // MARK: Saving

    private func app() -> AppModel {
        AppModel(store: InMemoryCredentialStore(), preferences: Fixture.preferences(), makeDecks: FakeDeck.pair)
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
}
