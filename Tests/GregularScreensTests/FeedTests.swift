import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Feeds (README, *Feeds*): reading one, what an update changes, and
/// following, updating and unfollowing one in the app.
@MainActor
struct FeedTests {
    static let link = URL(string: "https://feeds.example/dad.json")!

    /// A feed's file, with channels at `numbers` (Westerns first, then
    /// Mysteries, …) and set times on the first.
    static func file(title: String = "Dad's Network", numbers: [Int] = [52, 53], timeZone: String = "local",
                     extra: String = "", setTimes: Bool = true) -> String {
        let names = ["Westerns", "Mysteries", "Comedy", "Cartoons"]
        let channels = numbers.enumerated().map { index, number in
            #"{ "number": \#(number), "name": "\#(names[index % names.count])", "plays": "both", "rule": { "anyOf": [{ "genre": "\#(names[index % names.count])" }] } }"#
        }
        let times = #", "setTimes": [{ "channel": \#(numbers[0]), "programmes": [{ "series": "Columbo", "at": ["20:00"], "days": ["Sun"] }] }]"#
        return #"{ "gregularFeed": 1, "title": "\#(title)", "publisher": "Dad", "description": "Westerns all week.", "#
            + #""timeZone": "\#(timeZone)"\#(extra), "channels": [\#(channels.joined(separator: ", "))]\#(setTimes ? times : "") }"#
    }

    private func read(_ text: String) throws -> FeedDocument {
        try FeedDocument.read(Data(text.utf8))
    }

    private func problem(_ text: String) -> String? {
        do {
            _ = try read(text)
            return nil
        } catch {
            return "\(error)"
        }
    }

    // MARK: The file

    @Test func aFeedTakesTheFollowersNumbersKeepingItsLastDigits() throws {
        let feed = try read(Self.file())
        #expect(feed.title == "Dad's Network" && feed.publishedBlock == 50)
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let (channels, setTimes) = try feed.resolved(into: 70, localZone: tokyo)
        #expect(channels.map(\.number) == [72, 73])
        #expect(channels.map(\.name) == ["Westerns", "Mysteries"])
        #expect(setTimes.map(\.channelNumber) == [72])
        #expect(setTimes.first?.timeZone == tokyo, "\"local\" is the follower's own time")
    }

    @Test func aNamedTimeZoneIsTheSameForEveryone() throws {
        let feed = try read(Self.file(timeZone: "America/New_York"))
        let (_, setTimes) = try feed.resolved(into: 70, localZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(setTimes.first?.timeZone.identifier == "America/New_York")
    }

    @Test func aFileThatIsntAFeedOrIsTooNewIsRefused() {
        #expect(problem(#"{ "channels": [] }"#) == FeedText.notAFeed)
        #expect(problem("<rss></rss>") == FeedText.notAFeed)
        #expect(problem(Self.file().replacingOccurrences(of: #""gregularFeed": 1"#, with: #""gregularFeed": 2"#)) == FeedText.newerVersion)
        #expect(problem(Self.file().replacingOccurrences(of: #""plays": "both""#, with: #""plays": 3"#))?.hasPrefix(FeedText.notAFeed) == true)
        let padded = Self.file(extra: #", "padding": "\#(String(repeating: "x", count: FeedDocument.largestFile))""#)
        #expect(problem(padded) == FeedText.tooLarge)
    }

    @Test func aFeedKeepsToItsLimits() {
        #expect(problem(Self.file(title: " ")) == FeedText.needsTitle)
        #expect(problem(Self.file(title: String(repeating: "a", count: 61))) == FeedText.titleTooLong)
        #expect(problem(Self.file().replacingOccurrences(of: "Westerns all week.", with: String(repeating: "a", count: 301)))
                == FeedText.descriptionTooLong)
        #expect(problem(Self.file(numbers: Array(50...59) + [50])) == FeedText.channelCount)
        #expect(problem(Self.file(numbers: [52, 63])) == FeedText.oneBlock, "One block of ten")
        #expect(problem(Self.file(numbers: [52, 52])) == FeedText.oneBlock, "Each number once")
        #expect(problem(Self.file(numbers: [12, 13])) == FeedText.oneBlock, "Only the custom channel numbers")
        #expect(problem(Self.file(timeZone: "Mars/Olympus")) == FeedText.badTimeZone("Mars/Olympus"))
        let elsewhere = Self.file(setTimes: false).replacingOccurrences(
            of: #" }"#, with: #", "setTimes": [{ "channel": 2, "programmes": [{ "series": "Columbo", "at": ["20:00"] }] }] }"#,
            options: .backwards, range: nil)
        #expect(problem(elsewhere) == FeedText.setTimesOnItsChannels, "Never on a channel that isn't the feed's")
        let clash = Self.file().replacingOccurrences(
            of: #"[{ "series": "Columbo", "at": ["20:00"], "days": ["Sun"] }]"#,
            with: #"[{ "series": "Columbo", "at": ["20:00"] }, { "series": "Monk", "at": ["20:00"] }]"#)
        #expect(problem(clash) != nil, "Checked as any set times are")
        #expect(problem(Self.file(numbers: Array(50...59))) == nil)
    }

    /// A PNG's first 24 bytes, `width` by `height`, padded to `size`.
    static func png(width: Int, height: Int, size: Int = 100) -> String {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8)
        for side in [width, height] { bytes += [UInt8(side >> 24 & 0xFF), UInt8(side >> 16 & 0xFF), UInt8(side >> 8 & 0xFF), UInt8(side & 0xFF)] }
        bytes += [UInt8](repeating: 0, count: max(0, size - bytes.count))
        return Data(bytes).base64EncodedString()
    }

    @Test func aPictureIsASmallPNG() throws {
        let good = try read(Self.file(extra: #", "image": "\#(Self.png(width: 128, height: 128))""#))
        #expect(good.imageData?.count == 100)
        for image in [Self.png(width: 257, height: 10), Self.png(width: 0, height: 10),
                      Self.png(width: 64, height: 64, size: FeedDocument.largestImage + 1),
                      Data("GIF89a not a png at all, really".utf8).base64EncodedString(), "not base64!"] {
            #expect(problem(Self.file(extra: #", "image": "\#(image)""#)) == FeedText.badImage)
        }
    }

    @Test func sharingMakesAFeedOfOneBlock() throws {
        let zone = TimeZone(identifier: "America/Chicago")!
        let channels = [CustomChannel(number: 25, name: "Mine"), CustomChannel(number: 52, name: "Westerns", rule: .genre("Western")),
                        CustomChannel(number: 58, name: "Mysteries", rule: .genre("Mystery"))]
        let setTimes = [SetTimes(channelNumber: 52, programmes: [FixedProgramme(match: .series("Columbo"), times: [1200])], timeZone: zone),
                        SetTimes(channelNumber: 2, programmes: [FixedProgramme(match: .series("Monk"), times: [1200])], timeZone: zone)]
        let details = FeedDocument.Details(block: 50, title: " Dad's Network ", publisher: "", description: "Westerns.",
                                           timeZone: "America/Chicago", image: nil)
        let feed = try FeedDocument.make(details, channels: channels, setTimes: setTimes)
        #expect(feed.channels.map(\.number) == [52, 58])
        #expect(feed.setTimes?.map(\.channel) == [52], "Only set times on the shared channels")
        #expect(feed.title == "Dad's Network" && feed.publisher == nil)
        #expect(try read(feed.json) == feed, "What it writes, a follower reads")
        #expect(throws: FeedDocument.Problem(description: FeedText.nothingToShare(30))) {
            try FeedDocument.make(FeedDocument.Details(block: 30, title: "Empty", timeZone: "local"), channels: channels, setTimes: [])
        }
    }

    // MARK: What's new

    @Test func anUpdateSaysWhatItChanges() throws {
        let old = try read(Self.file(numbers: [52, 53, 54]))
        var new = old
        new.channels[0].name = "Cowboys"
        new.channels[1].rule.anyOf = [.init(genre: "Crime")]
        new.channels.remove(at: 2)
        new.channels.append(try read(Self.file(numbers: [56])).channels[0])
        new.setTimes = nil
        #expect(FeedChanges.lines(from: old, to: new) == [
            FeedText.renamed("Westerns", "Cowboys"), FeedText.goneSetTimes("Cowboys"),
            FeedText.changedChannel("Mysteries"), FeedText.goneChannel("Comedy"), FeedText.newChannel("Westerns"),
        ])
        new = old
        new.description = "Something else"
        #expect(FeedChanges.lines(from: old, to: new) == [FeedText.newDetails])
        #expect(FeedChanges.lines(from: old, to: old).isEmpty)
    }

    @Test func aFeedsBadgeIsItsInitialsOnAColour() {
        let badge = Feed.Badge("Dad's Network")
        #expect(badge.initials == "DN")
        #expect(badge == Feed.Badge("Dad's Network"), "The same everywhere")
        #expect((0..<360).contains(badge.hue))
        #expect(Feed.Badge("  ").initials.isEmpty)
    }

    // MARK: In the app

    /// A host serving feed files: what's at each link, and what was asked.
    final class Host: HTTPTransport, @unchecked Sendable {
        var files: [URL: String] = [:]
        var down = false
        private(set) var asked: [URL] = []

        func send(_ request: ServerRequest) async throws -> ServerReply {
            asked.append(request.url)
            if down { throw URLError(.notConnectedToInternet) }
            guard let file = files[request.url] else { return ServerReply(url: request.url, status: 404, body: Data()) }
            return ServerReply(url: request.url, status: 200, body: Data(file.utf8))
        }
    }

    /// Checking again only when `every` is given: a sleep left waiting
    /// keeps WasmKit's run from ending (`AppModel.checksFeedsEvery`).
    private func app(_ host: Host, preferences: AppPreferences = .testing(), checkingEvery every: Duration? = nil) -> AppModel {
        preferences.scheduleCode = .standard
        return AppModel(deviceName: "Test Device", formats: .appleTV, transport: host, store: InMemoryCredentialStore(),
                        preferences: preferences, makeDecks: FakeDeck.pair, checksFeedsEvery: every)
    }

    private func follow(_ app: AppModel, at firstNumber: Int = 70, link: URL = link) -> String? {
        var document = app.userChannels
        document.feeds = (document.feeds ?? []) + [EditingDocument.FeedEntry(link: link.absoluteString, firstNumber: firstNumber)]
        return app.replaceUserChannels(with: document)
    }

    @Test func followingAFeedJustLookedAtTakesItAtOnce() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        let look = try await app.lookAtFeed("feeds.example/dad.json").get()
        #expect(look.link == Self.link, "https when the link says nothing")
        #expect(look.feed.title == "Dad's Network")
        #expect(app.freeFeedBlocks == Array(stride(from: 20, through: 90, by: 10)))
        #expect(follow(app) == nil)
        #expect(host.asked.count == 1, "Not fetched again")
        #expect(app.feedLineup.channels.map(\.number) == [72, 73])
        #expect(app.feeds.first?.status == FeedText.upToDate)
        #expect(app.feed(owning: 75)?.title == "Dad's Network")
        #expect(!app.lineupChannels.contains { $0.number == 72 }, "Your set times can't go on a feed's channel")
        #expect(!app.freeFeedBlocks.contains(70))
        #expect(app.userChannels.feeds == [EditingDocument.FeedEntry(link: Self.link.absoluteString, firstNumber: 70)])
        if case .failure(let problem) = await app.lookAtFeed(Self.link.absoluteString) {
            #expect(problem.description == FeedText.alreadyFollowing)
        } else {
            Issue.record("Already followed")
        }
    }

    @Test func onlyTheLastFewFeedsLookedAtAreKept() async throws {
        let host = Host()
        let links = (1...AppModel.mostFeedsLookedAt + 2).map { URL(string: "https://feeds.example/\($0).json")! }
        for link in links { host.files[link] = Self.file() }
        let app = app(host)
        for link in links { _ = await app.lookAtFeed(link.absoluteString) }
        #expect(app.lookedAtFeeds.map(\.link) == Array(links.suffix(AppModel.mostFeedsLookedAt)))
        #expect(follow(app, link: links[0]) == nil)
        #expect(app.feeds.first?.accepted == nil, "Forgotten, so fetched again")
    }

    @Test func aFeedsNumbersAreItsAlone() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)
        var document = app.userChannels
        document.channels = [EditingDocument.ChannelEntry(CustomChannel(number: 79, name: "Mine"))]
        #expect(app.replaceUserChannels(with: document) == FeedText.inFeedBlock(79, feed: "Dad's Network"))
        document.channels = []
        document.setTimes = [EditingDocument.SetTimesEntry(SetTimes(channelNumber: 72, programmes: [FixedProgramme(match: .series("Monk"), times: [600])]))]
        #expect(app.replaceUserChannels(with: document)?.contains("72") == true, "Set times on a feed's channel are refused")
        #expect(follow(app, at: 70, link: URL(string: "https://feeds.example/other.json")!) == FeedText.blockTaken(70))
        #expect(follow(app, at: 75, link: URL(string: "https://feeds.example/other.json")!) == FeedText.badBlock)
        #expect(follow(app, at: 30, link: URL(string: "http://feeds.example/other.json")!) == FeedText.badLink)
    }

    @Test func aPastedFeedIsFetchedThenUpdatesWaitForATap() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let preferences = AppPreferences.testing()
        let app = app(host, preferences: preferences)
        #expect(follow(app) == nil)
        try await waitUntil(2) { !app.feedLineup.channels.isEmpty }
        #expect(app.feedLineup.channels.map(\.number) == [72, 73], "The first version is taken without asking")

        host.files[Self.link] = Self.file(numbers: [52, 53, 54])
        await app.checkFeeds()
        #expect(app.hasFeedUpdates)
        #expect(app.feeds.first?.status == FeedText.updateWaiting)
        #expect(app.feeds.first?.whatsNew == [FeedText.newChannel("Comedy")])
        #expect(app.feedLineup.channels.count == 2, "Nothing changes until the viewer gets it")
        #expect(self.app(host, preferences: preferences).feedLineup.channels.count == 2, "Nor after a relaunch")

        #expect(app.getUpdate(Self.link) == nil)
        #expect(app.feedLineup.channels.map(\.number) == [72, 73, 74])
        #expect(!app.hasFeedUpdates)
        #expect(self.app(host, preferences: preferences).feedLineup.channels.count == 3, "Kept")

        await app.checkFeeds()
        #expect(!app.hasFeedUpdates, "The same again isn't an update")
    }

    @Test func feedsAreCheckedAtLaunchThenAgainWhileTheAppRuns() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host, checkingEvery: .milliseconds(100))
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)
        await app.launch()
        try await waitUntil(5) { host.asked.count >= 2 }
        #expect(host.asked.count >= 2, "Checked at launch")
        #expect(!app.hasFeedUpdates)

        host.files[Self.link] = Self.file(numbers: [52, 53, 54])
        try await waitUntil(5) { app.hasFeedUpdates }
        #expect(app.hasFeedUpdates, "Checked again, without a relaunch")
        app.feedChecks?.cancel()
    }

    @Test func aLinkThatStopsWorkingKeepsWhatItHad() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)

        host.down = true
        await app.checkFeeds()
        #expect(app.feeds.first?.status.hasPrefix("Couldn't check it. Last reached") == true)
        #expect(app.feeds.first?.saved.expired == false)

        host.down = false
        host.files[Self.link] = nil
        await app.checkFeeds()
        #expect(app.feeds.first?.status.hasPrefix("Link expired. Last reached") == true)
        #expect(app.feedLineup.channels.count == 2, "The version accepted keeps playing")

        host.files[Self.link] = "not a feed"
        await app.checkFeeds()
        #expect(app.feeds.first?.saved.expired == true, "Something that isn't a feed counts as expired too")

        host.files[Self.link] = Self.file()
        await app.checkFeeds()
        #expect(app.feeds.first?.status == FeedText.upToDate)
    }

    @Test func unfollowingTakesAwayItsChannels() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)
        app.unfollow(Self.link)
        #expect(app.feeds.isEmpty && app.feedLineup.channels.isEmpty)
        #expect(app.freeFeedBlocks.contains(70))
    }

    @Test func aDocumentWithoutFeedsLeavesThemAlone() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)
        var document = app.userChannels
        document.feeds = nil
        #expect(app.replaceUserChannels(with: document) == nil)
        #expect(app.feeds.count == 1, "An older document says nothing about feeds")
        document.feeds = []
        #expect(app.replaceUserChannels(with: document) == nil)
        #expect(app.feeds.isEmpty, "An empty list unfollows them")
    }

    // MARK: On the editing page

    private func ask(_ api: EditingAPI, _ path: String, _ body: String) async -> (status: Int, json: [String: Any]) {
        let response = await api.answer("POST", path, Data(body.utf8))
        return (response.status, (try? JSONSerialization.jsonObject(with: response.body)) as? [String: Any] ?? [:])
    }

    @Test func thePageLooksAtAFeedThenListsItOnceFollowed() async throws {
        let host = Host()
        host.files[Self.link] = Self.file(extra: #", "image": "\#(Self.png(width: 64, height: 64))""#)
        let app = app(host)
        let api = EditingAPI(app: app)
        let look = await ask(api, "/api/feeds/look", #"{ "link": "https://feeds.example/dad.json" }"#)
        #expect(look.status == 200)
        #expect(look.json["title"] as? String == "Dad's Network")
        #expect((look.json["channels"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == ["Westerns", "Mysteries"])
        #expect((look.json["details"] as? [String: Any])?["times"] as? String == FeedText.localTimes)
        #expect((look.json["details"] as? [String: Any])?["image"] as? String != nil)
        #expect(look.json["freeBlocks"] as? [Int] == Array(stride(from: 20, through: 90, by: 10)))

        let missing = await ask(api, "/api/feeds/look", #"{ "link": "https://feeds.example/nothing.json" }"#)
        #expect(missing.status == 422 && missing.json["error"] as? String == FeedText.gone)

        #expect(follow(app) == nil)
        let state = await api.answer("GET", "/api/state", Data())
        let json = try #require(try JSONSerialization.jsonObject(with: state.body) as? [String: Any])
        let feeds = try #require(json["feeds"] as? [[String: Any]])
        #expect(feeds.first?["status"] as? String == FeedText.upToDate)
        let lines = try #require(feeds.first?["channels"] as? [[String: Any]])
        #expect(lines.compactMap { $0["number"] as? Int } == [72, 73])
        #expect((lines.first?["setTimes"] as? [String: Any])?["channel"] as? Int == 72, "What Make a Copy copies")
        #expect(!(json["freeFeedBlocks"] as? [Int] ?? []).contains(70))
    }

    @Test func thePageGetsAnUpdate() async throws {
        let host = Host()
        host.files[Self.link] = Self.file()
        let app = app(host)
        let api = EditingAPI(app: app)
        _ = await app.lookAtFeed(Self.link.absoluteString)
        #expect(follow(app) == nil)
        host.files[Self.link] = Self.file(numbers: [52, 53, 54])
        await app.checkFeeds()
        #expect(api.changes(EditingAPI.updatePath))
        let update = await ask(api, EditingAPI.updatePath, #"{ "link": "https://feeds.example/dad.json" }"#)
        #expect(update.status == 200)
        #expect(app.feedLineup.channels.count == 3)
    }

    @Test func thePageSharesABlockOfYourChannelsAsAFile() async throws {
        let app = app(Host())
        #expect(app.replaceUserChannels(with: EditingDocument(channels: [CustomChannel(number: 41, name: "Westerns", rule: .genre("Western"))],
                                                              setTimes: [])) == nil)
        let api = EditingAPI(app: app)
        let shared = await ask(api, "/api/feeds/share", #"{ "block": 40, "title": "Dad's Network", "timeZone": "local" }"#)
        #expect(shared.status == 200)
        #expect(shared.json["fileName"] as? String == "dads-network.json")
        let feed = try FeedDocument.read(Data(try #require(shared.json["file"] as? String).utf8))
        #expect(feed.channels.map(\.name) == ["Westerns"])
        let empty = await ask(api, "/api/feeds/share", #"{ "block": 50, "title": "Nothing", "timeZone": "local" }"#)
        #expect(empty.status == 422 && empty.json["error"] as? String == FeedText.nothingToShare(50))
    }
}
