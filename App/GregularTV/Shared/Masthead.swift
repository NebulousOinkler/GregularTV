import SwiftUI

/// The app's name and tagline, at the top of the main page and sign-in, and
/// on the waiting screen.
struct Masthead: View {
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 16) {
            Text("Gregular TV").font(.system(size: 80, weight: .heavy, design: .rounded))
            Text("We now return to your Gregular programming.").font(.title3).foregroundStyle(.secondary)
        }
    }
}
