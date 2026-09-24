import Foundation
import Testing
@testable import GregularTVCore

struct ServerAddressTests {
    @Test(arguments: [
        ("192.168.1.5:8096", "http://192.168.1.5:8096"),
        ("  jellyfin.local:8096/ ", "http://jellyfin.local:8096"),
        ("HTTPS://media.example.com/jellyfin/", "https://media.example.com/jellyfin"),
        ("https://user:pw@media.example.com?x=1#frag", "https://media.example.com"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(ServerAddress.normalize(input)?.absoluteString == expected)
    }

    @Test func candidatesTryHTTPSFirstWhenNoSchemeTyped() {
        #expect(ServerAddress.candidates(for: "tv.example.net").map(\.absoluteString)
                == ["https://tv.example.net", "http://tv.example.net"])
        #expect(ServerAddress.candidates(for: "http://10.0.0.2:8096").map(\.absoluteString) == ["http://10.0.0.2:8096"])
        #expect(ServerAddress.candidates(for: "ftp://x").isEmpty)
    }

    @Test(arguments: ["", "   ", "ftp://server", "http://"])
    func rejects(input: String) {
        #expect(ServerAddress.normalize(input) == nil)
    }
}

struct ClientIdentityTests {
    @Test func headerWithoutToken() {
        #expect(ClientIdentity(deviceID: "abc").authorizationHeader(token: nil)
                == #"MediaBrowser Client="Gregular TV", Device="Apple TV", DeviceId="abc", Version="\#(ClientIdentity.clientVersion)""#)
    }

    @Test func headerWithTokenStripsBreakingCharacters() {
        let header = ClientIdentity(deviceID: "a\"b,c").authorizationHeader(token: "t0k")
        #expect(header.contains(#"DeviceId="abc""#))
        #expect(header.hasSuffix(#"Token="t0k""#))
    }
}

struct JellyfinAuthTests {
    let mock = MockJellyfin()
    var server: JellyfinServer { JellyfinServer(url: JellyfinFixtures.server, identity: JellyfinFixtures.identity, transport: mock) }

    @Test func publicInfo() async throws {
        mock.on("GET", "/System/Info/Public", json: #"{ "ServerName": "Den", "Version": "10.10.3", "Id": "x" }"#)
        #expect(try await server.publicInfo() == .init(serverName: "Den", version: "10.10.3"))
    }

    @Test func passwordSignInSendsCredentialsOnceAndReturnsToken() async throws {
        mock.on("POST", "/Users/AuthenticateByName", json: JellyfinFixtures.authResult)
        let credentials = try await server.signIn(username: "sam", password: "hunter2")

        #expect(credentials == JellyfinFixtures.credentials)
        let request = try #require(mock.requests.first)
        #expect(request.jsonBody["Username"] as? String == "sam")
        #expect(request.jsonBody["Pw"] as? String == "hunter2")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("Token=") == false)
    }

    @Test func wrongPasswordIsUnauthorized() async {
        mock.on("POST", "/Users/AuthenticateByName", status: 401)
        await #expect(throws: JellyfinError.unauthorized) {
            try await server.signIn(username: "sam", password: "nope")
        }
    }

    @Test func quickConnectPollsUntilApproved() async throws {
        mock.on("GET", "/QuickConnect/Enabled", json: "true")
        mock.on("POST", "/QuickConnect/Initiate", json: #"{ "Code": "123456", "Secret": "s3cret", "Authenticated": false }"#)
        let polls = Counter()
        mock.on("GET", "/QuickConnect/Connect") { request in
            #expect(request.queryValue("secret") == "s3cret")
            return (200, #"{ "Authenticated": \#(polls.increment() >= 3) }"#)
        }
        mock.on("POST", "/Users/AuthenticateWithQuickConnect") { request in
            #expect(request.jsonBody["Secret"] as? String == "s3cret")
            return (200, JellyfinFixtures.authResult)
        }

        let request = try await server.startQuickConnect()
        #expect(request.code == "123456")
        let credentials = try await server.waitForQuickConnect(request, pollInterval: .milliseconds(1))
        #expect(credentials == JellyfinFixtures.credentials)
        #expect(polls.value == 3)
    }

    @Test func quickConnectDisabled() async {
        mock.on("GET", "/QuickConnect/Enabled", json: "false")
        await #expect(throws: JellyfinError.quickConnectDisabled) { try await server.startQuickConnect() }
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() -> Int { lock.withLock { count += 1; return count } }
}
