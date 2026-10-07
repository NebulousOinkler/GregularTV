import Foundation
import GregularBrowser
import GregularCore
import GregularScreens
import JavaScriptKit
import Observation

/// `PlayerDeck` in a browser: a queue of items played back to back, like
/// Apple TV's `AVQueuePlayer`. Everything `ChannelPlayer` does to video
/// goes through here.
///
/// It has two `<video>` elements: the item playing is in one, and the item
/// after it loads into the other, hidden, so the next one starts at once.
/// HLS plays through hls.js (`js/hls-player.js`); a file plays as it is.
@MainActor final class VideoDeck: PlayerDeck {
    /// Where the deck draws: both its videos, the one playing on top.
    let element = El("div", "deck")
    private let slots: [VideoSlot]
    private var queue: [VideoItem] = []
    /// play() was called and pause() hasn't been since.
    private var wantsToPlay = false

    /// The two decks a `ChannelPlayer` plays on.
    static func pair() -> [any PlayerDeck] { [VideoDeck(), VideoDeck()] }

    init() {
        slots = [VideoSlot(), VideoSlot()]
        for slot in slots {
            element.append(slot.video)
            slot.onEnded = { [weak self, weak slot] in
                guard let self, let slot, slot.item === self.queue.first else { return }
                self.reachedEnd()
            }
        }
    }

    /// A browser has no fallback player (`JellyfinClient` is given none), so
    /// every stream is for the browser's own: `player` is always `.builtIn`.
    func makeItem(url: URL, on player: MediaStream.Player, from start: TimeInterval, to end: TimeInterval,
                  bufferAhead: TimeInterval?) -> any PlayerItem {
        VideoItem(url: url, start: start, end: end, bufferAhead: bufferAhead)
    }

    var currentItem: (any PlayerItem)? { queue.first }

    func contains(_ item: any PlayerItem) -> Bool {
        queue.contains { $0 === item }
    }

    func append(_ item: any PlayerItem) {
        guard let item = item as? VideoItem, !contains(item) else { return }
        queue.append(item)
        arrange()
    }

    func removeAll() {
        for item in queue { item.slot?.unload() }
        queue = []
    }

    func advance() {
        guard !queue.isEmpty else { return }
        queue.removeFirst().slot?.unload()
        arrange()
    }

    var pausesAtItemEnd = false

    var volume: Float = 1 {
        didSet { for slot in slots { slot.volume = Double(volume) } }
    }

    var state: PlayerDeckState {
        guard wantsToPlay else { return .paused }
        guard let slot = queue.first?.slot else { return .waiting }
        return slot.isReady ? .playing : .waiting
    }

    func play() {
        wantsToPlay = true
        queue.first?.slot?.play()
    }

    func pause() {
        wantsToPlay = false
        for slot in slots { slot.pause() }
    }

    func seek(to seconds: TimeInterval) {
        queue.first?.slot?.seek(to: seconds)
    }

    var position: TimeInterval {
        queue.first?.slot?.position ?? 0
    }

    var activity: String {
        switch state {
        case .playing: "Playing"
        case .paused: "Paused"
        case .waiting: "Buffering" + (queue.first?.slot?.waitingReason.map { " (\($0))" } ?? "")
        }
    }

    /// The first item plays in a slot on top; the second loads behind it.
    private func arrange() {
        for item in queue.prefix(2) where item.slot == nil {
            guard let free = slots.first(where: { $0.item == nil }) else { break }
            free.load(item)
        }
        for slot in slots {
            let current = slot.item != nil && slot.item === queue.first
            slot.isCurrent = current
            if current, wantsToPlay { slot.play() } else if !current { slot.pause() }
        }
    }

    /// The playing item reached its end: hold its last frame, or go on.
    private func reachedEnd() {
        if pausesAtItemEnd {
            pause()
        } else {
            advance()
        }
    }
}

/// One item made by a `VideoDeck`: a stream from `start` to `end`.
@MainActor final class VideoItem: PlayerItem {
    let url: URL
    let start: TimeInterval
    let end: TimeInterval
    let bufferAhead: TimeInterval?
    /// The video it's loaded in, while it's playing or next.
    weak var slot: VideoSlot?
    private(set) var failure: (any Error)?

    init(url: URL, start: TimeInterval, end: TimeInterval, bufferAhead: TimeInterval?) {
        self.url = url
        self.start = start
        self.end = end
        self.bufferAhead = bufferAhead
    }

    var hasFailed: Bool { failure != nil }

    func fail(_ error: any Error) {
        if failure == nil { failure = error }
    }

    var bufferedAhead: TimeInterval { slot?.bufferedAhead ?? 0 }
    var bufferedInAll: TimeInterval { slot?.bufferedInAll ?? 0 }
}

/// One `<video>`, and the item loaded in it.
@MainActor final class VideoSlot {
    let video = El("video")
    private(set) var item: VideoItem?
    /// Called when the item reaches its end.
    var onEnded: (() -> Void)?
    /// What's waited for, while buffering, in a word or two.
    private(set) var waitingReason: String?
    /// Where the video has been asked to go and hasn't reached yet. Until it
    /// has, the slot reports that position and isn't ready, as `AVPlayer`
    /// does: a browser can say it's ready at the start before it seeks, and
    /// the player would think it was an hour behind live.
    private var pendingSeek: TimeInterval?
    private var hls: JSObject?
    private var endTimer: JSValue = .undefined
    /// Checks a file has started to load (`checkLoad()`).
    private var loadTimer: JSValue = .undefined
    private var reloads = 0
    /// How long a file may load nothing at all before it's asked for again.
    static let loadPatience: TimeInterval = 8

    init() {
        video.attribute("playsinline", "").attribute("preload", "auto").attribute("disableremoteplayback", "")
        video.object.muted = .boolean(true)
        video.on("waiting") { [weak self] _ in self?.waitingReason = "filling buffer" }
        video.on("stalled") { [weak self] _ in self?.waitingReason = "network stalled" }
        video.on("playing") { [weak self] _ in
            self?.waitingReason = nil
            self?.scheduleEnd()
        }
        video.on("seeked") { [weak self] _ in
            self?.settleSeek()
            self?.scheduleEnd()
        }
        video.on("timeupdate") { [weak self] _ in
            self?.settleSeek()
            self?.checkEnd()
        }
        video.on("ended") { [weak self] _ in self?.finish() }
        video.on("error") { [weak self] _ in
            guard let self, let item = self.item else { return }
            item.fail(UnplayableFormat())
        }
    }

    /// The item is on screen, with sound.
    var isCurrent = false {
        didSet {
            video.classed("current", isCurrent)
            video.object.muted = .boolean(!isCurrent || SoundUnlock.isMuted)
        }
    }

    var volume: Double = 1 {
        didSet { video.object.volume = .number(volume) }
    }

    /// Has enough to play on (HAVE_FUTURE_DATA), where it was asked to be.
    var isReady: Bool {
        (video.object.readyState.number ?? 0) >= 3 && video.object.seeking.boolean != true && pendingSeek == nil
    }

    /// Seconds into the item: where it's going, while a seek is on its way.
    var position: TimeInterval {
        pendingSeek ?? video.object.currentTime.number ?? 0
    }

    /// A seek has landed (to within the couple of seconds `PlayerDeck` allows).
    private func settleSeek() {
        guard let target = pendingSeek, video.object.seeking.boolean != true,
              abs((video.object.currentTime.number ?? 0) - target) < 2 else { return }
        pendingSeek = nil
    }

    func load(_ item: VideoItem) {
        unload()
        self.item = item
        item.slot = self
        let url = item.url.absoluteString
        let isHLS = item.url.path().hasSuffix(".m3u8")
        let player = JSObject.global.gregularHLS.object!
        if isHLS, player.supported!().boolean == true {
            let failed = JSClosure { [weak item] arguments in
                MainActor.assumeIsolated {
                    item?.fail(arguments.first?.string == "network" ? BrowserNetwork.Unreachable() as any Error : UnplayableFormat())
                }
                return .undefined
            }
            hls = player.attach!(video.object, url, item.start, item.bufferAhead ?? 30,
                                 BrowserNetwork.isLocalHTTP(item.url), failed).object
        } else {
            video.object.src = .string(url)
            _ = video.object.load!()
            // Starts partway in: set now, before the file's length is known, it's
            // where the browser starts. A seek after this (to live) replaces it.
            if item.start > 0 { seek(to: item.start) }
            reloads = 0
            checkLoadLater()
        }
    }

    /// Now and then a browser never starts loading a file, with no error
    /// (seen in Firefox): after `loadPatience` with nothing at all, it's
    /// asked for again, from the same place, twice at most. (HLS retries in
    /// hls.js; anything longer is `ChannelPlayer`'s stall timeout.)
    private func checkLoadLater() {
        _ = JSObject.global.clearTimeout!(loadTimer)
        loadTimer = JSObject.global.setTimeout!(JSOneshotClosure { [weak self] _ in
            MainActor.assumeIsolated { self?.checkLoad() }
            return .undefined
        }, Self.loadPatience * 1000)
    }

    private func checkLoad() {
        guard let item, hls == nil, (video.object.readyState.number ?? 0) == 0, video.object.error.isNull,
              reloads < 2 else { return }
        reloads += 1
        let resumeAt = position
        let wasPlaying = isCurrent && video.object.paused.boolean != true   // loading again pauses it
        video.object.src = .string(item.url.absoluteString)
        _ = video.object.load!()
        video.object.currentTime = .number(resumeAt)
        if wasPlaying { play() }
        checkLoadLater()
    }

    func unload() {
        _ = JSObject.global.clearTimeout!(endTimer)
        _ = JSObject.global.clearTimeout!(loadTimer)
        _ = hls?.destroy!()
        hls = nil
        _ = video.object.pause!()
        _ = video.object.removeAttribute!("src")
        _ = video.object.load!()
        item?.slot = nil
        item = nil
        waitingReason = nil
        pendingSeek = nil
        isCurrent = false
    }

    func play() {
        guard item != nil else { return }
        let promise = video.object.play!()
        // Browsers refuse sound until the viewer has clicked: play muted, and say so.
        _ = promise.object?.catch!(JSOneshotClosure { [weak self] arguments in
            MainActor.assumeIsolated {
                guard let self, arguments.first?.object?.name.string == "NotAllowedError" else { return }
                SoundUnlock.needed()
                self.video.object.muted = .boolean(true)
                _ = self.video.object.play!()
            }
            return .undefined
        })
    }

    func pause() {
        _ = JSObject.global.clearTimeout!(endTimer)
        _ = video.object.pause!()
    }

    func seek(to seconds: TimeInterval) {
        pendingSeek = seconds
        video.object.currentTime = .number(seconds)
    }

    var bufferedAhead: TimeInterval {
        let now = position
        return ranges.first { $0.contains(now) }.map { $0.upperBound - now } ?? 0
    }

    var bufferedInAll: TimeInterval {
        ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
    }

    private var ranges: [ClosedRange<Double>] {
        guard let buffered = video.object.buffered.object else { return [] }
        return (0..<Int(buffered.length.number ?? 0)).compactMap { index in
            guard let start = buffered.start!(index).number, let end = buffered.end!(index).number, end >= start else { return nil }
            return start...end
        }
    }

    // MARK: The item's end

    /// Ends right on time, rather than at the next `timeupdate` (four a second).
    private func scheduleEnd() {
        _ = JSObject.global.clearTimeout!(endTimer)
        guard let item, isCurrent, video.object.paused.boolean != true else { return }
        let remaining = max(0, item.end - position)
        endTimer = JSObject.global.setTimeout!(JSOneshotClosure { [weak self] _ in
            MainActor.assumeIsolated { self?.checkEnd() }
            return .undefined
        }, remaining * 1000)
    }

    private func checkEnd() {
        guard let item, isCurrent, position >= item.end - 0.05 else { return }
        finish()
    }

    private func finish() {
        guard isCurrent else { return }
        _ = video.object.pause!()
        onEnded?()
    }
}

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

/// A programme the browser couldn't play.
struct UnplayableFormat: LocalizedError {
    var errorDescription: String? {
        "This programme couldn't be played. It may be in a format this browser can't show."
    }
}
