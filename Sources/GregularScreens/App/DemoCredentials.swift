import Foundation
import GregularCore
import GregularJellyfin

#if DEBUG
/// Demo mode, for App Store screenshots. Launch with
/// `-demoServer http://localhost:8765` and the app signs in to that address,
/// held in memory only: nothing is written to the Keychain. Pair it with
/// `scripts/demo-server.py`, which serves a sample library of public-domain
/// films and made-up shows. Compiled out of Release builds.
public struct DemoCredentials: CredentialStore {
    public let credentials: Credentials

    public static func fromLaunchArguments() -> DemoCredentials? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoServer"), index + 1 < arguments.count,
              let url = URL(string: arguments[index + 1]) else { return nil }
        return DemoCredentials(credentials: Credentials(serverURL: url, userID: "demo", accessToken: "demo"))
    }

    public func loadCredentials() -> Credentials? { credentials }
    public func saveCredentials(_ credentials: Credentials) throws {}
    public func deleteCredentials() throws {}
    public func deviceID() -> String { "demo" }
}
#endif
