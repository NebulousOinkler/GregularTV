import Foundation
import GregularCore

/// A feed the viewer follows: what's kept (`SavedFeed`), the version they
/// accepted, read, and what the last check found. An update the check finds
/// waits, in memory only, until the viewer gets it (*Get Update*); the next
/// launch finds it again.
public struct Feed: Identifiable, Sendable, Equatable {
    public internal(set) var saved: SavedFeed
    /// The version accepted, or nil until the first one arrives (or if the
    /// kept one can no longer be read).
    public let accepted: FeedDocument?
    /// A newer version than `accepted`, found by the last check, read and
    /// as it came (`waitingFile`).
    public private(set) var waiting: FeedDocument?
    private(set) var waitingFile: Data?
    /// The last check got no answer.
    public internal(set) var unreachable = false

    init(_ saved: SavedFeed) {
        self.saved = saved
        accepted = saved.file.flatMap { try? FeedDocument.read($0) }
    }

    /// Notes `file`, just fetched and read as `document`, as waiting if it
    /// differs from the version accepted.
    mutating func found(_ document: FeedDocument, in file: Data) {
        (waiting, waitingFile) = document == accepted ? (nil, nil) : (document, file)
    }

    public var id: URL { saved.link }
    public var link: URL { saved.link }
    public var firstNumber: Int { saved.firstNumber }
    /// The numbers it may use.
    public var numbers: ClosedRange<Int> { saved.firstNumber...saved.firstNumber + 9 }
    /// Its title, or its link's host until it has one.
    public var title: String { accepted?.title ?? saved.link.host() ?? saved.link.absoluteString }

    /// Its channels and set times, in its numbers. None until a version is accepted.
    public var lineup: (channels: [CustomChannel], setTimes: [SetTimes]) {
        (try? accepted?.resolved(into: saved.firstNumber)) ?? ([], [])
    }

    /// Where it stands, in a line: "Update available.", "Link expired. Last reached 3 Oct; …".
    public var status: String {
        let lastReached = saved.lastReached?.formatted(.dateTime.day().month(.abbreviated))
        if saved.expired { return FeedText.expired(lastReached: lastReached) }
        if waiting != nil { return FeedText.updateWaiting }
        if unreachable { return FeedText.unreachable(lastReached: lastReached) }
        return accepted == nil ? FeedText.gettingIt : FeedText.upToDate
    }

    /// What getting the update would change, a line each: "New channel: Westerns".
    public var whatsNew: [String] {
        guard let accepted, let waiting else { return [] }
        return FeedChanges.lines(from: accepted, to: waiting)
    }

    /// Its picture: a small PNG, checked (`FeedDocument.imageData`).
    public var picture: Data? { accepted?.imageData }

    /// The badge drawn when it has no picture: its initials on a colour.
    public var badge: Badge { Badge(title) }

    /// A feed's badge: up to two initials, and a hue (0–359) picked from
    /// the title, the same on every device.
    public struct Badge: Sendable, Equatable, Encodable {
        public let initials: String
        public let hue: Int

        init(_ title: String) {
            let words = title.split(whereSeparator: \.isWhitespace)
            initials = String(words.compactMap { $0.first { $0.isLetter || $0.isNumber } }.prefix(2)).uppercased()
            // FNV-1a over the title's bytes: stable everywhere, unlike `hashValue`.
            let hash = title.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
            hue = Int(hash % 360)
        }
    }
}

/// The lines saying what a feed's update changes.
enum FeedChanges {
    static func lines(from old: FeedDocument, to new: FeedDocument) -> [String] {
        var lines: [String] = []
        if old.title != new.title || old.publisher != new.publisher || old.description != new.description || old.image != new.image {
            lines.append(FeedText.newDetails)
        }
        // Channels are matched by their place in the block, which never moves.
        let place = { (number: Int) in number % 10 }
        let oldChannels = Dictionary(old.channels.map { (place($0.number), $0) }, uniquingKeysWith: { first, _ in first })
        let newChannels = Dictionary(new.channels.map { (place($0.number), $0) }, uniquingKeysWith: { first, _ in first })
        let times = { (feed: FeedDocument, slot: Int) in
            (feed.setTimes ?? []).filter { place($0.channel) == slot }.flatMap(\.programmes)
        }
        let zoneChanged = old.timeZone != new.timeZone
        for slot in Set(oldChannels.keys).union(newChannels.keys).sorted() {
            switch (oldChannels[slot], newChannels[slot]) {
            case (nil, let added?):
                lines.append(FeedText.newChannel(added.name))
                continue
            case (let removed?, nil):
                lines.append(FeedText.goneChannel(removed.name))
                continue
            case (let was?, let now?):
                if was.name != now.name { lines.append(FeedText.renamed(was.name, now.name)) }
                var unnamed = was, renamed = now
                (unnamed.name, unnamed.number, renamed.number) = (now.name, 0, 0)
                if unnamed != renamed { lines.append(FeedText.changedChannel(now.name)) }
                let (before, after) = (times(old, slot), times(new, slot))
                switch (before.isEmpty, after.isEmpty) {
                case (true, false): lines.append(FeedText.newSetTimes(now.name))
                case (false, true): lines.append(FeedText.goneSetTimes(now.name))
                case (false, false) where before != after || zoneChanged: lines.append(FeedText.changedSetTimes(now.name))
                default: break
                }
            case (nil, nil):
                continue
            }
        }
        return lines
    }
}

/// Why a link couldn't be used, in plain words. `isGone`: what's there
/// will never be a usable feed (it's gone, too large, or not a feed), so a
/// followed feed's link is marked expired.
public struct LinkProblem: Error, Equatable, CustomStringConvertible {
    public let description: String
    let isGone: Bool
}
