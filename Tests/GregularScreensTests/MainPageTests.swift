import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// The main page: the servers signed in to, the app's first screen.
@MainActor
struct MainPageTests {
    static let home = Credentials(serverURL: URL(string: "http://192.168.1.5:8096")!, userID: "u", accessToken: "t1", deviceID: "d-t1")
    static let away = Credentials(serverURL: URL(string: "https://tv.example/jellyfin")!, userID: "u", accessToken: "t2", deviceID: "d-t2")

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
        #expect(app.notice?.contains("couldn't be reached to cancel the sign-in") == true,
                "Says the sign-in still works on the server, and how to cancel it")

        await app.signOut(of: app.servers[0])
        guard case .signedOut = app.phase else { Issue.record("The last one gone: sign in"); return }
        #expect(app.signedOutReason?.contains("couldn't be reached") == true, "Said on the sign-in screen instead")
    }

    /// Secure storage can outlive the app: a sign-in from before it was
    /// deleted doesn't come back with a new install. An update keeps them.
    @Test func aNewInstallStartsWithNoSignIns() throws {
        let store = InMemoryCredentialStore(credentials: Self.home)
        _ = Fixture.app(store: store)
        #expect(store.allCredentials() == [Self.home], "Launched before: kept")
        _ = Fixture.app(store: store, firstLaunch: true)
        #expect(store.allCredentials().isEmpty, "Just installed: forgotten")
    }

    /// The password never goes to a server it wasn't typed for, and the
    /// sign-in stops (no Quick Connect left waiting) when its screen closes.
    @Test func signInForgetsThePassword() {
        let login = Fixture.app().makeLoginModel()
        login.password = "hunter2"
        login.changeServer()
        #expect(login.password.isEmpty, "Not carried to another server")
        login.password = "hunter2"
        login.stop()
        #expect(login.password.isEmpty && login.quickConnectCode == nil)
    }

    @Test func addressesShowWithoutTheScheme() {
        #expect(AppModel.address(of: URL(string: "http://nas:8096")!) == "nas:8096")
        #expect(AppModel.address(of: URL(string: "https://tv.example")!) == "tv.example")
        #expect(AppModel.address(of: URL(string: "https://tv.example/jf/")!) == "tv.example/jf/")
    }

    // MARK: The remote

    /// Menu: live TV → guide → Resume Live TV → main page → Home screen.
    @Test func menuStepsFromLiveTVUpToTheHomeScreen() {
        #expect(RemoteControls.watching[.menu] == .hideInfoOrOpenGuide)
        #expect(RemoteControls.guide[.menu] == .stepBack, "Up to Resume, then the main page (GuideView)")
        #expect(RemoteControls.mainPage[.menu] == nil, "Menu goes to the Home screen, as Apple asks")
        #expect(RemoteControls.mainPage[.playPause] == .watchLastServer)
        #expect(RemoteControls.mainPageHint.hasSuffix("Menu: Home screen"))
        for table in [RemoteControls.channelList, RemoteControls.settings] {
            #expect(table[.menu] == .close)
        }
    }
}
