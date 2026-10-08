import Foundation
import JavaScriptKit
import Observation

/// Browsers won't play sound until the viewer has interacted with the page.
/// When a video had to start muted, the watch screen says "Click for sound";
/// the next click or key turns sound on everywhere.
@MainActor @Observable final class SoundUnlock {
    static let shared = SoundUnlock()
    private(set) var isNeeded = false

    static var isMuted: Bool { shared.isNeeded }

    static func needed() {
        shared.isNeeded = true
    }

    /// Plays `video`. A browser that refuses sound until the viewer has
    /// clicked plays it muted instead, and the screen says so.
    static func play(_ video: El) {
        let promise = video.object.play!()
        _ = promise.object?.catch!(JSOneshotClosure { [weak video = video.object] arguments in
            MainActor.assumeIsolated {
                guard let video, arguments.first?.object?.name.string == "NotAllowedError" else { return }
                needed()
                video.muted = .boolean(true)
                _ = video.play!()
            }
            return .undefined
        })
    }

    /// Called from a click or key press: sound is allowed now.
    static func unlock() {
        guard shared.isNeeded else { return }
        shared.isNeeded = false
        let videos = DOM.document.querySelectorAll!("video.current, video.song-video").object!
        for index in 0..<Int(videos.length.number ?? 0) {
            videos[index].muted = .boolean(false)
        }
    }
}
