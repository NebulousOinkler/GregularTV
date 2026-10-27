import GregularScreens
import SwiftUI
import UIKit

/// A feed's picture, or its badge (`Feed.Badge`): initials on a colour.
struct FeedArt: View {
    let feed: Feed
    static let side: CGFloat = 80

    var body: some View {
        Group {
            // A PNG the feed carries, checked small before anything decodes it (`FeedDocument.imageData`).
            if let data = feed.picture, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(feed.badge.initials).font(.title2.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hue: Double(feed.badge.hue) / 360, saturation: 0.45, brightness: 0.55))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}
