import Foundation
import GregularCore
@testable import GregularJellyfin

/// A fake Jellyfin server. Register responses per method and path. It records
/// every request so tests can inspect exactly what was sent.
final class MockJellyfin: HTTPTransport, @unchecked Sendable {
    typealias Handler = (ServerRequest) throws -> (status: Int, body: String)

    private let lock = NSLock()
    private var routes: [(method: String, path: String, handler: Handler)] = []
    private var recorded: [ServerRequest] = []

    var requests: [ServerRequest] { lock.withLock { recorded } }

    func on(_ method: String, _ path: String, status: Int = 200, json: String = "") {
        on(method, path) { _ in (status, json) }
    }

    func on(_ method: String, _ path: String, handler: @escaping Handler) {
        lock.withLock { routes.append((method, path, handler)) }
    }

    func send(_ request: ServerRequest) async throws -> ServerReply {
        let route = lock.withLock {
            recorded.append(request)
            return routes.last { $0.method == request.method && request.url.path.hasSuffix($0.path) }
        }
        let (status, body) = try route?.handler(request) ?? (404, "")
        return ServerReply(url: request.url, status: status, body: Data(body.utf8))
    }
}

extension ServerRequest {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    var jsonBody: [String: Any] {
        (body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }
}

enum JellyfinFixtures {
    static let server = URL(string: "http://tv.local:8096")!
    static let identity = ClientIdentity(deviceID: "device-123", deviceName: "Apple TV")
    static let credentials = Credentials(serverURL: server, userID: "user-1", accessToken: "token-abc", deviceID: "device-123")

    static func client(_ mock: MockJellyfin, server: URL = server, fallback: PlayableFormats? = nil) -> JellyfinClient {
        JellyfinClient(credentials: Credentials(serverURL: server, userID: "user-1", accessToken: "token-abc", deviceID: "device-123"),
                       identity: identity, formats: .appleTV, fallbackFormats: fallback, transport: mock)
    }

    static let authResult = #"{ "AccessToken": "token-abc", "User": { "Id": "user-1", "Name": "sam" }, "ServerId": "srv" }"#
    static let adminAuthResult =
        #"{ "AccessToken": "token-abc", "User": { "Id": "user-1", "Name": "sam", "Policy": { "IsAdministrator": true } }, "ServerId": "srv" }"#
}
