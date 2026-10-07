/// Karaoke's looks, chosen from boxes on its first screen each time it
/// opens (never remembered). Each front end draws them its own way, with
/// each one's own menu music and sound effects; this is the list they share.
public enum KaraokeTheme: String, CaseIterable, Sendable, Identifiable {
    case neonDisco
    case karaokeBar
    case bubblegumPop
    case vegasLounge

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .neonDisco: "Neon Disco"
        case .karaokeBar: "80s Karaoke Bar"
        case .bubblegumPop: "Bubblegum Pop"
        case .vegasLounge: "Vegas Lounge"
        }
    }

    /// A line under its name in the theme box.
    public var tagline: String {
        switch self {
        case .neonDisco: "Glow sticks and a mirror ball"
        case .karaokeBar: "Big hair, bigger chorus"
        case .bubblegumPop: "Sweet, sticky and stuck in your head"
        case .vegasLounge: "Sequins, velvet and one more encore"
        }
    }
}
