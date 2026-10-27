import Foundation
import GregularCore

/// Feeds: other people's channels, followed by link (README, *Feeds*). The
/// first version of a feed is taken when it's followed; after that, a
/// newer one waits until the viewer gets it (`getUpdate(_:)`). A feed's
/// channels and set times take the block of ten numbers the viewer gave it,
/// and nothing else of theirs is touched.
extension AppModel {
    /// How many feeds looked at are kept to follow without fetching again:
    /// a few, so looking at one after another (anyone with the editing
    /// page's code can ask) can't fill memory.
    static let mostFeedsLookedAt = 4

    /// How often the feeds are checked while the app runs (and once when it opens).
    public static let feedCheckInterval = Duration.seconds(6 * 3600)

    /// The blocks a feed may take: 20, 30, … 90, within the custom channel numbers.
    static let feedBlocks = Array(stride(from: CustomChannel.numbers.lowerBound, through: CustomChannel.numbers.upperBound - 9, by: 10))

    /// Every feed's channels and set times, in their numbers.
    var feedLineup: (channels: [CustomChannel], setTimes: [SetTimes]) {
        feeds.map(\.lineup).reduce(into: ([], [])) { all, feed in
            all.channels += feed.channels
            all.setTimes += feed.setTimes
        }
    }

    /// The feed whose numbers include `number`, if any.
    public func feed(owning number: Int) -> Feed? {
        feeds.first { $0.numbers.contains(number) }
    }

    /// Whether a feed has an update waiting: Settings shows a dot.
    public var hasFeedUpdates: Bool {
        feeds.contains { $0.waiting != nil }
    }

    /// The blocks a new feed could take: none of your own channels or set
    /// times are in them, and no feed has them.
    public var freeFeedBlocks: [Int] {
        let used = customChannels.map(\.number) + setTimes.map(\.channelNumber)
        return Self.feedBlocks.filter { block in
            feed(owning: block) == nil && !used.contains { (block...block + 9).contains($0) }
        }
    }

    /// What the viewer typed or pasted as a link, if the app may fetch it:
    /// https is assumed when it says nothing.
    func feedLink(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = URL(string: text.contains("://") ? text : "https://" + text), access.mayFetch(link) else { return nil }
        return link
    }

    /// Fetches the feed at `text` to show before following it, and keeps it
    /// a while, so following it doesn't fetch it again.
    public func lookAtFeed(_ text: String) async -> Result<(link: URL, feed: FeedDocument), LinkProblem> {
        guard let link = feedLink(text) else { return .failure(LinkProblem(description: FeedText.badLink, isGone: false)) }
        guard !feeds.contains(where: { $0.link == link }) else {
            return .failure(LinkProblem(description: FeedText.alreadyFollowing, isGone: false))
        }
        switch await fetchFeed(link) {
        case .success(let (feed, file)):
            lookedAtFeeds = (lookedAtFeeds.filter { $0.link != link } + [(link, file)]).suffix(Self.mostFeedsLookedAt)
            return .success((link, feed))
        case .failure(let problem):
            return .failure(problem)
        }
    }

    /// The feeds `entries` list, in their order: ones already followed keep
    /// what they have (in the numbers given now), and new ones start with
    /// the version just looked at, if there is one. Throws if a link can't
    /// be followed, or two feeds share a block.
    func following(_ entries: [EditingDocument.FeedEntry]) throws -> [Feed] {
        var feeds: [Feed] = []
        for entry in entries {
            guard let link = feedLink(entry.link) else { throw EditingDocument.Problem(description: FeedText.badLink) }
            guard Self.feedBlocks.contains(entry.firstNumber) else { throw EditingDocument.Problem(description: FeedText.badBlock) }
            guard !feeds.contains(where: { $0.link == link }) else { throw EditingDocument.Problem(description: FeedText.alreadyFollowing) }
            guard !feeds.contains(where: { $0.firstNumber == entry.firstNumber }) else {
                throw EditingDocument.Problem(description: FeedText.blockTaken(entry.firstNumber))
            }
            if var feed = self.feeds.first(where: { $0.link == link }) {
                feed.saved.firstNumber = entry.firstNumber
                feeds.append(feed)
            } else {
                let file = lookedAtFeeds.last { $0.link == link }?.file
                feeds.append(Feed(SavedFeed(link: link, firstNumber: entry.firstNumber, file: file, lastReached: file.map { _ in .now })))
            }
        }
        return feeds
    }

    /// Checks every feed: one never yet fetched takes what it finds; any
    /// other notes an update as waiting. A link that's gone is marked
    /// expired, and its feed keeps playing the version accepted.
    public func checkFeeds() async {
        for link in feeds.map(\.link) {
            let outcome = await fetchFeed(link)
            // Unfollowed while it was fetched.
            guard let index = feeds.firstIndex(where: { $0.link == link }) else { continue }
            var feed = feeds[index]
            switch outcome {
            case .success(let (document, file)):
                feed.saved.lastReached = .now
                feed.saved.expired = false
                feed.unreachable = false
                if feed.accepted == nil {
                    feed.saved.file = file
                    feed = Feed(feed.saved)
                } else {
                    feed.found(document, in: file)
                }
            case .failure(let problem):
                feed.saved.expired = problem.isGone
                feed.unreachable = !problem.isGone
            }
            var all = feeds
            all[index] = feed
            if all[index].accepted != feeds[index].accepted {
                apply(custom: customChannels, setTimes: setTimes, feeds: all)
            } else {
                feeds = all
                preferences.feeds = all.map(\.saved)
            }
        }
    }

    /// Takes the update waiting for the feed at `link`. Returns why it
    /// couldn't, or nil.
    @discardableResult
    public func getUpdate(_ link: URL) -> String? {
        guard let index = feeds.firstIndex(where: { $0.link == link }), let file = feeds[index].waitingFile else { return nil }
        var all = feeds
        var saved = all[index].saved
        saved.file = file
        all[index] = Feed(saved)
        return apply(custom: customChannels, setTimes: setTimes, feeds: all)
    }

    /// Stops following the feed at `link`: its channels and set times go.
    public func unfollow(_ link: URL) {
        apply(custom: customChannels, setTimes: setTimes, feeds: feeds.filter { $0.link != link })
    }

    /// Checks the feeds now, then every `checksFeedsEvery` while the app runs.
    func startCheckingFeeds() {
        feedChecks?.cancel()
        let interval = checksFeedsEvery
        feedChecks = Task { [weak self] in
            while !Task.isCancelled {
                // Held only while checking, not while waiting for the next time.
                guard let app = self else { return }
                await app.checkFeeds()
                _ = consume app
                guard let interval else { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// The feed at `link`, fetched and read.
    private func fetchFeed(_ link: URL) async -> Result<(FeedDocument, Data), LinkProblem> {
        do {
            let file = try await access.publishedFile(at: link, largest: FeedDocument.largestFile)
            return .success((try FeedDocument.read(file), file))
        } catch let problem as LinkProblem {
            return .failure(problem)
        } catch let problem as EditingDocument.Problem {
            return .failure(LinkProblem(description: problem.description, isGone: true))
        } catch {
            return .failure(LinkProblem(description: FeedText.unreachableLink, isGone: false))
        }
    }
}
