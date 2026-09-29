import Foundation
import Testing
@testable import GregularJellyfin

/// Redirects stay on the server the viewer signed in to.
@Suite(.serialized)
struct RedirectTests {
    @Test(arguments: [
        ("https://tv.example/a", "https://tv.example/b", true),
        ("https://tv.example:8920/a", "https://TV.example:8920/b", true),
        ("http://tv.local:8096/a", "https://tv.local:8920/a", true),     // upgrade on the same host
        ("https://tv.example/a", "http://tv.example/a", false),          // never down to http
        ("https://tv.example/a", "https://other.example/a", false),
        ("https://tv.example/a", "https://tv.example.other.example/a", false),
        ("https://tv.example/a", "https://tv.example:444/a", false),
        ("http://tv.local:8096/a", "http://tv.local:9000/a", false),
    ])
    func onlyTheSameServer(from: String, to: String, allowed: Bool) {
        #expect(RedirectGuard.allows(from: URL(string: from)!, to: URL(string: to)!) == allowed)
    }

    @Test func aSignInRedirectedElsewhereIsNotSentOn() async throws {
        StandInServer.reset()
        let configuration = URLSessionTransport.makeConfiguration()
        configuration.protocolClasses = [StandInServer.self]
        let transport = URLSessionTransport(configuration: configuration)
        var request = URLRequest(url: URL(string: "https://tv.example/Users/AuthenticateByName")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"Pw":"secret"}"#.utf8)
        let (_, response) = try await transport.send(request)
        #expect(response.statusCode == 307, "Stopped at the redirect")
        #expect(StandInServer.hosts == ["tv.example"], "Nothing reached the other host")
    }
}

/// Answers every request to tv.example with a redirect to another host.
final class StandInServer: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [String] = []
    static var hosts: [String] { lock.withLock { seen } }
    static func reset() { lock.withLock { seen = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url.host() ?? "") }
        if url.host() == "tv.example" {
            let redirect = HTTPURLResponse(url: url, statusCode: 307, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": "https://elsewhere.example/steal"])!
            var next = request
            next.url = URL(string: "https://elsewhere.example/steal")
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: redirect)
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
