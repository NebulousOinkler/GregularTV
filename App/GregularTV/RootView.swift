import SwiftUI

struct RootView: View {
    @State private var app = AppModel.forLaunch()

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                BrandedWait(message: nil)
            case .signedOut:
                LoginView(identity: app.identity, notice: app.signedOutReason) { await app.didSignIn($0) }
            case .loading:
                BrandedWait(message: "Loading your library…")
            case .watching(let surfer):
                WatchView(surfer: surfer,
                          scheduleCode: app.scheduleCode,
                          showsDiagnostics: app.showsDiagnostics,
                          playsCommercials: app.playsCommercials,
                          commercialsStatus: app.commercialsStatus,
                          onQualityChange: { app.setStreamingQuality($0) },
                          onScheduleCodeChange: { app.setScheduleCode($0) },
                          onShowsDiagnosticsChange: { app.setShowsDiagnostics($0) },
                          onPlaysCommercialsChange: { app.setPlaysCommercials($0) },
                          onSignOut: { Task { await app.signOut() } })
                    // A new schedule code brings a new surfer; start a fresh view for it.
                    .id(ObjectIdentifier(surfer))
            case .failed(let message):
                VStack(spacing: 32) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 80))
                    Text(message).font(.title3).multilineTextAlignment(.center).frame(maxWidth: 1200)
                    Text("Trying again automatically every 30 seconds.").foregroundStyle(.secondary)
                    HStack(spacing: 40) {
                        Button("Try Again") { Task { await app.launch() } }
                        Button("Sign Out") { Task { await app.signOut() } }
                    }
                }
                // A TV is often left on; recover by itself when the server comes back.
                .task {
                    try? await Task.sleep(for: .seconds(30))
                    await app.launch()
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
            Text("Gregular TV").font(.system(size: 80, weight: .heavy, design: .rounded))
            Text("We now return to your Gregular programming.").font(.title3).foregroundStyle(.secondary)
            ProgressView().padding(.top, 20)
            if let message { Text(message).foregroundStyle(.secondary) }
        }
    }
}
