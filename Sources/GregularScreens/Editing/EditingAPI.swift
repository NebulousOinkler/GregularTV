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

/// What the editing page asks (`/api/state`, `/api/preview`, `/api/save`,
/// and for feeds `/api/feeds/look`, `/api/feeds/update` and
/// `/api/feeds/share`), answered. Its `LocalPage` answers through it once a request from the
/// home network has passed its checks; the web version, which opens the
/// same page inside itself, answers through it directly.
///
/// What's sent in is checked exactly as a channel or set-times code is
/// (`EditingDocument`, `ChannelLineup.adding`), and the page is told only
/// what the app's own editors show: the library's genre, series, tag and
/// film names, never the server's address, token or user. Looking at a feed
/// is the one request that makes the app reach out: to the feed's link,
/// through `AppModel.lookAtFeed(_:)`, under the rules every request keeps.
@MainActor public final class EditingAPI: LocalPageAPI {
    /// Saving replaces your channels and set times.
    public static let savePath = "/api/save"
    /// Getting a feed's update changes its channels.
    public static let updatePath = "/api/feeds/update"
    private static let paths: Set = ["/api/state", "/api/preview", savePath, "/api/feeds/look", updatePath, "/api/feeds/share"]
    private let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    /// Only saving and getting an update change anything on the Apple TV.
    public func changes(_ path: String) -> Bool {
        path == Self.savePath || path == Self.updatePath
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
        case ("POST", "/api/feeds/look"):
            guard let asked = try? JSONDecoder().decode(FeedLink.self, from: body) else { return .json(LocalPageFailure(FeedText.badLink), status: 422) }
            switch await app.lookAtFeed(asked.link) {
            case .success(let (link, feed)): return .json(FeedLook(link: link, feed: feed, freeBlocks: app.freeFeedBlocks))
            case .failure(let problem): return .json(LocalPageFailure(problem.description), status: 422)
            }
        case ("POST", Self.updatePath):
            guard let asked = try? JSONDecoder().decode(FeedLink.self, from: body), let link = URL(string: asked.link) else {
                return .json(LocalPageFailure(FeedText.badLink), status: 422)
            }
            if let problem = app.getUpdate(link) { return .json(LocalPageFailure(problem), status: 422) }
            return state()
        case ("POST", "/api/feeds/share"):
            do {
                let details = try JSONDecoder().decode(FeedDocument.Details.self, from: body)
                let feed = try FeedDocument.make(details, channels: app.customChannels, setTimes: app.setTimes)
                return .json(SharedFeed(file: feed.json, fileName: SharedFeed.fileName(for: feed.title)))
            } catch let problem as EditingDocument.Problem {
                return .json(LocalPageFailure(problem.description), status: 422)
            } catch {
                return .json(LocalPageFailure("That isn't what Share as a feed sends: \(EditingDocument.describe(error))"), status: 422)
            }
        case (_, let path) where Self.paths.contains(path):
            return .text(405, "Wrong method.")
        default:
            return .text(404, "Not found.")
        }
    }

    private func state() -> HTTPResponse {
        let choices = app.libraryChoices
        return .json(State(
            document: app.userChannels,
            library: .init(genres: choices.genres, series: choices.seriesNames, tags: choices.tags, studios: choices.studios,
                           films: choices.movieNames,
                           firstYear: choices.years?.lowerBound, lastYear: choices.years?.upperBound),
            channels: app.lineupChannels.map { .init(number: $0.number, name: $0.name) },
            customNumbers: .init(from: CustomChannel.numbers.lowerBound, to: CustomChannel.numbers.upperBound),
            timeZone: TimeZone.current.identifier,
            mostConditions: CustomChannel.Rule.mostConditions,
            feeds: app.feeds.map(FeedState.init),
            freeFeedBlocks: app.freeFeedBlocks))
    }

    // MARK: - What it sends

    struct State: Encodable {
        struct Library: Encodable {
            let genres, series, tags, studios, films: [String]
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
        let feeds: [FeedState]
        let freeFeedBlocks: [Int]
    }

    /// A feed followed, as the page lists it: its details, where it stands,
    /// and its channels, each with what *Make a copy* copies.
    struct FeedState: Encodable {
        struct Line: Encodable {
            let number: Int
            let name, summary: String
            let channel: EditingDocument.ChannelEntry
            let setTimes: EditingDocument.SetTimesEntry?
        }
        let link: String
        let firstNumber: Int
        let title: String
        let details: FeedDetails?
        let badge: Feed.Badge
        let status: String
        let hasUpdate: Bool
        let whatsNew: [String]
        let channels: [Line]

        init(_ feed: Feed) {
            link = feed.link.absoluteString
            firstNumber = feed.firstNumber
            title = feed.title
            details = feed.accepted.map(FeedDetails.init)
            badge = feed.badge
            status = feed.status
            hasUpdate = feed.waiting != nil
            whatsNew = feed.whatsNew
            let (channels, setTimes) = feed.lineup
            self.channels = channels.map { channel in
                Line(number: channel.number, name: channel.name, summary: channel.summary, channel: .init(channel),
                     setTimes: setTimes.first { $0.channelNumber == channel.number }.map(EditingDocument.SetTimesEntry.init))
            }
        }
    }

    /// What a feed says about itself: the publisher, a line, the picture
    /// (a checked PNG, in base64) and whose time its set times are in.
    struct FeedDetails: Encodable {
        let publisher, description, image: String?
        let times: String

        init(_ feed: FeedDocument) {
            publisher = feed.publisher
            description = feed.description
            image = feed.imageData?.base64EncodedString()
            times = feed.timeZone == FeedDocument.localTime ? FeedText.localTimes : FeedText.timesIn(feed.timeZone)
        }
    }

    struct FeedLink: Decodable {
        let link: String
    }

    /// A feed looked at before following it, like a podcast's page.
    struct FeedLook: Encodable {
        struct Line: Encodable {
            let name, summary: String
        }
        let link: String
        let title: String
        let details: FeedDetails
        let badge: Feed.Badge
        let channels: [Line]
        let freeBlocks: [Int]

        init(link: URL, feed: FeedDocument, freeBlocks: [Int]) {
            self.link = link.absoluteString
            title = feed.title
            details = FeedDetails(feed)
            badge = Feed.Badge(feed.title)
            channels = ((try? feed.resolved(into: feed.publishedBlock))?.channels ?? []).map { Line(name: $0.name, summary: $0.summary) }
            self.freeBlocks = freeBlocks
        }
    }

    /// A feed made by *Share as a feed*, for the page to save as a file.
    struct SharedFeed: Encodable {
        let file, fileName: String

        /// "dads-network.json": the title's letters and digits, joined by hyphens.
        static func fileName(for title: String) -> String {
            let words = title.lowercased().filter { $0 != "'" && $0 != "\u{2019}" }.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            return (words.isEmpty ? "feed" : words.joined(separator: "-")) + ".json"
        }
    }

    struct Preview: Encodable {
        struct Line: Encodable {
            let when, title: String
        }
        let matching: Int
        let upcoming: [Line]
    }

}
