import GregularScreens
import SwiftUI

struct RootView: View {
    @State private var app = AppModel.forLaunch()

    var body: some View {
        ZStack {
            // Live TV sits underneath, in the same place whether it's on screen
            // or playing on behind the main page, so going up to the main page
            // and back never rebuilds it (or re-tunes).
            if let surfer = app.liveTV {
                WatchView(surfer: surfer, app: app, isCovered: app.isOverLiveTV)
                    // A new schedule code (or new channels) brings a new surfer; start a fresh view for it.
                    .id(ObjectIdentifier(surfer))
            }
            switch app.phase {
            case .launching:
                BrandedWait(message: nil)
            case .signedOut:
                LoginView(model: app.makeLoginModel(), notice: app.signedOutReason,
                          onCancel: app.canCancelSignIn ? { app.showMainPage() } : nil)
            case .mainPage:
                MainPageView(app: app)
            case .loading:
                BrandedWait(message: "Loading your library…")
            case .watching:
                EmptyView()   // drawn above
            case .failed(let message):
                VStack(spacing: 32) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 80))
                    Text(message).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1200)
                    Text("Trying again automatically every 30 seconds.").foregroundStyle(.secondary)
                    HStack(spacing: 40) {
                        Button("Try Again") { Task { await app.retry() } }
                        Button("All Servers") { app.showMainPage() }
                    }
                }
                // A TV is often left on; recover by itself when the server comes back.
                .task {
                    try? await Task.sleep(for: .seconds(30))
                    await app.retry()
                }
            }
        }
        .task {
            // When Xcode runs the app's tests, it launches the app as a host.
            // The simulator clone it uses has a copy of the Keychain, so without
            // this guard the hidden app would sign in and start playing (audio
            // with no visible video).
            guard !Self.isHostingTests else { return }
            await app.launch()
        }
    }

    private static var isHostingTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}

/// The name, tagline and a spinner, while the app starts or loads the library.
private struct BrandedWait: View {
    let message: String?

    var body: some View {
        VStack(spacing: 28) {
            Masthead()
            ProgressView().padding(.top, 20)
            if let message { Text(message).foregroundStyle(.secondary) }
        }
    }
}
