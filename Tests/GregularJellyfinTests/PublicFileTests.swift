import Foundation
import Testing
@testable import GregularJellyfin

/// `PublicFile`: a published file is fetched under the same rules as the
/// media server's replies, and the host learns as little as possible.
struct PublicFileTests {
    /// Answers every request with `status` and `body`, from `answeredFrom`
    /// if given, and keeps what it was asked.
    private final class Host: HTTPTransport, @unchecked Sendable {
        var status = 200
        var body = Data("{}".utf8)
        var answeredFrom: URL?
        var failure: (any Error)?
        private(set) var requests: [ServerRequest] = []

        func send(_ request: ServerRequest) async throws -> ServerReply {
            requests.append(request)
            if let failure { throw failure }
            return ServerReply(url: answeredFrom ?? request.url, status: status, body: body)
        }
    }

    private let link = URL(string: "https://feeds.example/dad.json")!

    @Test func itAsksForTheFileAndSaysNothingAboutTheViewer() async throws {
        let host = Host()
        let data = try await PublicFile(transport: host).fetch(link, largest: 1000)
        #expect(data == Data("{}".utf8))
        let request = try #require(host.requests.first)
        #expect(request.method == "GET")
        #expect(request.url == link)
        #expect(request.body == nil)
        #expect(request.largestResponse == 1000)
        #expect(request.headers == ["Accept": "application/json", "Accept-Language": "*", "User-Agent": "GregularTV"])
    }

    @Test(arguments: [
        ("https://feeds.example/a.json", true),
        ("http://nas.local/a.json", true),               // plain http on the home network,
        ("http://192.168.1.5:8000/a.json", true),
        ("http://feeds.example/a.json", false),          // never beyond it
        ("http://nas/a.json", false),                    // nor to a one-word name
        ("https://dad:secret@feeds.example/a.json", false),
        ("ftp://feeds.example/a.json", false),
        ("file:///etc/passwd", false),
    ])
    func onlyLinksTheAppMayFetch(link: String, allowed: Bool) async {
        let host = Host()
        let fetched = (try? await PublicFile(transport: host).fetch(URL(string: link)!, largest: 1000)) != nil
        #expect(fetched == allowed)
        #expect(host.requests.isEmpty == !allowed)
    }

    @Test(arguments: [(404, PublicFile.Failure.gone), (410, .gone), (500, .refused(status: 500)), (403, .refused(status: 403))])
    func whatAnErrorMeans(status: Int, failure: PublicFile.Failure) async {
        let host = Host()
        host.status = status
        await #expect(throws: failure) { try await PublicFile(transport: host).fetch(link, largest: 1000) }
    }

    @Test func aReplyFromElsewhereIsNeverUsed() async {
        let host = Host()
        host.answeredFrom = URL(string: "https://elsewhere.example/dad.json")
        await #expect(throws: PublicFile.Failure.redirectedAway) { try await PublicFile(transport: host).fetch(link, largest: 1000) }
    }

    @Test func aReplyTooLargeIsNeverUsed() async {
        let host = Host()
        host.body = Data(repeating: 0x20, count: 1001)
        await #expect(throws: PublicFile.Failure.tooLarge) { try await PublicFile(transport: host).fetch(link, largest: 1000) }
        host.body = Data()
        host.failure = JellyfinError.responseTooLarge
        await #expect(throws: PublicFile.Failure.tooLarge) { try await PublicFile(transport: host).fetch(link, largest: 1000) }
    }

    @Test func noAnswerIsUnreachable() async {
        let host = Host()
        host.failure = URLError(.notConnectedToInternet)
        await #expect(throws: PublicFile.Failure.unreachable(maybeNotAllowed: false)) { try await PublicFile(transport: host).fetch(link, largest: 1000) }
    }
}
