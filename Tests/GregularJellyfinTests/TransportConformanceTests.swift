import Foundation
import Testing
@testable import GregularJellyfin

/// What every `HTTPTransport` must do (`TransportRules`), checked against
/// stand-in servers. A new transport built on URLSession goes in
/// `transports`; one built on something else needs its own stand-ins for
/// the same checks. `JellyfinAPI` also checks the rules on every reply
/// (below), so even a transport that gets them wrong can't pass one on.
@Suite(.serialized)
struct TransportConformanceTests {
    // MARK: Redirects

    @Test(arguments: [
        ("https://tv.example/a", "https://tv.example/b", true),
        ("https://tv.example:8920/a", "https://TV.example:8920/b", true),
        ("http://tv.local:8096/a", "https://tv.local:8920/a", true),     // up to https on the same host
        ("https://tv.example/a", "http://tv.example/a", false),          // never down to http
        ("https://tv.example/a", "https://other.example/a", false),
        ("https://tv.example/a", "https://tv.example.other.example/a", false),
        ("https://tv.example/a", "https://tv.example:444/a", false),
        ("http://tv.local:8096/a", "http://tv.local:9000/a", false),
    ])
    func redirectsOnlyToTheSameServer(from: String, to: String, allowed: Bool) {
        #expect(TransportRules.allowsRedirect(from: URL(string: from)!, to: URL(string: to)!) == allowed)
    }

    // MARK: JellyfinAPI checks every reply too

    /// A transport that breaks the rules: it hands back whatever it's told to.
    private struct CarelessTransport: HTTPTransport {
        let answeredFrom: URL?
        let size: Int

        func send(_ request: ServerRequest) async throws -> ServerReply {
            ServerReply(url: answeredFrom ?? request.url, status: 200, body: Data(repeating: 0x20, count: size))
        }
    }

    private func publicInfo(through transport: CarelessTransport) async throws {
        _ = try await JellyfinServer(url: URL(string: "https://tv.example")!, identity: JellyfinFixtures.identity,
                                     transport: transport).publicInfo()
    }

    @Test func aReplyFromAnotherServerIsNeverUsed() async {
        await #expect(throws: JellyfinError.invalidResponse) {
            try await publicInfo(through: CarelessTransport(answeredFrom: URL(string: "https://elsewhere.example/System/Info/Public"), size: 2))
        }
    }

    @Test func aReplyTooLargeIsNeverUsed() async {
        await #expect(throws: JellyfinError.responseTooLarge) {
            try await publicInfo(through: CarelessTransport(answeredFrom: nil, size: TransportRules.largestResponse + 1))
        }
    }
}

#if canImport(Darwin)
// URLSession's transport, on Apple platforms (other platforms' transports
// are checked where they're built: `FetchTransport` in Web/).
extension TransportConformanceTests {
    /// Every URLSession-based transport, made with the stand-in servers.
    static let transports: [String: @Sendable (URLSessionConfiguration) -> any HTTPTransport] = [
        "URLSessionTransport": { URLSessionTransport(configuration: $0) },
    ]
    static let names = Array(transports.keys)

    private func transport(_ name: String) -> any HTTPTransport {
        let configuration = URLSessionTransport.makeConfiguration()
        configuration.protocolClasses = [StandInServer.self]
        return Self.transports[name]!(configuration)
    }

    private func send(_ name: String, _ url: String, body: Data? = nil) async throws -> ServerReply {
        try await transport(name).send(ServerRequest(method: body == nil ? "GET" : "POST", url: URL(string: url)!, body: body))
    }

    @Test(arguments: names)
    func aSignInRedirectedElsewhereIsNotSentOn(transport: String) async throws {
        StandInServer.reset()
        let reply = try await send(transport, "https://tv.example/elsewhere", body: Data(#"{"Pw":"secret"}"#.utf8))
        #expect(reply.status == 307, "Stopped at the redirect")
        #expect(StandInServer.hosts == ["tv.example"], "Nothing reached the other host")
    }

    @Test(arguments: names)
    func aRedirectOnTheSameServerIsFollowed(transport: String) async throws {
        let reply = try await send(transport, "https://tv.example/moved")
        #expect(reply.status == 200 && reply.url.path() == "/small" && reply.body.count == 300_000)
    }

    // MARK: Reply size

    @Test(arguments: names)
    func anOrdinaryReplyArrivesWhole(transport: String) async throws {
        let reply = try await send(transport, "https://tv.example/small")
        #expect(reply.status == 200 && reply.body == Data(repeating: 7, count: 300_000))
    }

    @Test(arguments: names)
    func aReplyAnnouncedAsTooLargeIsTurnedDown(transport: String) async {
        await #expect(throws: JellyfinError.responseTooLarge) { try await send(transport, "https://tv.example/announced") }
    }

    @Test(arguments: names)
    func aReplyThatNeverEndsIsStoppedPartway(transport: String) async {
        StandInServer.reset()
        await #expect(throws: JellyfinError.responseTooLarge) { try await send(transport, "https://tv.example/flood") }
        // Stopped soon after the limit: nowhere near the 256 MB the server would send.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(StandInServer.bytesSent < TransportRules.largestResponse + 8 * StandInServer.chunk.count)
        #expect(StandInServer.stopped)
    }

    // MARK: Storing nothing

    @Test func urlSessionTransportStoresNothing() {
        let config = URLSessionTransport.makeConfiguration()
        #expect(config.urlCache == nil)
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.urlCredentialStorage == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }
}

/// Stand-in servers at tv.example:
/// - `/small`: 300 KB, with its size stated;
/// - `/moved`: a redirect to `/small` on the same server;
/// - `/elsewhere`: a redirect to another host;
/// - `/announced`: a reply stating a size of a terabyte;
/// - `/flood`: a megabyte at a time, with no stated size, until stopped.
final class StandInServer: URLProtocol, @unchecked Sendable {
    static let chunk = Data(repeating: 1, count: 1024 * 1024)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seenHosts: [String] = []
    nonisolated(unsafe) private static var sent = 0
    nonisolated(unsafe) private static var wasStopped = false
    static var hosts: [String] { lock.withLock { seenHosts } }
    static var bytesSent: Int { lock.withLock { sent } }
    static var stopped: Bool { lock.withLock { wasStopped } }
    static func reset() { lock.withLock { seenHosts = []; sent = 0; wasStopped = false } }

    private let stopLock = NSLock()
    nonisolated(unsafe) private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seenHosts.append(url.host() ?? "") }
        guard url.host() == "tv.example" else { return finish(Data("{}".utf8)) }
        switch url.path() {
        case "/small":
            respond(headers: ["Content-Length": "300000"])
            finish(Data(repeating: 7, count: 300_000))
        case "/moved":
            redirect(to: "https://tv.example/small")
        case "/elsewhere":
            redirect(to: "https://elsewhere.example/steal")
        case "/announced":
            respond(headers: ["Content-Length": String(1 << 40)])
            finish(Data(repeating: 1, count: 10))
        default:
            respond(headers: [:])
            DispatchQueue.global().async {
                for _ in 0..<256 {
                    if self.stopLock.withLock({ self.isStopped }) { return }
                    Self.lock.withLock { Self.sent += Self.chunk.count }
                    self.client?.urlProtocol(self, didLoad: Self.chunk)
                    Thread.sleep(forTimeInterval: 0.002)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    private func respond(status: Int = 200, headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private func finish(_ data: Data) {
        if request.url?.host() != "tv.example" { respond(headers: [:]) }
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func redirect(to location: String) {
        let redirect = HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: ["Location": location])!
        var next = request
        next.url = URL(string: location)
        client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: redirect)
        client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stopLock.withLock { isStopped = true }
        Self.lock.withLock { Self.wasStopped = true }
    }
}
#endif
