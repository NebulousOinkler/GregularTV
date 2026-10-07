import Foundation
import GregularCore

extension LocalPage {
    /// The editing page: your channels and set times, edited from a phone or
    /// computer browser on the home network instead of with the remote. It's
    /// off unless "Edit from a phone or computer" is on in Settings, and even
    /// then only answers while its screen is open on the Apple TV.
    public static func editing(app: AppModel, hosts: Set<String>, code: String? = nil) -> LocalPage {
        LocalPage(html: EditingPageHTML.page, api: EditingAPI(app: app), hosts: hosts, code: code)
    }
}

/// What the editing page asks (`/api/state`, `/api/preview`, `/api/save`),
/// answered. Its `LocalPage` answers through it once a request from the
/// home network has passed its checks; the web version, which opens the
/// same page inside itself, answers through it directly.
///
/// What's sent in is checked exactly as a channel or set-times code is
/// (`EditingDocument`, `ChannelLineup.adding`), and the page is told only
/// what the app's own editors show: the library's genre, series, tag and
/// film names, never the server's address, token or user.
@MainActor public final class EditingAPI: LocalPageAPI {
    /// Saving replaces your channels and set times.
    public static let savePath = "/api/save"
    private let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    /// Only saving changes anything on the Apple TV.
    public func changes(_ path: String) -> Bool {
        path == Self.savePath
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
                return .json(LocalPageFailure(problem.description), status: 422)
            } catch {
                return .json(LocalPageFailure("That isn't a channel: \(EditingDocument.describe(error))"), status: 422)
            }
        case ("POST", Self.savePath):
            do {
                let document = try EditingDocument.read(body)
                if let problem = app.replaceUserChannels(with: document) { return .json(LocalPageFailure(problem), status: 422) }
                return state()
            } catch {
                return .json(LocalPageFailure("\(error)"), status: 422)
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

}
