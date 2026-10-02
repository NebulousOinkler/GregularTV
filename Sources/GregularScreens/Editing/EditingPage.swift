import Foundation
import GregularCore
import Observation

/// The editing page: your channels and set times, edited from a phone or
/// computer browser on the home network instead of with the remote. It's
/// off unless "Edit from a phone or computer" is on in Settings, and even
/// then only answers while its screen is open on the Apple TV (the app's
/// `EditingServer` listens only then, and only on the local network).
///
/// **What it guards against.** Anything on the home network can reach the
/// port while it's open, so:
/// - every request for data needs the one-time `code` shown on the TV,
///   compared in constant time. A device that gets it wrong
///   `mostWrongCodes` times is refused, and after `mostWrongCodesInAll`
///   wrong ones from anywhere the page locks until it's closed and opened
///   again: one device can't lock everyone out, and guessing stays hopeless
///   (20 tries at a million codes);
/// - the `Host` header must be an address this Apple TV is being reached
///   at, and any `Origin` must match it, so another web page can't use the
///   browser to reach it (DNS rebinding, cross-site requests);
/// - only then is it answered, by `EditingAPI`, which checks what's sent
///   in and tells the page only the library's genre, series, tag and film
///   names, never the server's address, token or user.
///
/// It's plain http, so on a network you don't trust, others there could see
/// the code and the names. The Apple TV screen says so.
///
/// It draws nothing itself: `handle(_:from:)` answers requests, and the
/// Apple TV screen shows `code` and whether it's locked.
@MainActor @Observable
public final class EditingPage {
    /// Six digits, new each time the page opens.
    public let code: String
    /// Wrong codes one device may send before it's refused, and from all
    /// devices before the page locks.
    public static let mostWrongCodes = 5
    public static let mostWrongCodesInAll = 20
    public private(set) var isLocked = false
    /// When the page last saved, for the TV screen to say so.
    public private(set) var lastSaved: Date?

    /// Wrong codes so far, by the address they came from.
    private var wrongCodes: [String: Int] = [:]
    private let api: EditingAPI
    /// The `Host` values a request may carry: this Apple TV's addresses, with the port.
    private let hosts: Set<String>

    public init(app: AppModel, hosts: Set<String>, code: String? = nil) {
        api = EditingAPI(app: app)
        self.hosts = hosts
        self.code = code ?? String(format: "%06d", Int.random(in: 0..<1_000_000))
    }

    /// The answer to one request, from the device at `address`.
    public func handle(_ request: HTTPRequest, from address: String) async -> HTTPResponse {
        guard let host = request.headers["host"], hosts.contains(host.lowercased()) else {
            return .text(403, "Open the address shown on the Apple TV.")
        }
        if let origin = request.headers["origin"], origin.lowercased() != "http://\(host.lowercased())" {
            return .text(403, "Requests come from the editing page only.")
        }
        switch (request.method, request.path) {
        case ("GET", "/"):
            return HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(EditingPageHTML.page.utf8))
        case (_, "/"):
            return .text(405, "Use GET.")
        case (let method, let path) where path.hasPrefix("/api/"):
            if let refused = checkCode(request, from: address) { return refused }
            let response = await api.answer(method, path, request.body)
            if path == EditingAPI.savePath, response.status == 200 { lastSaved = .now }
            return response
        default:
            return .text(404, "Not found.")
        }
    }

    private func checkCode(_ request: HTTPRequest, from address: String) -> HTTPResponse? {
        let tooMany = "Close the editing screen on the Apple TV and open it again for a new code."
        guard !isLocked else { return .json(EditingAPI.Failure("Too many wrong codes. \(tooMany)"), status: 423) }
        guard wrongCodes[address, default: 0] < Self.mostWrongCodes else {
            return .json(EditingAPI.Failure("Too many wrong codes from this device. \(tooMany)"), status: 423)
        }
        guard Self.same(request.headers["x-gregular-code"] ?? "", code) else {
            wrongCodes[address, default: 0] += 1
            if wrongCodes.values.reduce(0, +) >= Self.mostWrongCodesInAll { isLocked = true }
            return .json(EditingAPI.Failure("That isn't the code on the Apple TV."), status: 401)
        }
        return nil
    }

    /// Whether a connection from `address` (as text, IPv4 or IPv6) comes from
    /// the home network: a private, link-local or loopback address. Anything
    /// else is refused before it's read.
    public nonisolated static func isLocal(_ address: String) -> Bool {
        var text = address.lowercased()
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }   // fe80::1%en0
        if text.hasPrefix("::ffff:") { text = String(text.dropFirst(7)) }       // IPv4 mapped into IPv6
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).compactMap { UInt8($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        guard text.contains(":") else { return false }
        if text == "::1" { return true }
        let first = UInt16(text.split(separator: ":", omittingEmptySubsequences: false).first.flatMap { UInt16($0, radix: 16) } ?? 0)
        return first & 0xFE00 == 0xFC00 || first & 0xFFC0 == 0xFE80   // fc00::/7 unique local, fe80::/10 link-local
    }

    /// Compares in time that doesn't depend on where they differ.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

/// What the editing page asks (`/api/state`, `/api/preview`, `/api/save`),
/// answered. `EditingPage` answers through it once a request from the home
/// network has passed its checks; the web version, which opens the same
/// page inside itself, answers through it directly.
///
/// What's sent in is checked exactly as a channel or set-times code is
/// (`EditingDocument`, `ChannelLineup.adding`), and the page is told only
/// what the app's own editors show: the library's genre, series, tag and
/// film names, never the server's address, token or user.
@MainActor public final class EditingAPI {
    /// Saving replaces your channels and set times.
    public static let savePath = "/api/save"
    private let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public func answer(_ method: String, _ path: String, _ body: Data) async -> HTTPResponse {
        switch (method, path) {
        case ("GET", "/api/state"):
            return state()
        case ("POST", "/api/preview"):
            do {
                let entry = try JSONDecoder().decode(EditingDocument.ChannelEntry.self, from: body)
                let channel = try entry.channel()
                let (matching, upcoming) = await app.preview(channel)
                return .json(Preview(matching: matching, upcoming: upcoming.map { Preview.Line(when: $0.when, title: $0.title) }))
            } catch let problem as EditingDocument.Problem {
                return .json(Failure(problem.description), status: 422)
            } catch {
                return .json(Failure("That isn't a channel: \(EditingDocument.describe(error))"), status: 422)
            }
        case ("POST", Self.savePath):
            do {
                let document = try EditingDocument.read(body)
                if let problem = app.replaceUserChannels(with: document) { return .json(Failure(problem), status: 422) }
                return state()
            } catch {
                return .json(Failure("\(error)"), status: 422)
            }
        case (_, "/api/state"), (_, "/api/preview"), (_, "/api/save"):
            return .text(405, "Wrong method.")
        default:
            return .text(404, "Not found.")
        }
    }

    private func state() -> HTTPResponse {
        let choices = app.libraryChoices
        return .json(State(
            document: app.userChannels,
            library: .init(genres: choices.genres, series: choices.seriesNames, tags: choices.tags, films: choices.movieNames,
                           firstYear: choices.years?.lowerBound, lastYear: choices.years?.upperBound),
            channels: app.lineupChannels.map { .init(number: $0.number, name: $0.name) },
            customNumbers: .init(from: CustomChannel.numbers.lowerBound, to: CustomChannel.numbers.upperBound),
            timeZone: TimeZone.current.identifier,
            mostConditions: CustomChannel.Rule.mostConditions))
    }

    // MARK: - What it sends

    struct State: Encodable {
        struct Library: Encodable {
            let genres, series, tags, films: [String]
            let firstYear, lastYear: Int?
        }
        struct ChannelName: Encodable {
            let number: Int
            let name: String
        }
        struct Range: Encodable {
            let from, to: Int
        }
        let document: EditingDocument
        let library: Library
        let channels: [ChannelName]
        let customNumbers: Range
        let timeZone: String
        let mostConditions: Int
    }

    struct Preview: Encodable {
        struct Line: Encodable {
            let when, title: String
        }
        let matching: Int
        let upcoming: [Line]
    }

    struct Failure: Encodable {
        let error: String
        init(_ error: String) { self.error = error }
    }
}
