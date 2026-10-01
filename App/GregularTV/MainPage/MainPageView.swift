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
            VStack(alignment: .leading, spacing: 12) {
                Text("Gregular TV").font(.system(size: 80, weight: .heavy, design: .rounded))
                Text("We now return to your Gregular programming.").font(.title3).foregroundStyle(.secondary)
            }
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
        .confirmationDialog(signingOut.map { app.signOutConfirmation(for: $0).question } ?? "",
                            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                            titleVisibility: .visible, presenting: signingOut) { server in
            Button(app.signOutConfirmation(for: server).action, role: .destructive) {
                Task { await app.signOut(of: server) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { server in
            Text(app.signOutConfirmation(for: server).detail)
        }
        .task {
            // In case the default didn't take: over live TV, focus is still
            // leaving the channel underneath as the page appears.
            try? await Task.sleep(for: .milliseconds(100))
            if focused == nil { focused = app.servers.first?.id }
            await app.loadServerNames()
        }
    }
}

/// One server: its name (or address, until it answers), and where it is.
private struct ServerCard: View {
    let server: AppModel.Server

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "server.rack").font(.system(size: 56))
            Spacer(minLength: 0)
            Text(server.title).font(.title3).bold().lineLimit(2)
            if server.name != nil {
                Text(server.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if server.isPlaying {
                Text("Now playing").font(.caption).bold().foregroundStyle(.tint)
            } else if server.isLastWatched {
                Text("Watched last").font(.caption).bold().foregroundStyle(.tint)
            }
        }
        .padding(32)
        .frame(width: 440, height: 300, alignment: .topLeading)
    }
}

private struct AddServerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "plus.circle").font(.system(size: 56))
            Spacer(minLength: 0)
            Text("Add a Server").font(.title3).bold()
            Text("Sign in to another Jellyfin server").font(.caption).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 440, height: 300, alignment: .topLeading)
    }
}
