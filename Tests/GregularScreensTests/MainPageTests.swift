import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// The main page: the servers signed in to, the app's first screen.
@MainActor
struct MainPageTests {
    static let home = Credentials(serverURL: URL(string: "http://192.168.1.5:8096")!, userID: "u", accessToken: "t1")
    static let away = Credentials(serverURL: URL(string: "https://tv.example/jellyfin")!, userID: "u", accessToken: "t2")

    private func app(_ signIns: [Credentials]) throws -> (AppModel, InMemoryCredentialStore) {
        let store = InMemoryCredentialStore()
        for credentials in signIns.reversed() { try store.saveCredentials(credentials) }
        return (Fixture.app(store: store), store)
    }

    @Test func theAppOpensOnTheMainPageOrSignInIfThereAreNoServers() async throws {
        let (empty, _) = try app([])
        await empty.launch()
        guard case .signedOut = empty.phase else { Issue.record("No servers: sign in first"); return }
        #expect(!empty.canCancelSignIn, "Nothing to go back to; Menu leaves the app")

        let (app, _) = try app([Self.away, Self.home])
        await app.launch()
        guard case .mainPage = app.phase else { Issue.record("Should open on the main page"); return }
        #expect(app.servers.map(\.address) == ["tv.example/jellyfin", "192.168.1.5:8096"], "The one watched last first; no scheme")
        #expect(app.servers.map(\.isLastWatched) == [true, false])
        #expect(app.servers.map(\.badge) == ["Watched last", nil], "Nothing's playing behind the page at launch")
        #expect(app.servers[0].title == "tv.example/jellyfin", "The address until the server gives its name")
    }

    @Test func addingAServerCanBeCancelled() async throws {
        let (app, _) = try app([Self.home])
        await app.launch()
        app.addServer()
        guard case .signedOut = app.phase else { Issue.record("Add a Server opens sign-in"); return }
        #expect(app.canCancelSignIn)
        app.showMainPage()
        guard case .mainPage = app.phase else { Issue.record("Cancel goes back"); return }
    }

    @Test func signingOutOfOneServerKeepsTheOthers() async throws {
        let (app, store) = try app([Self.away, Self.home])
        await app.launch()
        let away = try #require(app.servers.first)
        #expect(app.signOutConfirmation(for: away).question == "Sign out of tv.example/jellyfin?")
        await app.signOut(of: away)   // the server can't be reached here: it's forgotten anyway
        #expect(store.allCredentials() == [Self.home])
        guard case .mainPage = app.phase else { Issue.record("Back to the main page"); return }
        #expect(app.servers.map(\.address) == ["192.168.1.5:8096"] && app.servers[0].isLastWatched)

        await app.signOut(of: app.servers[0])
        guard case .signedOut = app.phase else { Issue.record("The last one gone: sign in"); return }
    }

    @Test func addressesShowWithoutTheScheme() {
        #expect(AppModel.address(of: URL(string: "http://nas:8096")!) == "nas:8096")
        #expect(AppModel.address(of: URL(string: "https://tv.example")!) == "tv.example")
        #expect(AppModel.address(of: URL(string: "https://tv.example/jf/")!) == "tv.example/jf/")
    }

    // MARK: The remote

    /// Menu always goes back one level: guide → live TV → main page → Home.
    @Test func menuGoesBackOneLevelAtATime() {
        #expect(RemoteControls.mainPage[.menu] == nil, "Menu goes to the Home screen, as Apple asks")
        #expect(RemoteControls.mainPage[.playPause] == .watchLastServer)
        #expect(RemoteControls.mainPageHint.hasSuffix("Menu: Home screen"))
        #expect(RemoteControls.watching[.menu] == .hideInfoOrOpenMainPage)
        for table in [RemoteControls.guide, RemoteControls.channelList, RemoteControls.settings] {
            #expect(table[.menu] == .close, "Menu closes what's over live TV, back to the channel")
        }
    }
}
