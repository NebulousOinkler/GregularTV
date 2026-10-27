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
    /// What the device's add-on player plays as it is, if it has one.
    let addOnFormats: PlayableFormats?
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
        JellyfinClient(credentials: credentials, identity: identity(for: credentials), formats: formats, addOnFormats: addOnFormats,
                       transport: transport)
    }

    /// Whether `link` is one the app may fetch a published file from (`PublicFile.mayFetch`).
    func mayFetch(_ link: URL) -> Bool {
        PublicFile.mayFetch(link)
    }

    /// The file published at `link`, such as a feed, of at most `largest`
    /// bytes. Throws a `LinkProblem` in plain words.
    func publishedFile(at link: URL, largest: Int) async throws -> Data {
        do {
            return try await PublicFile(transport: transport).fetch(link, largest: largest)
        } catch let failure as PublicFile.Failure {
            throw LinkProblem(failure)
        }
    }

    /// How this device introduces itself with `credentials`: the device ID it signed in with.
    private func identity(for credentials: Credentials) -> ClientIdentity {
        ClientIdentity(credentials, deviceName: deviceName)
    }
}

extension LinkProblem {
    init(_ failure: PublicFile.Failure) {
        switch failure {
        case .notAllowed: self.init(description: FeedText.badLink, isGone: false)
        case .gone: self.init(description: FeedText.gone, isGone: true)
        case .refused(let status): self.init(description: FeedText.refused(status), isGone: false)
        case .tooLarge: self.init(description: FeedText.tooLarge, isGone: true)
        case .redirectedAway: self.init(description: FeedText.redirectedAway, isGone: false)
        case .unreachable(let maybeNotAllowed):
            self.init(description: maybeNotAllowed ? FeedText.unreachableInBrowser : FeedText.unreachableLink, isGone: false)
        }
    }
}
