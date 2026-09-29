import Foundation
import Testing
@testable import GregularJellyfin

/// Replies are limited as they arrive, so a server can't fill the app's memory.
@Suite(.serialized)
struct ResponseSizeTests {
    private func transport() -> URLSessionTransport {
        let configuration = URLSessionTransport.makeConfiguration()
        configuration.protocolClasses = [FloodServer.self]
        return URLSessionTransport(configuration: configuration)
    }

    private func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
        try await transport().send(URLRequest(url: URL(string: "https://tv.example\(path)")!))
    }

    @Test func anOrdinaryReplyArrivesWhole() async throws {
        let (data, response) = try await get("/small")
        #expect(response.statusCode == 200 && data == Data(repeating: 7, count: 300_000))
    }

    @Test func aReplyAnnouncedAsTooLargeIsTurnedDown() async {
        await #expect(throws: JellyfinError.responseTooLarge) { try await get("/announced") }
    }

    @Test func aReplyThatNeverEndsIsStoppedPartway() async {
        FloodServer.reset()
        await #expect(throws: JellyfinError.responseTooLarge) { try await get("/flood") }
        // Stopped soon after the limit: nowhere near the 256 MB the server would send.
        try? await Task.sleep(for: .milliseconds(200))
        #expect(FloodServer.bytesSent < URLSessionTransport.largestResponse + 8 * FloodServer.chunk.count)
        #expect(FloodServer.stopped)
    }
}

/// A server that answers `/small` normally, announces a huge `/announced`,
/// and sends `/flood` a megabyte at a time, with no stated size, until stopped.
final class FloodServer: URLProtocol, @unchecked Sendable {
    static let chunk = Data(repeating: 1, count: 1024 * 1024)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var sent = 0
    nonisolated(unsafe) private static var wasStopped = false
    static var bytesSent: Int { lock.withLock { sent } }
    static var stopped: Bool { lock.withLock { wasStopped } }
    static func reset() { lock.withLock { sent = 0; wasStopped = false } }

    private let stopLock = NSLock()
    nonisolated(unsafe) private var isStopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        switch url.path() {
        case "/small":
            respond(headers: ["Content-Length": "300000"])
            client?.urlProtocol(self, didLoad: Data(repeating: 7, count: 300_000))
            client?.urlProtocolDidFinishLoading(self)
        case "/announced":
            respond(headers: ["Content-Length": String(1 << 40)])
            client?.urlProtocol(self, didLoad: Data(repeating: 1, count: 10))
            client?.urlProtocolDidFinishLoading(self)
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

    private func respond(headers: [String: String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    override func stopLoading() {
        stopLock.withLock { isStopped = true }
        Self.lock.withLock { Self.wasStopped = true }
    }
}
