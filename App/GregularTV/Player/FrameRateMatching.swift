import AVFoundation
import AVKit
import UIKit

/// "Match frame rate" in Settings: asks Apple TV to switch the TV to the
/// frame rate and dynamic range of what's on screen, so a 24 fps film isn't
/// shown at 60 Hz with judder. Apple TV only switches if Match Content is on
/// in its own Settings (Video and Audio); otherwise asking does nothing.
/// A bare `AVPlayerLayer`, as live TV uses, never asks by itself.
enum FrameRateMatching {
    /// The window's display manager, which switches the TV.
    @MainActor static var displayManager: AVDisplayManager? {
        UIApplication.shared.connectedScenes.lazy.compactMap { ($0 as? UIWindowScene)?.keyWindow?.avDisplayManager }.first
    }

    /// Whether Apple TV switches when asked (Match Content is on). True if it can't be told.
    @MainActor static var isOnInAppleTVSettings: Bool {
        displayManager?.isDisplayCriteriaMatchingEnabled ?? true
    }

    /// Switches the TV to what `deck`'s current item needs, once its player
    /// knows; with no deck, back to the TV's usual mode. A task that's
    /// cancelled (the item changed) stops waiting and leaves it.
    @MainActor static func match(_ deck: TVDeck?) async {
        guard let deck else {
            displayManager?.preferredDisplayCriteria = nil
            return
        }
        // A file's details come quickly; a stream's once it's playing.
        for _ in 0..<60 {
            if Task.isCancelled { return }
            if let criteria = await deck.displayCriteria() {
                if !Task.isCancelled { displayManager?.preferredDisplayCriteria = criteria }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

extension TVDeck {
    /// What the TV should switch to for the current item: its frame rate
    /// and its video's format (which carries its dynamic range). Nil until
    /// its player knows.
    func displayCriteria() async -> AVDisplayCriteria? {
        guard let current = queue.first else { return nil }
        if let vlc = current.vlcItem {
            // VLC says only the rate and size: the format of an SDR picture that size.
            guard let video = vlc.videoTrack else { return nil }
            var format: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_H264, width: Int32(video.width),
                                           height: Int32(video.height), extensions: nil, formatDescriptionOut: &format)
            return format.map { AVDisplayCriteria(refreshRate: Float(video.frameRate), formatDescription: $0) }
        }
        guard let item = current.avItem, item.status == .readyToPlay else { return nil }
        // A file has its tracks in the asset; a stream (HLS) only in the item, once playing.
        let track = if let fileTrack = try? await item.asset.loadTracks(withMediaType: .video).first {
            fileTrack
        } else {
            item.tracks.lazy.compactMap(\.assetTrack).first { $0.mediaType == .video }
        }
        guard let track, let format = try? await track.load(.formatDescriptions).first else { return nil }
        let nominal = (try? await track.load(.nominalFrameRate)) ?? 0
        let rate = nominal > 0 ? nominal : item.tracks.first { $0.assetTrack?.mediaType == .video }?.currentVideoFrameRate ?? 0
        guard rate > 0 else { return nil }
        return AVDisplayCriteria(refreshRate: rate, formatDescription: format)
    }
}
