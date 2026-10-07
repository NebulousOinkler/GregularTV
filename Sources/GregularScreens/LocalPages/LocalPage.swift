import Foundation
import Observation

/// A page that phones and computers on the home network open, served by
/// the Apple TV while it's wanted (the app's `LocalPageServer`): the
/// editing page (`LocalPage.editing`), karaoke's song picker
/// (`LocalPage.songPicker`). It draws nothing itself: `handle(_:from:)`
/// answers requests, and the Apple TV's screen shows `code` and whether
/// it's locked.
///
/// **What it guards against.** Anything on the home network can reach the
/// port while it's open, so:
/// - only connections from the home network are read (`LocalNetwork`:
///   private, link-local and loopback addresses);
/// - every request for data needs the one-time `code` shown on the TV,
///   compared in constant time. A device that gets it wrong
///   `mostWrongCodes` times is refused, and after `mostWrongCodesInAll`
///   wrong ones from anywhere the page locks until it's closed and opened
///   again: one device can't lock everyone out, and guessing stays hopeless
///   (20 tries at a million codes);
/// - the `Host` header must be an address this Apple TV is being reached
///   at, and any `Origin` must match it, so another web page can't use the
///   browser to reach it (DNS rebinding, cross-site requests);
/// - only then is it answered, by its `LocalPageAPI`, which checks what's
///   sent in and tells the page only what it needs, never the server's
///   address, token or user.
///
/// It's plain http, so on a network you don't trust, others there could see
/// the code and what the page shows. The Apple TV screen says so.
@MainActor @Observable
public final class LocalPage {
    /// Six digits, new each time the page opens.
    public let code: String
    /// Wrong codes one device may send before it's refused, and from all
    /// devices before the page locks.
    public static let mostWrongCodes = 5
    public static let mostWrongCodesInAll = 20
    public private(set) var isLocked = false
    /// When a phone or computer last changed something on the Apple TV
    /// (saved its channels, queued a song), for the TV to say so.
    public private(set) var lastChange: Date?

    /// The page itself, one self-contained file (`LocalPageHTML`).
    private let html: String
    private let api: any LocalPageAPI
    /// Wrong codes so far, by the address they came from.
    private var wrongCodes: [String: Int] = [:]
    /// The `Host` values a request may carry: this Apple TV's addresses, with the port.
    private let hosts: Set<String>

    public init(html: String, api: any LocalPageAPI, hosts: Set<String>, code: String? = nil) {
        self.html = html
        self.api = api
        self.hosts = hosts
        self.code = code ?? String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    /// The answer to one request, from the device at `address`.
    public func handle(_ request: HTTPRequest, from address: String) async -> HTTPResponse {
        guard let host = request.headers["host"], hosts.contains(host.lowercased()) else {
            return .text(403, "Open the address shown on the Apple TV.")
        }
        if let origin = request.headers["origin"], origin.lowercased() != "http://\(host.lowercased())" {
            return .text(403, "Requests come from the page only.")
        }
        switch (request.method, request.path) {
        case ("GET", "/"):
            return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8))
        case (_, "/"):
            return .text(405, "Use GET.")
        case (let method, let path) where path.hasPrefix("/api/"):
            if let refused = checkCode(request, from: address) { return refused }
            let response = await api.answer(method, path, request.body)
            if api.changes(path), response.status == 200 { lastChange = .now }
            return response
        default:
            return .text(404, "Not found.")
        }
    }

    private func checkCode(_ request: HTTPRequest, from address: String) -> HTTPResponse? {
        let tooMany = "Turn the page off and on again on the Apple TV for a new code."
        guard !isLocked else { return .json(LocalPageFailure("Too many wrong codes. \(tooMany)"), status: 423) }
        guard wrongCodes[address, default: 0] < Self.mostWrongCodes else {
            return .json(LocalPageFailure("Too many wrong codes from this device. \(tooMany)"), status: 423)
        }
        guard Self.same(request.headers["x-gregular-code"] ?? "", code) else {
            wrongCodes[address, default: 0] += 1
            if wrongCodes.values.reduce(0, +) >= Self.mostWrongCodesInAll { isLocked = true }
            return .json(LocalPageFailure("That isn't the code on the Apple TV."), status: 401)
        }
        return nil
    }

    /// Compares in time that doesn't depend on where they differ.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// What a `LocalPage` answers at `/api/…`, once a request has passed its checks.
@MainActor public protocol LocalPageAPI: AnyObject {
    func answer(_ method: String, _ path: String, _ body: Data) async -> HTTPResponse
    /// Whether a request to `path` that succeeds changes something on the Apple TV.
    func changes(_ path: String) -> Bool
}

/// What a page is told when its request can't be done: `{ "error": "…" }`.
public struct LocalPageFailure: Encodable, Sendable {
    let error: String
    public init(_ error: String) { self.error = error }
}
