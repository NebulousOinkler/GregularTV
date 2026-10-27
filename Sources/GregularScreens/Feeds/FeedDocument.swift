import Foundation
import GregularCore

/// A feed: someone's channels and their set times, published as one file at
/// a link for others to follow (README, *Feeds*). Its channels and set times
/// are written as the editing page writes them (`EditingDocument`), with a
/// name, a line about it, an optional small picture, and the time zone its
/// set times mean.
///
/// ```json
/// { "gregularFeed": 1, "title": "Dad's Network", "publisher": "Dad",
///   "description": "Westerns all week, mysteries on Sunday nights.",
///   "timeZone": "local",
///   "channels": [{ "number": 52, "name": "Westerns", "plays": "both",
///                  "rule": { "anyOf": [{ "genre": "Western" }] } }],
///   "setTimes": [{ "channel": 52, "programmes": [{ "series": "Columbo", "at": ["20:00"], "days": ["Sun"] }] }] }
/// ```
///
/// A feed's channels are all in one block of ten numbers (50–59, say), and
/// keep their last digit wherever a follower puts the block, so they're never
/// more than ten and never move between updates. Set times may only be on
/// the feed's own channels: a feed never changes anything else. It's
/// checked as the editing page's documents are, and more strictly: a
/// stranger wrote it.
public struct FeedDocument: Codable, Sendable, Equatable {
    /// The format's version. A file of a newer one isn't read.
    public static let version = 1
    /// The most a feed file may be, in bytes.
    public static let largestFile = 256 * 1024
    public static let mostChannels = 10
    public static let longestTitle = 60
    public static let longestDescription = 300
    /// A picture is a PNG of at most this many bytes, and `largestImageSide` pixels each way.
    public static let largestImage = 32 * 1024
    public static let largestImageSide = 256
    /// `timeZone` for "the follower's own time".
    public static let localTime = "local"

    public var gregularFeed: Int
    public var title: String
    public var publisher: String?
    public var description: String?
    /// `localTime`, or an identifier such as "America/New_York".
    public var timeZone: String
    /// A PNG, in base64.
    public var image: String?
    public var channels: [EditingDocument.ChannelEntry]
    public var setTimes: [SetTimesEntry]?

    /// Set times on one of the feed's channels, in the feed's time zone.
    public struct SetTimesEntry: Codable, Sendable, Equatable {
        public var channel: Int
        public var programmes: [EditingDocument.ProgrammeEntry]
    }

    /// Why a file can't be used as a feed, in plain words.
    public typealias Problem = EditingDocument.Problem

    /// Reads and checks a feed file. Throws a `Problem` naming the first thing that's wrong.
    public static func read(_ data: Data) throws -> FeedDocument {
        guard data.count <= largestFile else { throw Problem(description: FeedText.tooLarge) }
        struct Version: Decodable { let gregularFeed: Int? }
        guard let version = (try? JSONDecoder().decode(Version.self, from: data))?.gregularFeed else {
            throw Problem(description: FeedText.notAFeed)
        }
        guard version <= Self.version else { throw Problem(description: FeedText.newerVersion) }
        let feed: FeedDocument
        do {
            feed = try JSONDecoder().decode(FeedDocument.self, from: data)
        } catch {
            throw Problem(description: "\(FeedText.notAFeed) \(EditingDocument.describe(error))")
        }
        try feed.check()
        return feed
    }

    /// The first number of the block the publisher put the channels in.
    public var publishedBlock: Int {
        (channels.first?.number ?? 0) / 10 * 10
    }

    /// The channels and set times, numbered into the block starting at
    /// `firstNumber`, with "local" set times read in `localZone`.
    public func resolved(into firstNumber: Int, localZone: TimeZone = .current) throws -> (channels: [CustomChannel], setTimes: [SetTimes]) {
        let zone = timeZone == Self.localTime ? localZone : TimeZone(identifier: timeZone)
        guard let zone else { throw Problem(description: FeedText.badTimeZone(timeZone)) }
        let place = { (number: Int) in firstNumber + number % 10 }
        let channels = try channels.map { entry in
            var channel = try entry.channel()
            channel.number = place(entry.number)
            return channel
        }
        let setTimes = try (setTimes ?? []).map { entry in
            var times = try EditingDocument.SetTimesEntry(channel: entry.channel, timeZone: zone.identifier,
                                                          programmes: entry.programmes).setTimes()
            times.channelNumber = place(entry.channel)
            return times
        }
        return (channels, setTimes)
    }

    /// The picture, if it has one and it's a PNG within the limits.
    public var imageData: Data? {
        image.flatMap { Data(base64Encoded: $0) }.flatMap { Self.isAllowedImage($0) ? $0 : nil }
    }

    /// The feed as text: pretty, with keys in a fixed order.
    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    // MARK: - Checking

    private func check() throws {
        func problem(_ text: String) -> Problem { Problem(description: text) }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw problem(FeedText.needsTitle) }
        guard title.count <= Self.longestTitle, (publisher ?? "").count <= Self.longestTitle else {
            throw problem(FeedText.titleTooLong)
        }
        guard (description ?? "").count <= Self.longestDescription else { throw problem(FeedText.descriptionTooLong) }
        guard (1...Self.mostChannels).contains(channels.count) else { throw problem(FeedText.channelCount) }
        let numbers = channels.map(\.number)
        guard Set(numbers).count == numbers.count, CustomChannel.numbers.contains(publishedBlock),
              numbers.allSatisfy({ $0 / 10 * 10 == publishedBlock }) else { throw problem(FeedText.oneBlock) }
        guard (setTimes ?? []).allSatisfy({ numbers.contains($0.channel) }) else { throw problem(FeedText.setTimesOnItsChannels) }
        guard image == nil || imageData != nil else { throw problem(FeedText.badImage) }
        // Everything else as the editing page's documents are checked: each
        // channel and set time, and all of them together in a line-up.
        let (channels, setTimes) = try resolved(into: publishedBlock)
        do {
            _ = try ChannelLineup.bundled().adding(channels, setTimes: setTimes)
        } catch {
            throw problem("\(error)")
        }
    }

    /// A PNG of at most `largestImage` bytes, and at most `largestImageSide`
    /// pixels each way, read from its header before anything decodes it.
    static func isAllowedImage(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let bytes = [UInt8](data.prefix(24))
        guard data.count <= largestImage, bytes.count == 24, Array(bytes[0..<8]) == signature,
              Array(bytes[12..<16]) == Array("IHDR".utf8) else { return false }
        let side = { (at: Int) in bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) } }
        return (1...largestImageSide).contains(side(16)) && (1...largestImageSide).contains(side(20))
    }
}

// MARK: - Making one

extension FeedDocument {
    /// What *Share as a feed* asks for.
    public struct Details: Codable, Sendable, Equatable {
        /// The first number of the block of your channels to share.
        public var block: Int
        public var title: String
        public var publisher: String?
        public var description: String?
        public var timeZone: String
        /// A PNG, in base64.
        public var image: String?
    }

    /// A feed of your channels in `details.block` and their set times,
    /// checked as any feed is. Set times are written as they were set, and
    /// read in the feed's time zone.
    public static func make(_ details: Details, channels: [CustomChannel], setTimes: [SetTimes]) throws -> FeedDocument {
        let block = details.block..<details.block + 10
        let shared = channels.filter { block.contains($0.number) }.sorted { $0.number < $1.number }
        guard !shared.isEmpty else { throw Problem(description: FeedText.nothingToShare(details.block)) }
        let numbers = Set(shared.map(\.number))
        let times = setTimes.filter { numbers.contains($0.channelNumber) }.sorted { $0.channelNumber < $1.channelNumber }
        let blank = { (text: String?) in text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil }
        let feed = FeedDocument(
            gregularFeed: version, title: details.title.trimmingCharacters(in: .whitespacesAndNewlines),
            publisher: blank(details.publisher), description: blank(details.description), timeZone: details.timeZone,
            image: blank(details.image), channels: shared.map(EditingDocument.ChannelEntry.init),
            setTimes: times.isEmpty ? nil : times.map { SetTimesEntry(channel: $0.channelNumber,
                                                                      programmes: EditingDocument.SetTimesEntry($0).programmes) })
        try feed.check()
        return feed
    }
}
