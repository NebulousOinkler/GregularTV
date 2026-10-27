import Foundation
import GregularCore

/// The one way the app fetches anything that isn't on the media server: a
/// file someone published at a link, such as a feed of channels. It goes
/// over the same `HTTPTransport` as every other request, and keeps to the
/// same rules, checked again here on every reply:
/// - https, or plain http only on the local network (`ServerAddress.isAllowed`);
///   never a link with a user name or password in it;
/// - no `Authorization`, cookies or referrer, and no language or device
///   (`headers`): the host learns only that something asked for the file;
/// - redirects only within the same host (`TransportRules`; a browser follows none);
/// - at most `largest` bytes, stopped as they arrive.
public struct PublicFile: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// Not a link the app may fetch (see above).
        case notAllowed
        /// The host says it's gone (HTTP 404 or 410).
        case gone
        /// The host answered with another error.
        case refused(status: Int)
        /// Larger than allowed.
        case tooLarge
        /// A reply from somewhere a redirect shouldn't have gone.
        case redirectedAway
        /// No answer: offline or timed out. `maybeNotAllowed`: in a browser,
        /// which can't say why, it may also be that the host doesn't let web
        /// pages read it (`HTTPTransport.needsHostsPermission`).
        case unreachable(maybeNotAllowed: Bool)
    }

    /// What's sent with the request. The app calls itself just "GregularTV",
    /// not by the platform's own User-Agent, which names the system and its
    /// version, and asks for any language rather than letting the platform
    /// name the device's. (A browser sends its own User-Agent, whatever the
    /// page asks; `FetchTransport` leaves it out.)
    static let headers = ["Accept": "application/json", "Accept-Language": "*", "User-Agent": "GregularTV"]

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Whether the app may fetch `url` at all.
    public static func mayFetch(_ url: URL) -> Bool {
        ServerAddress.isAllowed(url) && url.user == nil && url.password == nil && url.host()?.isEmpty == false
    }

    /// The file at `url`, of at most `largest` bytes.
    public func fetch(_ url: URL, largest: Int) async throws -> Data {
        guard Self.mayFetch(url) else { throw Failure.notAllowed }
        let request = ServerRequest(url: url, headers: Self.headers, largestResponse: largest)
        let reply: ServerReply
        do {
            reply = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch JellyfinError.responseTooLarge {
            throw Failure.tooLarge
        } catch {
            throw Failure.unreachable(maybeNotAllowed: transport.needsHostsPermission)
        }
        guard reply.url == url || TransportRules.allowsRedirect(from: url, to: reply.url) else { throw Failure.redirectedAway }
        guard reply.body.count <= largest else { throw Failure.tooLarge }
        switch reply.status {
        case 200..<300: return reply.body
        case 404, 410: throw Failure.gone
        default: throw Failure.refused(status: reply.status)
        }
    }
}
