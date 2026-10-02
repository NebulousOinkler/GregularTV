import Foundation
import GregularCore
import GregularJellyfin

/// How this device reaches servers: what it calls itself, what it can play,
/// and the platform's network path. `AppModel` and `LoginModel` make every
/// server and client through it, so they all go the same way.
struct ServerAccess: Sendable {
    /// The kind of device, such as "Apple TV".
    let deviceName: String
    let formats: PlayableFormats
    let transport: any HTTPTransport

    /// A server being signed in to: a device ID of its own (`ClientIdentity.forSignIn`).
    func newServer(at url: URL) -> JellyfinServer {
        JellyfinServer(url: url, identity: .forSignIn(deviceName: deviceName), transport: transport)
    }

    /// The server of a saved sign-in.
    func server(of credentials: Credentials) -> JellyfinServer {
        JellyfinServer(url: credentials.serverURL, identity: identity(for: credentials), transport: transport)
    }

    func client(for credentials: Credentials) -> JellyfinClient {
        JellyfinClient(credentials: credentials, identity: identity(for: credentials), formats: formats, transport: transport)
    }

    /// How this device introduces itself with `credentials`: the device ID it signed in with.
    private func identity(for credentials: Credentials) -> ClientIdentity {
        ClientIdentity(credentials, deviceName: deviceName)
    }
}
