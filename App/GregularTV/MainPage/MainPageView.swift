import GregularScreens
import SwiftUI

/// The main page: the servers signed in to, and adding another. The app
/// opens here, with the server watched last highlighted, so one click (or
/// Play/Pause) starts live TV. Holding a click on a server signs out of it.
/// Menu isn't handled, so tvOS takes it to the Home screen, as Apple asks of
/// an app's first screen. Menu from the guide's top row comes back up here
/// (see `RemoteControls`), with the channel playing on, dimmed, behind the
/// page: a click on its server goes straight back to it.
struct MainPageView: View {
    let app: AppModel

    @FocusState private var focused: String?
    @State private var signingOut: AppModel.Server?

    /// Focus ID of the Add a Server card.
    private static let addID = "add"

    var body: some View {
        VStack(spacing: 64) {
            Spacer(minLength: 0)
            Masthead()
            if let notice = app.notice {
                Text(notice).foregroundStyle(.yellow).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 1300)
            }
            serverCards
            Spacer(minLength: 0)
            Text(RemoteControls.mainPageHint).font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The servers, then Add a Server: centred, scrolling sideways if there
    /// are more than fit.
    private var serverCards: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                HStack(spacing: 48) {
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
                .padding(.horizontal, 90)
                .padding(.vertical, 40)   // room for the cards to lift when highlighted
                .frame(minWidth: geometry.size.width)
            }
            .scrollClipDisabled()
        }
        .frame(height: Card<EmptyView>.size.height + 80)
    }
}

/// A card on the main page: an icon in a soft circle, a title, and a line
/// or two under it.
private struct Card<Lines: View>: View {
    static var size: CGSize { CGSize(width: 420, height: 280) }

    let icon: String
    let title: String
    @ViewBuilder let lines: Lines

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 40, weight: .semibold))
                .frame(width: 88, height: 88)
                .background(.white.opacity(0.12), in: Circle())
            Spacer(minLength: 0)
            Text(title).font(.title3).bold().lineLimit(2).minimumScaleFactor(0.75)
            lines.font(.caption).lineLimit(1)
        }
        .padding(32)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }
}

/// One server: its name (or address, until it answers), where it is, and
/// whether it's playing or was watched last.
private struct ServerCard: View {
    let server: AppModel.Server

    var body: some View {
        Card(icon: "server.rack", title: server.title) {
            if server.name != nil { Text(server.address).foregroundStyle(.secondary) }
            if let badge = server.badge {
                HStack(spacing: 8) {
                    if server.isPlaying { Circle().fill(.red).frame(width: 10, height: 10) }
                    Text(badge).bold()
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.white.opacity(0.14), in: Capsule())
                .padding(.top, 4)
            }
        }
    }
}

private struct AddServerCard: View {
    var body: some View {
        Card(icon: "plus", title: "Add a Server") {
            Text("Sign in to another \(AppModel.serverName) server").foregroundStyle(.secondary)
        }
    }
}
