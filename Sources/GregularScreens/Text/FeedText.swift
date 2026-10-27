import Foundation

/// The words for feeds (README, *Feeds*), shared by every version of the
/// app and the editing page.
public enum FeedText {
    public static let title = "Feeds"
    public static let note = "Channels other people publish at a link. Follow one from Edit Channels. "
        + "When a feed changes, Get Update brings in the new version; until then, the one you have keeps playing."
    public static let none = "You don't follow any feeds."
    public static let getUpdate = "Get Update"
    public static let updatesWaiting = "A feed has an update."

    // MARK: A feed's file

    public static let notAFeed = "That isn't a Gregular TV feed."
    public static let newerVersion = "This feed was made for a newer version of Gregular TV. Update the app to follow it."
    public static let tooLarge = "That feed is larger than a feed may be (\(FeedDocument.largestFile / 1024) KB)."
    public static let needsTitle = "A feed needs a title."
    public static let titleTooLong = "Keep a feed's title and publisher to \(FeedDocument.longestTitle) characters each."
    public static let descriptionTooLong = "Keep a feed's description to \(FeedDocument.longestDescription) characters."
    public static let channelCount = "A feed has from 1 to \(FeedDocument.mostChannels) channels."
    public static let oneBlock = "A feed's channels are all in one block of ten numbers, from 20–29 to 90–99, each number once."
    public static let setTimesOnItsChannels = "A feed's set times can only be on its own channels."
    public static let badImage = "A feed's picture is a PNG of at most \(FeedDocument.largestImage / 1024) KB, "
        + "and at most \(FeedDocument.largestImageSide) pixels each way."
    public static func badTimeZone(_ zone: String) -> String { "\u{201C}\(zone)\u{201D} isn't a time zone." }
    public static func nothingToShare(_ block: Int) -> String { "You have no channels in \(block)–\(block + 9) to share." }

    // MARK: Following one

    public static let badLink = "That isn't a link the app can follow. Use one starting with https://, "
        + "or http:// only for a file on your home network."
    public static let alreadyFollowing = "You already follow that feed."
    public static let badBlock = "Feeds go in a block of ten numbers, starting at 20, 30 and so on up to 90."
    public static func blockTaken(_ block: Int) -> String { "Channels \(block)–\(block + 9) are already in use. Pick other numbers." }
    public static func inFeedBlock(_ number: Int, feed: String) -> String {
        "Channel \(number) is one of \(feed)\u{2019}s numbers. Use another, or make a copy of the feed's channel to change it."
    }

    /// What went wrong reaching a link. A browser can't say why it got no
    /// answer, which may be the host not letting web pages read it.
    public static let gone = "There's nothing at that link any more."
    public static func refused(_ status: Int) -> String { "The feed's host turned the request down (HTTP \(status))." }
    public static let redirectedAway = "That link sends the app to another site, which it won't follow."
    public static let unreachableLink = "Couldn't reach that link. Check it, and that this device is online."
    public static let unreachableInBrowser = "Couldn't reach that link from this browser. If it opens in a browser tab, "
        + "its host doesn't let web apps read it: follow it on Apple TV, or ask whoever publishes it to host it on GitHub Pages or a GitHub gist."

    // MARK: A feed in the list

    /// "Channels 70–79".
    public static func block(_ first: Int) -> String { "Channels \(first)–\(first + 9)" }
    public static let gettingIt = "Getting it\u{2026}"
    public static func expired(lastReached: String?) -> String {
        lastReached.map { "Link expired. Last reached \($0); the version you have keeps playing." }
            ?? "Link expired."
    }
    public static func unreachable(lastReached: String?) -> String {
        lastReached.map { "Couldn't check it. Last reached \($0)." } ?? "Couldn't reach it yet."
    }
    public static let upToDate = "Up to date."
    public static let updateWaiting = "Update available."
    public static let localTimes = "Set times in your own time."
    public static func timesIn(_ zone: String) -> String { "Set times in \(zone) time." }

    // MARK: What's new in an update

    public static func newChannel(_ name: String) -> String { "New channel: \(name)" }
    public static func goneChannel(_ name: String) -> String { "No longer on it: \(name)" }
    public static func changedChannel(_ name: String) -> String { "Changed: \(name)" }
    public static func renamed(_ old: String, _ new: String) -> String { "\(old) is now \(new)" }
    public static func newSetTimes(_ name: String) -> String { "New set times on \(name)" }
    public static func changedSetTimes(_ name: String) -> String { "Set times changed on \(name)" }
    public static func goneSetTimes(_ name: String) -> String { "Set times taken off \(name)" }
    public static let newDetails = "New name, description or picture"
}

extension Confirmation {
    /// Unfollowing a feed, which takes its channels and set times away.
    public static func unfollow(_ feed: String, channels: Int) -> Confirmation {
        Confirmation(
            action: "Unfollow",
            question: "Unfollow \(feed)?",
            detail: "Its \(channels == 1 ? "channel" : "\(channels) channels") and set times will be removed. "
                + "To keep one, make a copy of it first in Edit Channels.")
    }
}
