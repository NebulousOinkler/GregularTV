import Foundation
import GregularCore
import GregularJellyfin

extension AppModel {
    /// The model the app starts with. Release builds always use the saved
    /// sign-in (or show sign-in); Debug builds can instead start in demo mode.
    static func forLaunch() -> AppModel {
        #if DEBUG
        if let demo = DemoCredentials.fromLaunchArguments() { return AppModel(store: demo) }
        #endif
        return AppModel()
    }
}

#if DEBUG
/// Demo mode, for App Store screenshots. Launch with
/// `-demoServer http://localhost:8765` and the app signs in to that address,
/// held in memory only: nothing is written to the Keychain. Pair it with
/// `scripts/demo-server.py`, which serves a sample library of public-domain
/// films and made-up shows. Compiled out of Release builds.
struct DemoCredentials: CredentialStore {
    let credentials: Credentials

    static func fromLaunchArguments() -> DemoCredentials? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoServer"), index + 1 < arguments.count,
              let url = URL(string: arguments[index + 1]) else { return nil }
        return DemoCredentials(credentials: Credentials(serverURL: url, userID: "demo", accessToken: "demo"))
    }

    func loadCredentials() -> Credentials? { credentials }
    func saveCredentials(_ credentials: Credentials) throws {}
    func deleteCredentials() throws {}
    func deviceID() -> String { "demo" }
}
#endif
