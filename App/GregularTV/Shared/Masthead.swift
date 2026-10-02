import SwiftUI

/// The app's name, its colour bars and tagline, as on the Top Shelf: at the
/// top of the main page and sign-in, and on the waiting screen.
struct Masthead: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Gregular TV").font(.system(size: 80, weight: .heavy, design: .rounded))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
            ColorBars()
            Text("We now return to your Gregular programming.").font(.title3).foregroundStyle(.secondary)
        }
    }
}
