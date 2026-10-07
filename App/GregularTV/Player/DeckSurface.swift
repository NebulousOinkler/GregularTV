import SwiftUI
import SwiftVLC

/// A `TVDeck`'s picture: AVFoundation's, and each queued VLC item's, the
/// current item's on top. Every VLC item in the queue has its view here
/// from the moment it's queued, hidden until it's current, because VLC
/// draws only into a view it had when it started (`VLCItem`).
struct DeckSurface: View {
    let deck: TVDeck

    var body: some View {
        let current = deck.queue.first?.vlcItem
        ZStack {
            VideoSurface(player: deck.avPlayer)
            ForEach(deck.queue.compactMap(\.vlcItem)) { item in
                VideoView(item.player)
                    .opacity(item === current ? 1 : 0)
                    .zIndex(item === current ? 1 : 0)
                    .onAppear { item.surfaceAppeared() }
            }
        }
    }
}
