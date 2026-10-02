import SwiftUI

/// The Gregular look, as in the app icon and Top Shelf (scripts/make-artwork.swift):
/// a deep indigo gradient, and a slim pill of TV colour bars as the one accent.
enum Brand {
    /// Deep indigo at the top to near-black navy at the bottom.
    static let gradient = LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.36),
                                                  Color(red: 0.04, green: 0.05, blue: 0.12)],
                                         startPoint: .top, endPoint: .bottom)

    /// 75% SMPTE colour bars, left to right.
    static let barColors: [Color] = [
        Color(white: 0.75), Color(red: 0.75, green: 0.75, blue: 0), Color(red: 0, green: 0.75, blue: 0.75),
        Color(red: 0, green: 0.75, blue: 0), Color(red: 0.75, green: 0, blue: 0.75), Color(red: 0.75, green: 0, blue: 0),
        Color(red: 0, green: 0, blue: 0.75),
    ]
}

/// The slim pill of colour bars under the wordmark.
struct ColorBars: View {
    var width: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Brand.barColors.indices, id: \.self) { Brand.barColors[$0] }
        }
        .frame(width: width, height: width / 18)
        .clipShape(Capsule())
    }
}
