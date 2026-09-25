/// One way of saying "the programme is over; the channel is in a break
/// until the next one", used by the badge, the banner, the channel list and
/// the guide, so it reads the same everywhere. (Each app styles it; on Apple
/// TV that's `BreakStyle`.)
public enum BreakText {
    public static let title = "Commercial break"
    /// An SF Symbols name for it (a TV).
    public static let symbol = "tv"
}
