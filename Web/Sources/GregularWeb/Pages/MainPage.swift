import GregularScreens
import JavaScriptKit

/// The main page: the servers signed in to, and adding another. The app
/// opens here, with the server watched last first, so one tap (or Enter, or
/// Space) starts live TV. Each server has its own Sign Out. From the guide,
/// Escape comes up here with the channel playing on, dimmed, behind the page.
@MainActor final class MainPage: Page, KeyTarget {
    let element = El("main", "page main-page")
    private let app: AppModel
    private let notice = El("div").attribute("role", "status")
    private let list = El("ul", "server-list")
    private var redraws: [Redraw] = []
    private var drawnServers: [AppModel.Server] = []

    init(app: AppModel) {
        self.app = app
        let content = El("div", "content wide", [
            El("h1", "page-title", text: "Your servers"),
            notice,
            list,
            El("p", "hint keyboard-hint",
               text: "Enter: watch · " + RemoteControls.hint(for: RemoteControls.mainPage, names: KeyboardControls.names)),
        ])
        element.append(Parts.appBar(), content, Parts.footer())
        redraws = [
            Redraw { [weak self] in self?.drawNotice() },
            Redraw { [weak self] in self?.drawServers() },
        ]
        Keys.take(self)
        Task { await app.loadServerNames() }
    }

    func appeared() {
        Focus.focusable(in: list).first?.focus()
    }

    func close() {
        redraws.forEach { $0.stop() }
        Keys.release(self)
    }

    func press(_ button: RemoteButton) -> Bool {
        if let direction = button.direction { return Focus.move(direction, within: element) }
        guard RemoteControls.mainPage[button] == .watchLastServer else { return false }
        Task { await app.watchLastServer() }
        return true
    }

    private func drawNotice() {
        notice.replaceChildren(app.notice.map { [Parts.callout($0, kind: "warn", icon: .warning)] } ?? [])
    }

    private func drawServers() {
        let servers = app.servers
        guard servers != drawnServers else { return }
        // Keep focus on the same server across a redraw (its name arriving).
        let focusedID = DOM.focused?.dataset.object?.server.string
        drawnServers = servers
        list.replaceChildren(servers.map(item(for:)) + [addItem()])
        if let focusedID {
            Focus.focusable(in: list).first { $0.object.dataset.server.string == focusedID }?.focus()
        }
    }

    private func item(for server: AppModel.Server) -> El {
        let badges = El("span", "server-badges")
        if let badge = server.badge { badges.append(El("span", "badge" + (server.isPlaying ? " playing" : ""), text: badge)) }
        let text = El("span", "server-text", [El("span", "server-title", text: server.title)])
        text.append(El("span", "server-line", text: server.name == nil ? "\(AppModel.serverName) server" : server.address))
        text.append(badges)
        let watch = El("button", "server-main", [El("span", "server-icon", [Icon.tv.element]), text])
        let chevron = Icon.chevronRight.element
        chevron.attribute("class", "icon chevron")
        watch.append(chevron)
        watch.attribute("type", "button").attribute("data-server", server.id)
            .attribute("aria-label", "Watch \(server.title)" + (server.badge.map { ", \($0)" } ?? ""))
        watch.on("click") { [app] _ in Task { await app.watch(server) } }
        let signOut = El.button("Sign out of \(server.title)", icon: .signOut, "icon-button", labelHidden: true) { [app] in
            Parts.confirm(app.signOutConfirmation(for: server)) { Task { await app.signOut(of: server) } }
        }
        return El("li", "server" + (server.isLastWatched ? " last" : ""), [watch, El("div", "server-actions", [signOut])])
    }

    private func addItem() -> El {
        let add = El("button", "server-main", [
            El("span", "server-icon", [Icon.plus.element]),
            El("span", "server-text", [
                El("span", "server-title", text: "Add a server"),
                El("span", "server-line", text: "Sign in to another \(AppModel.serverName) server"),
            ]),
        ])
        add.attribute("type", "button").attribute("data-server", "add")
        add.on("click") { [app] _ in app.addServer() }
        return El("li", "server add-server", [add])
    }
}
