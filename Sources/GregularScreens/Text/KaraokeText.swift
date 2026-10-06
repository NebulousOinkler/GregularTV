import GregularCore

/// Karaoke's words, shared by every version of the app. Plain text, like
/// all of GregularScreens' (a web front end escapes it).
public enum KaraokeText {
    public static let karaoke = "Karaoke"
    public static let pickATheme = "Pick a Theme"
    public static let pickASong = "Pick a song!"
    public static let anyButton = "Press any button"
    public static let getReady = "Get ready!"
    public static let pressPlay = "Press Play to sing"
    public static let upNext = "Up next"
    public static let noLyrics = "No lyrics"
    public static let video = "Video"
    public static let unknownArtist = "Unknown Artist"
    public static let otherSongs = "Other Songs"
    public static let searchPrompt = "Song, artist or album"
    public static let nothingFound = "No songs match."
    public static let emptyQueue = "No songs in the queue yet."
    public static let noSongs = "There are no songs here that play on this device."

    public static func songCount(_ count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    /// Said when a song joins the queue while another plays.
    public static func queued(_ song: Songbook.Song, place: Int) -> String {
        "\u{201C}\(song.title)\u{201D} is \(place == 1 ? "next" : "number \(place) in the queue")."
    }

    /// Said when a song couldn't be loaded, and was skipped.
    public static func skipped(_ song: Songbook.Song) -> String {
        "\u{201C}\(song.title)\u{201D} couldn't be loaded, so it was skipped."
    }

    // MARK: Songs from phones

    public static let phones = "Songs from Phones"
    public static let letPhonesAdd = "Let phones add songs"
    public static let openOnPhone = "On a phone on the same network, open"
    public static let thenCode = "Then enter this code"
    public static let phonesNote = "Guests can add songs to the queue from a phone on this network: they open the address and enter "
        + "the code. Phones see only the songs' names. It's off whenever karaoke opens. The page isn't encrypted, so turn it "
        + "on only on a network you trust."
    public static let queueFull = "The queue is full. Try again after a song or two."
    public static let notInSongbook = "That song isn't in the songbook any more."

    public static func queuedFromPhone(_ song: Songbook.Song) -> String {
        "A phone added \u{201C}\(song.title)\u{201D}."
    }

    /// On the stage while phones may add songs.
    public static func phonesBadge(address: String, code: String) -> String {
        "Add songs from your phone: \(address) \u{00B7} code \(code)"
    }

    /// Asked before leaving karaoke.
    public static let leave = Confirmation(action: "Leave Karaoke", question: "Leave karaoke?",
                                           detail: "The queue is forgotten, and live TV comes back on the channel you were watching.")
}
