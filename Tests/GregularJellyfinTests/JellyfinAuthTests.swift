import Foundation
import Testing
import GregularCore
@testable import GregularJellyfin

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
        #expect(ServerAddress.candidates(for: "tv.local").map(\.absoluteString) == ["https://tv.local", "http://tv.local"])
        #expect(ServerAddress.candidates(for: "tv.example.net").map(\.absoluteString) == ["https://tv.example.net"],
                "Plain http only on the local network")
        #expect(ServerAddress.candidates(for: "http://tv.example.net").isEmpty)
        #expect(ServerAddress.candidates(for: "http://10.0.0.2:8096").map(\.absoluteString) == ["http://10.0.0.2:8096"])
        #expect(ServerAddress.candidates(for: "ftp://x").isEmpty)
    }

    @Test(arguments: [
        ("localhost", true), ("jellyfin", true), ("tv.local", true), ("nas.home.arpa", true),
        ("127.0.0.1", true), ("10.1.2.3", true), ("172.16.0.1", true), ("172.31.255.255", true), ("192.168.1.5", true),
        ("169.254.10.10", true), ("[::1]", true), ("fe80::1", true), ("fd12:3456::1", true), ("nas", true), ("0.0.0.0", false),
        ("tv.example.net", false), ("8.8.8.8", false), ("172.32.0.1", false), ("100.128.0.1", false),
        // Other ways to write an address, which a resolver reads as a public one:
        ("134744072", false), ("0x08080808", false), ("010.8.8.8", false), ("0172.16.0.1", false), ("8.8.2056", false),
        ("0x0a.1.1.1", false), ("10.1.1.256", false), ("١٠.1.1.1", false),
        // Carrier-grade NAT: Tailscale, but also internet providers' own networks.
        ("100.101.102.103", false), ("100.64.0.1", false),
        ("192.168.1.5.example.net", false), ("2001:db8::1", false), ("local", true), ("evil.local.example.com", false),
    ])
    func localNetwork(host: String, local: Bool) {
        #expect(ServerAddress.isOnLocalNetwork(host) == local)
    }

    @Test func plainHTTPToTheInternetIsNeverSent() async {
        let mock = MockJellyfin()
        mock.on("GET", "/System/Info/Public", json: "{}")
        let server = JellyfinServer(url: URL(string: "http://media.example.com")!, identity: JellyfinFixtures.identity, transport: mock)
        await #expect(throws: JellyfinError.insecureAddress) { try await server.publicInfo() }
        #expect(mock.requests.isEmpty, "Refused before anything is sent")
    }

    @Test(arguments: ["", "   ", "ftp://server", "http://"])
    func rejects(input: String) {
        #expect(ServerAddress.normalize(input) == nil)
    }
}

struct ClientIdentityTests {
    @Test func headerWithoutToken() {
        #expect(ClientIdentity(deviceID: "abc", deviceName: "Apple TV").authorizationHeader(token: nil)
                == #"MediaBrowser Client="Gregular TV", Device="Apple TV", DeviceId="abc", Version="\#(ClientIdentity.clientVersion)""#)
    }

    @Test func aDeviceNameCantAddAHeader() {
        let header = ClientIdentity(deviceID: "abc", deviceName: "TV\r\nX-Evil: 1\u{0}").authorizationHeader(token: nil)
        #expect(header.contains(#"Device="TVX-Evil: 1""#))
        #expect(!header.contains("\r") && !header.contains("\n") && !header.contains("\u{0}"))
    }

    @Test func theAppUsingItNamesTheDevice() {
        // Nothing here assumes an Apple TV: a web version names its own kind of device.
        #expect(ClientIdentity(deviceID: "abc", deviceName: "Web Browser").authorizationHeader(token: nil).contains(#"Device="Web Browser""#))
    }

    @Test func headerWithTokenStripsBreakingCharacters() {
        let header = ClientIdentity(deviceID: "a\"b,c", deviceName: "Apple TV").authorizationHeader(token: "t0k")
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
