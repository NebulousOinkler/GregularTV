import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Special modes: opened by a keyword in Settings' schedule code field, in
/// place of live TV, and left for live TV again.
@MainActor
struct SpecialModeTests {
    static let modes = try! SpecialModeRegistry.load(from: Data("""
    { "modes": [
        { "id": "everything", "keywordHashes": ["\(hash("ABRACADABRA"))"] },
        { "id": "own-library", "keywordHashes": ["\(hash("SING ALONG"))"], "library": "Songs" },
        { "id": "missing-library", "keywordHashes": ["\(hash("NOWHERE"))"], "library": "Nowhere" }
    ] }
    """.utf8))

    private static func hash(_ keyword: String) -> String {
        try! SpecialModeRegistry.keywordHash(for: keyword)
    }

    /// Watching a server with three films, and a library of two songs.
    private func watching(_ modes: SpecialModeRegistry = modes) async throws -> AppModel {
        let store = InMemoryCredentialStore(credentials: MainPageTests.home)
        let app = Fixture.app(store: store, transport: FakeServer(), specialModes: modes)
        await app.launch()
        await app.watch(try #require(app.servers.first))
        try #require(app.phase.isWatching, "Should be watching: \(app.phase)")
        return app
    }

    private func session(of app: AppModel) throws -> SpecialModeSession {
        try #require(app.phase.specialMode, "Should be in a special mode: \(app.phase)")
    }

    @Test func aScheduleCodeIsStillACode() async throws {
        let app = try await watching()
        #expect(await app.enterCode("7kqm2 x9pda") == nil)
        #expect(app.scheduleCode == ScheduleCode("7KQM2-X9PDA"))
        #expect(await app.enterCode("abracadabra please") == SettingsText.badCode)
        #expect(app.phase.isWatching)
    }

    @Test func aKeywordOpensItsModeInPlaceOfLiveTV() async throws {
        let app = try await watching()
        let surfer = try #require(app.liveTV)
        #expect(await app.enterCode("Abra-Cadabra") == nil)
        let session = try session(of: app)
        #expect(session.mode.id == "everything")
        #expect(session.programmes.map(\.id) == FakeServer.films.map(\.id), "The whole library")
        #expect(app.liveTV == nil && surfer.player.status == .tuning, "Live TV stops")
    }

    @Test func aModeCanPlayFromItsOwnLibrary() async throws {
        let app = try await watching()
        #expect(await app.enterCode("sing along") == nil)
        #expect(try session(of: app).programmes.map(\.id) == FakeServer.songs.map(\.id))
    }

    @Test func aModeWithNothingOnTheServerStaysShut() async throws {
        let app = try await watching()
        #expect(await app.enterCode("nowhere") == SettingsText.specialModeUnavailable)
        #expect(app.phase.isWatching)

        app.showMainPage()
        #expect(await app.enterCode("abracadabra") == SettingsText.specialModeUnavailable, "Only from live TV")
    }

    @Test func leavingAModeGoesBackToLiveTV() async throws {
        let app = try await watching()
        let channel = try #require(app.liveTV).player.schedule.channel.number
        #expect(await app.enterCode("abracadabra") == nil)
        let session = try session(of: app)
        session.exit()
        #expect(app.liveTV?.player.schedule.channel.number == channel, "On the channel watched last")

        #expect(await app.enterCode("sing along") == nil)
        let songs = try self.session(of: app)
        session.exit()
        #expect(try self.session(of: app) === songs, "A mode already left can't close another")
    }

    /// A front end accepts only the keywords of the modes it has screens for.
    @Test func onlyTheFrontEndsModesOpen() async throws {
        let screens = SpecialModeScreens<String>(["own-library": { "\($0.programmes.count) songs" }], bundled: Self.modes)
        let app = try await watching(screens.registry)
        #expect(await app.enterCode("abracadabra") == SettingsText.badCode, "No screen for it: not a keyword here")
        #expect(await app.enterCode("sing along") == nil)
        #expect(screens.screen(for: try session(of: app)) == "2 songs")
    }
}

private extension AppModel.Phase {
    var isWatching: Bool { if case .watching = self { true } else { false } }
    var specialMode: SpecialModeSession? { if case .special(let session) = self { session } else { nil } }
}

/// A server with three films, and a library called Songs with two videos.
/// Everything else it's asked (streams, other libraries) isn't found.
struct FakeServer: HTTPTransport {
    static let films = (1...3).map { (id: "m\($0)", name: "Film \($0)", type: "Movie") }
    static let songs = (1...2).map { (id: "s\($0)", name: "Song \($0)", type: "Video") }

    func send(_ request: ServerRequest) async throws -> ServerReply {
        let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let body: String? = switch request.url.path {
        case "/UserViews": #"{ "Items": [ { "Id": "songs", "Name": "Songs", "Type": "CollectionFolder" } ], "TotalRecordCount": 1 }"#
        case "/Items" where value("ParentId") == "songs": Self.page(Self.songs)
        case "/Items" where value("ParentId") == nil && value("IncludeItemTypes") == "Episode,Movie": Self.page(Self.films)
        case "/Items" where value("ParentId") == nil: Self.page([])
        default: nil
        }
        return ServerReply(url: request.url, status: body == nil ? 404 : 200, body: Data((body ?? "").utf8))
    }

    private static func page(_ items: [(id: String, name: String, type: String)]) -> String {
        let listed = items.map { #"{ "Id": "\#($0.id)", "Name": "\#($0.name)", "Type": "\#($0.type)", "RunTimeTicks": 36000000000 }"# }
        return #"{ "Items": [\#(listed.joined(separator: ","))], "TotalRecordCount": \#(items.count) }"#
    }
}
