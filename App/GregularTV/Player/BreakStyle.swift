import SwiftUI

/// One look for "the programme is over; the channel is in a break until the
/// next one", used by the watch screen's badge, the banner, the channel list
/// and the guide, so it reads the same everywhere.
enum BreakStyle {
    static let title = "Commercial break"
    static let symbol = "tv"
    /// The guide's darker tail over the break part of a programme's block.
    static let guideTail = Color.black.opacity(0.45)

    /// "Commercial break" with its symbol.
    static var label: some View {
        Label(title, systemImage: symbol)
    }
}
