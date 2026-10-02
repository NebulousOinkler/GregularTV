import GregularScreens
import SwiftUI

/// The main page: the servers signed in to, and adding another. The app
/// opens here, with the server watched last highlighted, so one click (or
/// Play/Pause) starts live TV. Holding a click on a server signs out of it.
/// Menu isn't handled, so tvOS takes it to the Home screen, as Apple asks of
/// an app's first screen. Menu from live TV comes back up here (see
/// `RemoteControls`), with the channel playing on, dimmed, behind the page:
/// a click on its server goes straight back to it.
struct MainPageView: View {
    let app: AppModel

    @FocusState private var focused: String?
    @State private var signingOut: AppModel.Server?

    /// Focus ID of the Add a Server card.
    private static let addID = "add"

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Masthead(alignment: .leading)
            Text(app.servers.count == 1 ? "Your server" : "Your servers").font(.headline).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 48) {
                    ForEach(app.servers) { server in
                        Button { Task { await app.watch(server) } } label: { ServerCard(server: server) }
                            .buttonStyle(.card)
                            .focused($focused, equals: server.id)
                            .contextMenu {
                                Button("Sign Out of \(server.title)", role: .destructive) { signingOut = server }
                            }
                    }
                    Button { app.addServer() } label: { AddServerCard() }
                        .buttonStyle(.card)
                        .focused($focused, equals: Self.addID)
                }
                .padding(.vertical, 40)   // room for the cards to lift when highlighted
            }
            .scrollClipDisabled()
            Text(RemoteControls.mainPageHint).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 90)
        .padding(.vertical, 70)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .defaultFocus($focused, app.servers.first?.id)
        .remoteControls(RemoteControls.mainPage) { action in
            if action == .watchLastServer { Task { await app.watchLastServer() } }
        }
        .confirming(signingOut.map(app.signOutConfirmation(for:)),
                    isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } })) { [signingOut] in
            if let server = signingOut { Task { await app.signOut(of: server) } }
        }
        .task {
            // In case the default didn't take: over live TV, focus is still
            // leaving the channel underneath as the page appears.
            await FocusSettling.wait()
            if focused == nil { focused = app.servers.first?.id }
            await app.loadServerNames()
        }
    }
}

/// A card on the main page: an icon, a title, and a line or two under it.
private struct Card<Lines: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let lines: Lines

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 56))
            Spacer(minLength: 0)
            Text(title).font(.title3).bold().lineLimit(2)
            lines.font(.caption).lineLimit(1)
        }
        .padding(32)
        .frame(width: 440, height: 300, alignment: .topLeading)
    }
}

/// One server: its name (or address, until it answers), where it is, and
/// whether it's playing or was watched last.
private struct ServerCard: View {
    let server: AppModel.Server

    var body: some View {
        Card(icon: "server.rack", title: server.title) {
            if server.name != nil { Text(server.address).foregroundStyle(.secondary) }
            if let badge = server.badge { Text(badge).bold().foregroundStyle(.tint) }
        }
    }
}

private struct AddServerCard: View {
    var body: some View {
        Card(icon: "plus.circle", title: "Add a Server") {
            Text("Sign in to another Jellyfin server").foregroundStyle(.secondary)
        }
    }
}
