import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// The editing page: its HTTP, its JSON, and what it lets through.
@MainActor
struct EditingPageTests {
    static let host = "192.168.1.20:8080"

    private func request(_ path: String, method: String = "GET", host: String = host, code: String? = nil,
                         origin: String? = nil, body: String = "") -> HTTPRequest {
        var text = "\(method) \(path) HTTP/1.1\r\nHost: \(host)\r\n"
        if let code { text += "X-Gregular-Code: \(code)\r\n" }
        if let origin { text += "Origin: \(origin)\r\n" }
        text += "Content-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard case .complete(let request) = HTTPRequest.parse(Data(text.utf8)) else { preconditionFailure("Didn't parse") }
        return request
    }

    private func app() -> AppModel {
        AppModel(deviceName: "Test Device", store: InMemoryCredentialStore(), preferences: Fixture.preferences(), makeDecks: FakeDeck.pair)
    }

    private func page(_ app: AppModel) -> EditingPage {
        EditingPage(app: app, hosts: [Self.host], code: "123456")
    }

    // MARK: HTTP

    @Test func requestsAreReadWholeAndCapped() {
        #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: a".utf8)) == .incomplete)
        #expect(HTTPRequest.parse(Data("POST /api/save HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc".utf8)) == .incomplete)
        guard case .complete(let request) = HTTPRequest.parse(Data("POST /api/save?x=1 HTTP/1.1\r\nHOST: a\r\nContent-Length: 3\r\n\r\nabc".utf8)) else {
            Issue.record("Should parse"); return
        }
        #expect(request.method == "POST" && request.path == "/api/save" && request.headers["host"] == "a" && request.body == Data("abc".utf8))
        #expect(HTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: \(HTTPRequest.longestBody + 1)\r\n\r\n".utf8)) == .invalid(413))
        #expect(HTTPRequest.parse(Data(String(repeating: "a", count: HTTPRequest.longestHead + 1).utf8)) == .invalid(431))
        #expect(HTTPRequest.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) == .invalid(501))
        #expect(HTTPRequest.parse(Data("GARBAGE\r\n\r\n".utf8)) == .invalid(400))
        #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n".utf8)) == .invalid(400), "A repeated header is refused")
    }

    @Test func responsesAreLockedDown() {
        let head = String(decoding: HTTPResponse.text(200, "hi").serialized, as: UTF8.self)
        for header in ["Cache-Control: no-store", "Referrer-Policy: no-referrer", "X-Content-Type-Options: nosniff",
                       "Content-Security-Policy: default-src 'none'", "connect-src 'self'", "Connection: close", "Content-Length: 2"] {
            #expect(head.contains(header), "\(header)")
        }
    }

    // MARK: Who may ask

    @Test func onlyTheAddressShownAndTheCodeGetIn() async {
        let page = page(app())
        #expect(await page.handle(request("/")).status == 200, "The page itself holds nothing, so needs no code")
        #expect(await page.handle(request("/", host: "evil.example:8080")).status == 403, "Another host name (DNS rebinding)")
        #expect(await page.handle(request("/api/state", code: "123456", origin: "http://evil.example")).status == 403, "Another site")
        #expect(await page.handle(request("/api/state")).status == 401)
        #expect(await page.handle(request("/api/state", code: "123456", origin: "http://\(Self.host)")).status == 200)
    }

    @Test func wrongCodesLockThePage() async {
        let page = page(app())
        for _ in 0..<EditingPage.mostWrongCodes {
            #expect(await page.handle(request("/api/state", code: "000000")).status == 401)
        }
        #expect(page.isLocked)
        #expect(await page.handle(request("/api/state", code: "123456")).status == 423, "Even the right code, once locked")
        #expect(EditingPage(app: app(), hosts: []).code.count == 6)
    }

    @Test func onlyTheHomeNetworkMayConnect() {
        for local in ["192.168.1.20", "10.0.0.5", "172.16.0.1", "172.31.255.255", "169.254.3.4", "127.0.0.1",
                      "::1", "fe80::1%en0", "fd12:3456::1", "::ffff:192.168.1.20"] {
            #expect(EditingPage.isLocal(local), "\(local)")
        }
        for remote in ["8.8.8.8", "172.32.0.1", "100.64.0.1", "2001:4860::8888", "::ffff:8.8.8.8", "", "example.com"] {
            #expect(!EditingPage.isLocal(remote), "\(remote)")
        }
    }

    // MARK: Saving

    static let document = """
    { "channels": [
        { "number": 30, "name": "Laughs", "plays": "both",
          "rule": { "anyOf": [{ "genre": "Comedy" }, { "series": "Taskmaster" }], "noneOf": [{ "tag": "Christmas" }] } } ],
      "setTimes": [
        { "channel": 30, "timeZone": "America/New_York",
          "programmes": [{ "series": "Taskmaster", "at": ["18:00", "18:30"], "days": ["Mon", "Feb 2"] }] } ] }
    """

    @Test func savingReplacesYourChannelsAndSetTimes() async throws {
        let app = app()
        let page = page(app)
        let response = await page.handle(request("/api/save", method: "POST", code: "123456", body: Self.document))
        #expect(response.status == 200)
        #expect(page.lastSaved != nil)
        let channel = try #require(app.customChannels.first)
        #expect(channel.name == "Laughs" && channel.rule.summary == "Comedy or Taskmaster, not Christmas")
        #expect(app.setTimes.first?.programmes.first?.days == ["Mon", "Feb 2"])
        #expect(app.setTimes.first?.timeZone.identifier == "America/New_York")
        // What's saved reads back as the same document.
        let saved = try EditingDocument.read(Data(Self.document.utf8))
        #expect(app.userChannels.channels.map(\.name) == saved.channels.map(\.name))
        #expect(try app.userChannels.resolved().channels == saved.resolved().channels)
    }

    @Test func aBadDocumentSaysWhatsWrongAndChangesNothing() async {
        let app = app()
        let page = page(app)
        for (body, problem) in [
            ("{", "That isn't a channels document"),
            (#"{ "channels": [{ "number": 30, "name": "", "plays": "both", "rule": {} }], "setTimes": [] }"#, "Channel 30 needs a name."),
            (#"{ "channels": [{ "number": 30, "name": "X", "plays": "all", "rule": {} }], "setTimes": [] }"#, "Channel 30: \\\"plays\\\" is"),
            (#"{ "channels": [{ "number": 5, "name": "X", "plays": "both", "rule": {} }], "setTimes": [] }"#, "Custom channels are numbered 20 to 99."),
            (#"{ "channels": [{ "number": 30, "name": "X", "plays": "both", "rule": { "anyOf": [{ "genre": "A", "tag": "B" }] } }], "setTimes": [] }"#, "each condition is one"),
            (#"{ "channels": [], "setTimes": [{ "channel": 1, "timeZone": "Mars/Base", "programmes": [] }] }"#, "isn't a time zone"),
            (#"{ "channels": [], "setTimes": [{ "channel": 1, "timeZone": "UTC", "programmes": [{ "series": "A", "at": ["25:00"] }] }] }"#, "isn't a time like"),
        ] {
            let response = await page.handle(request("/api/save", method: "POST", code: "123456", body: body))
            #expect(response.status == 422, "\(body)")
            #expect(String(decoding: response.body, as: UTF8.self).contains(problem), "\(String(decoding: response.body, as: UTF8.self))")
        }
        #expect(app.customChannels.isEmpty && app.setTimes.isEmpty)
    }

    @Test func thePageShowsLibraryNamesOnlyAsText() {
        // Names come from the server: the page must never put them in as HTML.
        #expect(!EditingPageHTML.page.contains("innerHTML") && !EditingPageHTML.page.contains("outerHTML")
                && !EditingPageHTML.page.contains("insertAdjacentHTML") && !EditingPageHTML.page.contains("document.write"))
        #expect(!EditingPageHTML.page.contains("http://") && !EditingPageHTML.page.contains("https://"), "Nothing fetched from elsewhere")
    }
}
