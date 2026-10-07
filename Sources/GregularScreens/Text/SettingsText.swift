/// The words in Settings, shared by every version of the app so they say
/// the same things. Each app draws them its own way.
public enum SettingsText {
    public static let title = "Settings"
    public static let done = "Done"

    public static func onOff(_ on: Bool) -> String { on ? "On" : "Off" }

    // MARK: Streaming quality

    public static let quality = "Streaming quality"
    public static let autoDetail = "Measures how fast your server can stream right now, and backs off when it's busy."
    public static func nowPlaying(_ stream: String) -> String { "Now playing: \(stream)" }
    public static let qualityNote = "Lower quality saves bandwidth but makes the server transcode, which takes more of its processing power. "
        + "If your server is short on CPU rather than bandwidth, Maximum may work best."

    // MARK: Trouble with a programme

    public static func trouble(with programme: String) -> String { "Trouble with \u{201C}\(programme)\u{201D}?" }
    public static let troubleNote = "For this programme only: the next programme, or changing channel, goes back to standard. "
        + "These help when \(AppModel.serverName) has to convert the programme and can't keep up, since a lower quality is quicker to convert. "
        + "A programme that plays as-is will be converted at the lower quality."

    /// The fixes offered, with their row title and detail.
    public static let fixes: [(fix: ChannelPlayer.ProgrammeFix, title: String, detail: String)] = [
        (.stepDown, "Step Down Quality", "Restarts it one step lower, and steps down again whenever it pauses to buffer."),
        (.hd720, "Play at 720p", "Restarts it at 720p (4 Mbps)."),
        (.standard, "Standard", "Back to your streaming quality setting."),
    ]

    // MARK: Schedule code

    public static let scheduleCode = "Schedule code"
    public static let currentCode = "Current code"
    public static let codePlaceholder = "Enter a code, like 7KQM2-X9PDA"
    public static let newRandomCode = "Use a New Random Code"
    public static let badCode = "A code is 10 letters and digits, like 7KQM2-X9PDA."
    /// A special mode's keyword (`AppModel.enterCode`), with nothing on this server to open it with.
    public static let specialModeUnavailable = "There's nothing on this server for that code."
    public static let scheduleCodeNote = "The code sets the running order on every channel. Anyone using the same code, with the same "
        + "\(AppModel.serverName) library and channels, sees the same programmes at the same time. Changing it reshuffles every channel."

    // MARK: Your channels and set times
    //
    // `kept` says where they're saved, such as "on this Apple TV".

    public static let yourChannels = "Your channels"
    public static let setTimes = "Set times"
    public static let noneYet = "None yet."

    public static func yourChannelsNote(kept: String) -> String {
        "Your own channels join the guide like any other. They're saved \(kept): the name, number and the genres, series, "
            + "tags and years in each one's rule. Nothing else from your library is kept."
    }

    public static func setTimesNote(kept: String) -> String {
        "A series or film at fixed times on a channel. At every other time the channel stays the same as for everyone "
            + "with your schedule code. They're saved \(kept): the channel, the names you picked and the times."
    }

    // MARK: Commercials and diagnostics

    public static let commercials = "Commercials"
    public static let playCommercials = "Play commercials"
    public static let commercialsNote = "When off, breaks between programmes are blank, with the Up Next card showing what's on next "
        + "and when. Programmes still start at the same times, so you stay in step with everyone using the same schedule code."

    public static let diagnostics = "Diagnostics"
    public static let showDiagnostics = "Show playback diagnostics"
    public static func commercialsStatus(_ status: String) -> String { "Commercials: \(status)" }
    public static let diagnosticsNote = "Adds a technical line to the info banner: quality, whether the server is transcoding and why, "
        + "buffering, and how far behind live playback is. Useful when something isn't playing well."

    // MARK: Picture (Apple TV)

    public static let picture = "Picture"
    public static let matchFrameRate = "Match frame rate"
    public static let matchFrameRateNote = "Switches the TV to each programme's frame rate and dynamic range, so films play "
        + "without judder. The screen may go dark for a moment when it changes, such as between a programme and the commercials."
    public static let matchContentIsOff = "Match Content is off in this Apple TV's Settings (Video and Audio), "
        + "so the TV won't switch until it's turned on there."

    // MARK: Server

    public static let server = "Server"
    public static let watching = "Watching"
    public static let allServers = "All Servers"

    /// - Parameter back: the button that steps back, such as "Menu".
    public static func serverNote(back: String) -> String {
        "All Servers goes to the main page, to watch another server or add one. \(back) from the guide's top row goes there too; "
            + "the channel plays on behind it."
    }
}
