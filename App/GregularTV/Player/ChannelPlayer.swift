import AVFoundation
import GregularTVCore
import Observation

/// Plays one channel as live TV.
///
/// The schedule decides what should be on. This class makes AVPlayer match:
/// - **Tuning in** loads what's on now and seeks to the live position.
/// - **Hand-off:** 30 seconds before a programme or commercial ends, whatever
///   is next is queued in the `AVQueuePlayer`, so it follows with no loading
///   spinner. Only one item is ever queued.
/// - **Commercial breaks:** as a break starts, the programme after it starts
///   loading, paused, in a second player behind the one on screen, so it's
///   buffered by the time the commercials end. At the programme's start time
///   the two swap: the standby player comes to the front and plays. (An
///   AVPlayerItem can never move between players, so it stays where it
///   loaded.) So the server works on at most two streams, or three in the
///   last 30 seconds of a commercial: this clip, the next one, and the programme.
/// - **Commercials** are only ever played as-is or remuxed, with no bitrate
///   cap, so a clip's bitrate never makes it re-encoded. One that would need
///   re-encoding anyway (a video codec the Apple TV can't play) is skipped,
///   and its time is blank.
/// - **Gaps:** time with nothing scheduled (a gap of a minute or less, the
///   end of a break, a skipped commercial, or every break with commercials
///   off) is a blank screen with an "Up next" card. The next item is still
///   queued 30 seconds ahead, but held until its start time.
/// - **Pause** really pauses. Resuming jumps back to live (PLAN.md §7).
/// - **Drift:** if buffering leaves playback over a minute behind live, it re-tunes.
/// - **Failures** (server down, network drop) retry with backoff: 5 s, 10 s,
///   20 s, 40 s, then every minute, so playback returns by itself when the
///   server does.
/// - **Stalls:** if video hasn't moved for 30 s (for example, the server
///   can't transcode fast enough), it's treated as a failure and retried.
/// - **Head start for re-encoding:** tuning into a programme Jellyfin has to
///   re-encode, the player asks for it from a little ahead of live
///   (`transcodeHeadStart`), lets it buffer paused while the screen is blank,
///   and starts playing when live reaches that point, once `startCushion` is
///   buffered (waiting up to `maxCushionWait` more for it, a little behind
///   live). Each stall on the channel doubles the head start, up to
///   `maxTranscodeHeadStart`. Files that play as-is or are only repackaged
///   start at once.
/// - **Re-encoding that can't keep up:** when a programme Jellyfin re-encodes
///   fails or stalls, the retry asks for less work: 720p, then a step lower
///   on each further failure, for that programme only (shown in Settings as
///   its fix). The server's processor is the limit, not the connection, so
///   Auto doesn't re-measure first.
/// - **Too little left to re-encode:** a programme Jellyfin would re-encode
///   isn't started with under `minReencodedTimeLeft` to go, since starting a
///   transcode costs the server a lot for a minute of video. The screen is
///   blank with "Up next" instead.
/// - **Programme fixes** (`ProgrammeFix`, from Settings) try a lower quality
///   for just the programme on now, if it keeps having trouble. Changing
///   channel, changing quality, or the next programme starting puts it back
///   to standard.
/// - **Quality** caps the bitrate Jellyfin sends. Auto never delays playback
///   to measure: it plays at the last measured rate (8 Mbps before the first
///   measurement), then runs the speed test in the background once playback
///   has settled, for the next programme. After a playback failure it measures
///   *before* retrying, because the retry waits anyway. With a fixed quality,
///   no speed test ever runs.
///
/// **The stream only restarts on an explicit change:** a different channel, a
/// different quality, resuming from pause (which jumps to live), or recovery
/// from a failure or stall. Opening menus, the guide or Settings, choosing the
/// setting that's already selected, or the app briefly becoming inactive
/// (a system overlay) never re-buffers what's playing.
///
/// Everything runs on the main actor. A once-a-second heartbeat checks the
/// state, which keeps the logic in one readable place (`tick()`) rather than
/// spread across observers.
@MainActor @Observable
final class ChannelPlayer {
    enum Status: Equatable {
        case tuning
        case playing
        case paused(since: Date)
        case betweenProgrammes(until: Date)
        /// Buffering ahead of live while Jellyfin re-encodes; plays at `at`.
        case startingSoon(at: Date)
        case failed(message: String, retryAt: Date)
    }

    /// A viewer's choice, from Settings, for just the programme on now.
    enum ProgrammeFix: Equatable {
        /// The quality setting, as usual.
        case standard
        /// One quality step lower, and another each time it pauses to buffer.
        case stepDown
        /// 720p (4 Mbps).
        case hd720
    }

    static let prepareNextLead: TimeInterval = 30
    static let maxDriftBehindLive: TimeInterval = 60
    static let maxRetryDelay: TimeInterval = 60
    static let autoRemeasureInterval: TimeInterval = 600
    /// How long after starting a programme Auto's background speed test waits,
    /// so it doesn't compete with the video for bandwidth while it starts.
    static var backgroundMeasurementDelay: Duration = .seconds(20)
    static let stallTimeout: TimeInterval = 30
    static let transcodeHeadStart: TimeInterval = 20
    static let maxTranscodeHeadStart: TimeInterval = 120
    /// Seconds of video to have buffered before a head start begins playing.
    static let startCushion: TimeInterval = 15
    /// How much longer than the head start to wait for that cushion.
    static let maxCushionWait: TimeInterval = 30
    /// How far ahead a re-encoded programme keeps buffering, so it builds a
    /// reserve whenever Jellyfin gets ahead.
    static let reencodedForwardBuffer: TimeInterval = 60
    /// With "Step down quality", buffering this long steps down again.
    static let stepDownAfterBuffering: TimeInterval = 4
    /// A re-encoded programme with less than this left isn't started.
    static let minReencodedTimeLeft: TimeInterval = 180

    /// Two players, each with its own video surface. One is on screen
    /// (`player`); the other is standby, buffering the programme after a
    /// commercial break (`afterBreak`) until they swap.
    let players = [AVQueuePlayer(), AVQueuePlayer()]
    private(set) var activeIndex = 0
    /// The player on screen.
    var player: AVQueuePlayer { players[activeIndex] }
    private var standby: AVQueuePlayer { players[1 - activeIndex] }
    private(set) var schedule: ChannelSchedule
    private(set) var status: Status = .tuning
    /// What the schedule says is on this channel. The UI shows this.
    private(set) var airing: Airing? {
        didSet {
            // A fix is for one programme: the next one plays as standard.
            if let airing, !airing.isFiller, let fixed = fixedProgramme, fixed.airing != airing {
                clearProgrammeFix()
            }
        }
    }
    /// The fix in use for the programme on now.
    private(set) var programmeFix: ProgrammeFix = .standard
    /// The programme on now, if one is (not a commercial or a gap). Fixes apply to it.
    var fixableProgramme: Airing? {
        airing.flatMap { $0.isFiller ? nil : $0 }
    }
    /// Goes up on every tune-in, so the UI can show the banner even when the
    /// programme hasn't changed (for example, jumping back to live after a pause).
    private(set) var tuneCount = 0
    private(set) var quality: StreamingQuality
    /// For example "Auto · up to 8.4 Mbps · direct play". Shown with diagnostics on.
    private(set) var streamDescription: String?
    /// True while AVPlayer is waiting for data. The UI shows "Buffering…".
    private(set) var isBuffering = false
    /// Called if the server rejects our token, for example because the device
    /// was removed in Jellyfin's dashboard. Retrying can't help; sign in again.
    var onUnauthorized: (() -> Void)?
    /// Set from Settings ("Show playback diagnostics"). Diagnostics are only
    /// worked out while it's on.
    var diagnosticsEnabled = false {
        didSet { if !diagnosticsEnabled { diagnostics = nil } }
    }
    /// Live playback details for the banner, while diagnostics are on.
    private(set) var diagnostics: PlaybackDiagnostics?
    /// For Settings' diagnostics: how many commercials have been skipped.
    var skippedCommercialsNote: String? {
        switch skippedCommercialIDs.count {
        case 0: nil
        case 1: "1 was skipped so far because Jellyfin would have to re-encode it."
        case let n: "\(n) were skipped so far because Jellyfin would have to re-encode them."
        }
    }

    private let client: JellyfinClient
    private var current: LoadedAiring?
    private var next: LoadedAiring?
    private var isPreparingNext = false
    /// The programme a fix applies to, and the cap it's playing at.
    private var fixedProgramme: (airing: Airing, cap: Int)?
    /// When the current fixed programme started buffering, for stepping down again.
    private var bufferingSince: Date?
    /// The programme after the current commercial break, buffering in
    /// `standby`. It becomes `next` once it's the next thing to air.
    private var afterBreak: LoadedAiring?
    /// When the break we've started preloading for ends, so each break loads once.
    private var preloadedBreakEnd: Date?
    /// `next` is in `standby`, waiting for its start time to swap in.
    private var nextIsOnStandby = false
    /// Swaps to `standby` right on the programme's start time.
    private var standbyHandoff: Task<Void, Never>?
    /// Commercials that would need re-encoding, found this session. In memory only.
    private var skippedCommercialIDs: Set<String> = []
    /// Failures since video last actually played, on this channel. Sets the retry backoff.
    private var consecutiveFailures = 0
    /// Auto's latest bandwidth-based cap, and when it was measured.
    private var autoBitrate: (bitsPerSecond: Int, measuredAt: Date)?
    /// A background speed test that's waiting or running (Auto only).
    private var measurementTask: Task<Void, Never>?
    /// Set by a playback failure in Auto: measure before the next load.
    private var needsMeasurementFirst = false
    /// When the playhead last moved, for spotting stalls.
    private var lastProgress: (position: Double, at: Date)?
    private var tuneTask: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?

    /// An airing with its AVPlayerItem and Jellyfin play session.
    private struct LoadedAiring {
        let airing: Airing
        let item: AVPlayerItem
        /// Cleared once Jellyfin has been told to stop, so it's only told once.
        var transcodeSessionID: String?
        let description: String
        /// The bitrate cap it was asked for.
        let cap: Int
        /// Jellyfin re-encodes the video, so tuning in mid-programme gets a head start.
        let reencodesVideo: Bool
        /// Jellyfin's reasons for transcoding, if it is (for diagnostics).
        let transcodeReasons: String?
    }

    init(schedule: ChannelSchedule, client: JellyfinClient, quality: StreamingQuality) {
        self.schedule = schedule
        self.client = client
        self.quality = quality
    }

    // MARK: - Controls

    /// Starts playing live. Does nothing if already running, so extra
    /// "appear" or "became active" events never restart the stream.
    func start() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        tune()
    }

    /// Stops playback and releases server transcodes. Use when leaving the
    /// screen or when the app goes to the background.
    func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        cancelMeasurement()
        unloadEverything()
        status = .tuning
    }

    func switchTo(_ schedule: ChannelSchedule) {
        self.schedule = schedule
        consecutiveFailures = 0   // a new channel starts with the shortest retry wait
        clearProgrammeFix()
        tune()
    }

    /// Applies a fix to the programme on now and restarts it. Does nothing
    /// during a commercial or a gap.
    func setProgrammeFix(_ fix: ProgrammeFix) {
        guard let programme = fixableProgramme else { return }
        switch fix {
        case .standard:
            guard programmeFix != .standard else { return }
            clearProgrammeFix()
        case .stepDown:
            let from = fixedProgramme?.cap ?? current?.cap ?? StreamingQuality.fallbackAutoBitrate
            fixedProgramme = (programme, StreamingQuality.bitrate(below: from) ?? StreamingQuality.lowestBitrate)
        case .hd720:
            fixedProgramme = (programme, StreamingQuality.hd720.fixedBitrate!)
        }
        programmeFix = fix
        tune()
    }

    private func clearProgrammeFix() {
        fixedProgramme = nil
        programmeFix = .standard
    }

    /// Re-tunes at the new quality. Choosing the quality that's already set
    /// does nothing: the stream carries on, and Auto keeps its measurement.
    func setQuality(_ quality: StreamingQuality) {
        guard quality != self.quality else { return }
        self.quality = quality
        clearProgrammeFix()
        // Any speed test belongs to Auto: stop it, and forget its result.
        cancelMeasurement()
        autoBitrate = nil
        needsMeasurementFirst = false
        tune()
    }

    /// Play/Pause on the remote. Resuming always jumps to live.
    func togglePause() {
        switch status {
        case .paused:
            tune()
        case .playing:
            player.pause()
            status = .paused(since: .now)
        default:
            break
        }
    }

    /// Drops whatever is playing and joins the channel live.
    func tune() {
        unloadEverything()
        status = .tuning
        tuneCount += 1

        let tuning = schedule.tune(at: .now)
        airing = tuning.airing
        if tuning.isInPadding {
            status = .betweenProgrammes(until: tuning.airing.slotEnd)
            return
        }

        tuneTask = Task {
            do {
                let loaded = try await load(tuning.airing)
                guard !Task.isCancelled else { return release(loaded) }
                if loaded.reencodesVideo, !tuning.airing.isFiller,
                   tuning.airing.end.timeIntervalSinceNow < Self.minReencodedTimeLeft {
                    // Not worth a transcode: blank with "Up next" until the
                    // break after it, or the next programme if there's none.
                    release(loaded)
                    let breakFollows = schedule.commercialBreak(at: tuning.airing.end) != nil
                    status = .betweenProgrammes(until: breakFollows ? tuning.airing.end : tuning.airing.slotEnd)
                    return
                }
                current = loaded
                streamDescription = loaded.description
                player.insert(loaded.item, after: nil)
                if loaded.reencodesVideo, let start = headStartTarget(in: tuning.airing) {
                    // Let Jellyfin get ahead: buffer from `start`, paused, then play on time.
                    seek(to: start.timeIntervalSince(tuning.airing.start))
                    status = .startingSoon(at: start)
                    // Wait for live to reach `start`. Don't start into an almost
                    // empty buffer: wait a little longer for a cushion if Jellyfin
                    // was slow to get going. A stream that fails is retried at
                    // once, not after the head start.
                    let deadline = start.addingTimeInterval(Self.maxCushionWait)
                    while !Task.isCancelled, Date.now < deadline, loaded.item.status != .failed,
                          Date.now < start || Self.bufferedAhead(in: loaded.item) < Self.startCushion {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard !Task.isCancelled else { return }
                    if loaded.item.status == .failed {
                        return fail(loaded.item.error, airing: tuning.airing)
                    }
                } else {
                    // Measure the offset *after* loading, so time spent waiting for
                    // the server doesn't leave us behind live.
                    seek(to: Date.now.timeIntervalSince(tuning.airing.start))
                }
                player.play()
                status = .playing
            } catch is SkippedCommercial {
                // Blank, with the banner, until the next clip or programme.
                guard !Task.isCancelled else { return }
                status = .betweenProgrammes(until: tuning.airing.slotEnd)
            } catch {
                guard !Task.isCancelled else { return }
                fail(error, airing: tuning.airing)
            }
        }
    }

    // MARK: - Heartbeat

    private func tick() {
        let now = Date.now
        switch status {
        case .tuning, .paused, .startingSoon:
            return
        case .betweenProgrammes(let until):
            if now >= until, !startHeldNext() { tune() }
            return
        case .failed(_, let until):
            if now >= until { tune() }
            return
        case .playing:
            break
        }
        guard let current else { return }

        // Checked first: AVQueuePlayer drops an item that fails from its queue,
        // which would otherwise look like the item finishing, leaving the
        // channel blank until the slot ends instead of retrying.
        if current.item.status == .failed {
            fail(current.item.error, airing: current.airing)
            return
        }

        // AVQueuePlayer has moved on, either to the queued item or to nothing.
        if player.currentItem !== current.item {
            release(current)
            isPreparingNext = false
            if let next, player.currentItem === next.item {
                self.current = next
                self.next = nil
                airing = next.airing
                streamDescription = next.description
                lastProgress = nil   // the stall watchdog starts afresh for the new item
            } else {
                self.current = nil
                if now < current.airing.slotEnd {
                    status = .betweenProgrammes(until: current.airing.slotEnd)
                } else {
                    tune()
                }
            }
            return
        }

        // Finished, with a gap before the next item: the player has paused at
        // the end. Blank, with the "Up next" card, until the next item starts.
        if player.actionAtItemEnd == .pause, player.timeControlStatus == .paused {
            isBuffering = false
            // It's finished, so let Jellyfin stop its transcode and delete the
            // temporary files now, rather than when the next item starts.
            if current.transcodeSessionID != nil {
                release(current)
                self.current?.transcodeSessionID = nil
            }
            status = .betweenProgrammes(until: next?.airing.start ?? current.airing.slotEnd)
            return
        }
        if player.timeControlStatus == .playing {
            consecutiveFailures = 0
        }
        isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate

        // "Step down quality": buffering for a few seconds steps down again.
        if programmeFix == .stepDown, isBuffering, let fixed = fixedProgramme, fixed.airing == current.airing {
            let since = bufferingSince ?? now
            bufferingSince = since
            if now.timeIntervalSince(since) > Self.stepDownAfterBuffering,
               let lower = StreamingQuality.bitrate(below: fixed.cap) {
                fixedProgramme = (fixed.airing, lower)
                tune()
                return
            }
        } else {
            bufferingSince = nil
        }

        // Stall watchdog: the playhead hasn't got any further for too long.
        // Only forward progress counts, so a stream stuck jittering back and
        // forth (or with no time at all) is still caught.
        let position = player.currentTime().seconds
        if lastProgress == nil || position > (lastProgress?.position ?? 0) + 0.5 {
            lastProgress = (position, now)
        } else if let last = lastProgress, now.timeIntervalSince(last.at) > Self.stallTimeout {
            fail(StallError(), airing: current.airing)
            return
        }
        if diagnosticsEnabled {
            diagnostics = PlaybackDiagnostics(player: player,
                                              behindLive: now.timeIntervalSince(current.airing.start) - position,
                                              transcodeReasons: current.transcodeReasons,
                                              preloaded: (nextIsOnStandby ? next : afterBreak)?.item)
        }

        // A long buffering stall left us well behind live, so jump back.
        let behindLive = now.timeIntervalSince(current.airing.start) - position
        if player.timeControlStatus == .playing, behindLive > Self.maxDriftBehindLive {
            tune()
            return
        }

        if current.airing.isFiller, preloadedBreakEnd.map({ current.airing.slotEnd > $0 }) ?? true {
            preloadProgrammeAfterBreak(during: current.airing)
        }

        // Queue whatever's next (a programme or a commercial) shortly before this one ends.
        if next == nil, !isPreparingNext, current.airing.end.timeIntervalSince(now) < Self.prepareNextLead {
            prepareNext(after: current)
        }
    }

    /// At the end of a gap, starts the next item that was queued and held
    /// during it, so it's already buffered. False if nothing was held.
    private func startHeldNext() -> Bool {
        if nextIsOnStandby {
            switchToStandby()
            return true
        }
        guard let current, let next, player.currentItem === current.item,
              player.items().contains(where: { $0 === next.item }) else { return false }
        player.actionAtItemEnd = .advance
        player.advanceToNextItem()
        player.play()
        status = .playing   // the next tick sees the hand-off and swaps current and next
        return true
    }

    private func prepareNext(after current: LoadedAiring) {
        isPreparingNext = true   // stays set on failure; the end-of-programme re-tune tries again
        Task {
            // Whatever airs next, passing over any commercial that would need
            // re-encoding: its time is left blank.
            var from = current.airing.slotEnd
            while let upcoming = schedule.airings(from: from, to: from.addingTimeInterval(1)).first {
                // The channel may have changed, or re-tuned, while we were loading.
                guard self.current?.item === current.item, next == nil else { return }
                // The programme after a break is already buffering in `standby`.
                if let preloaded = afterBreak, preloaded.airing == upcoming {
                    return scheduleStandbyHandoff(to: preloaded)
                }
                do {
                    let loaded = try await load(upcoming)
                    guard self.current?.item === current.item, next == nil else { return release(loaded) }
                    return queue(loaded, after: current)
                } catch is SkippedCommercial {
                    from = upcoming.slotEnd
                } catch {
                    return
                }
            }
        }
    }

    /// Holds on the current item if it ends early (blank, with the banner),
    /// and swaps to `standby` right on the programme's start time.
    private func scheduleStandbyHandoff(to preloaded: LoadedAiring) {
        afterBreak = nil
        next = preloaded
        nextIsOnStandby = true
        player.actionAtItemEnd = .pause
        let wait = preloaded.airing.start.timeIntervalSinceNow
        standbyHandoff = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, wait)))
            guard !Task.isCancelled else { return }
            self?.switchToStandby()
        }
    }

    private func queue(_ loaded: LoadedAiring, after current: LoadedAiring) {
        next = loaded
        // With a gap before it (padding, or time the commercials didn't fill),
        // hold on the last frame when this item ends, rather than starting
        // the next one early; `startHeldNext()` starts it on time.
        let hasGap = loaded.airing.start.timeIntervalSince(current.airing.end) > 0.5
        player.actionAtItemEnd = hasGap ? .pause : .advance
        player.insert(loaded.item, after: current.item)
    }

    /// Brings `standby`, with the programme after the break, to the front and
    /// plays it; the old player lets go of the commercial.
    private func switchToStandby() {
        guard nextIsOnStandby, let next else { return }
        standbyHandoff?.cancel()
        standbyHandoff = nil
        let old = player
        activeIndex = 1 - activeIndex
        // Normally on the dot; if the heartbeat got here late, catch up.
        let late = Date.now.timeIntervalSince(next.airing.start)
        if late > 2 { seek(to: late) }
        player.play()
        old.pause()
        old.removeAllItems()
        old.actionAtItemEnd = .advance
        if let current { release(current) }
        current = next
        self.next = nil
        nextIsOnStandby = false
        isPreparingNext = false
        airing = next.airing
        streamDescription = next.description
        lastProgress = nil
        status = .playing
    }

    /// Starts loading the programme that follows the break `clip` is in.
    /// It buffers, paused, in `standby` until the swap.
    private func preloadProgrammeAfterBreak(during clip: Airing) {
        guard let span = schedule.commercialBreak(at: clip.start) else { return }
        preloadedBreakEnd = span.end
        guard let programme = schedule.airings(from: span.end, to: span.end.addingTimeInterval(1)).first,
              !programme.isFiller else { return }
        let tuneCount = tuneCount
        Task {
            guard let loaded = try? await load(programme) else { return }   // the usual 30 s lead tries again
            // Dropped if the channel changed or re-tuned while it loaded.
            guard self.tuneCount == tuneCount, preloadedBreakEnd == span.end, afterBreak == nil,
                  next?.airing != programme else { return release(loaded) }
            afterBreak = loaded
            standby.removeAllItems()
            standby.insert(loaded.item, after: nil)
        }
    }

    // MARK: - Helpers

    /// Seconds buffered past the playhead.
    private static func bufferedAhead(in item: AVPlayerItem) -> TimeInterval {
        let now = item.currentTime()
        return item.loadedTimeRanges.map(\.timeRangeValue)
            .first { $0.containsTime(now) }
            .map { ($0.end - now).seconds } ?? 0
    }

    /// Where to start a re-encoded programme: a head start past live that
    /// doubles with each failure on this channel. Nil if the programme ends
    /// too soon for it to be worth it.
    private func headStartTarget(in airing: Airing) -> Date? {
        let lead = min(Self.maxTranscodeHeadStart, Self.transcodeHeadStart * pow(2, Double(consecutiveFailures)))
        let start = Date.now.addingTimeInterval(lead)
        return start < airing.end.addingTimeInterval(-lead) ? start : nil
    }

    private func load(_ airing: Airing) async throws -> LoadedAiring {
        let (source, cap) = airing.isFiller ? try await commercialSource(for: airing.item)
                                            : try await programmeSource(for: airing)
        let method = source.method == .directPlay ? "direct play" : "streamed by Jellyfin"
        let label = airing.isFiller ? "Commercial"
            : fixedProgramme?.airing == airing ? "This programme only"
            : quality == .auto ? "Auto" : quality.label
        let reasons = source.transcodeReasons.isEmpty ? nil : source.transcodeReasons.joined(separator: ",")
        let item = AVPlayerItem(url: source.url)
        // Stop at the scheduled length, so programmes and commercials keep to
        // the schedule even when a file runs a little longer than Jellyfin says,
        // and a commercial still playing is cut off when the next programme starts.
        item.forwardPlaybackEndTime = CMTime(seconds: airing.length, preferredTimescale: 600)
        if source.reencodesVideo { item.preferredForwardBufferDuration = Self.reencodedForwardBuffer }
        return LoadedAiring(airing: airing,
                            item: item,
                            transcodeSessionID: source.method == .hls ? source.playSessionID : nil,
                            description: "\(label) · up to \(Self.mbps(cap)) · \(method)",
                            cap: cap,
                            reencodesVideo: source.reencodesVideo,
                            transcodeReasons: reasons)
    }

    /// Programmes use the viewer's quality setting, or the programme fix's cap.
    private func programmeSource(for airing: Airing) async throws -> (PlaybackSource, cap: Int) {
        let fixedCap = fixedProgramme.flatMap { $0.airing == airing ? $0.cap : nil }
        let cap = if let fixedCap { fixedCap } else { await maxBitrate() }
        return (try await client.playbackSource(for: airing.item.id, maxBitrate: cap), cap)
    }

    /// Commercials never make the server re-encode video, and never start a
    /// speed test. They play the original file, as-is or at most remuxed,
    /// which costs the server almost nothing. They're asked for with no
    /// bitrate cap (the quality setting doesn't apply), so a clip is never
    /// re-encoded just for its bitrate. A clip that would need re-encoding
    /// anyway is skipped (`SkippedCommercial`): its time is blank. It's
    /// remembered for the rest of the session, so it isn't asked about again.
    private func commercialSource(for item: MediaItem) async throws -> (PlaybackSource, cap: Int) {
        guard !skippedCommercialIDs.contains(item.id) else { throw SkippedCommercial() }
        let cap = StreamingQuality.maximumBitrate
        let source = try await client.playbackSource(for: item.id, maxBitrate: cap)
        guard !source.reencodesVideo else {
            skippedCommercialIDs.insert(item.id)   // nothing to stop: a transcode only starts when the stream is requested
            throw SkippedCommercial()
        }
        return (source, cap)
    }

    /// The bitrate cap for the current quality setting.
    ///
    /// Fixed qualities return their cap and never measure. Auto returns its
    /// last measurement straight away, and schedules a background re-measure
    /// if there's none yet or it's over 10 minutes old. It only waits for a
    /// measurement after a playback failure.
    private func maxBitrate() async -> Int {
        if let fixed = quality.fixedBitrate { return fixed }

        if needsMeasurementFirst {
            needsMeasurementFirst = false
            cancelMeasurement()
            await measureBandwidth()
        } else if autoBitrate.map({ Date.now.timeIntervalSince($0.measuredAt) >= Self.autoRemeasureInterval }) ?? true {
            measureInBackground()
        }
        return autoBitrate?.bitsPerSecond ?? StreamingQuality.fallbackAutoBitrate
    }

    /// Runs the speed test after `backgroundMeasurementDelay`, unless one is already pending.
    private func measureInBackground() {
        guard quality == .auto, measurementTask == nil else { return }
        measurementTask = Task { [weak self] in
            try? await Task.sleep(for: Self.backgroundMeasurementDelay)
            guard !Task.isCancelled else { return }
            await self?.measureBandwidth()
            // A cancelled task leaves the slot alone: a newer one may be in it.
            if !Task.isCancelled { self?.measurementTask = nil }
        }
    }

    private func measureBandwidth() async {
        guard quality == .auto else { return }
        let measured = try? await client.measureBandwidth()
        // Dropped if cancelled, or if the viewer left Auto meanwhile.
        guard !Task.isCancelled, quality == .auto else { return }
        autoBitrate = (measured.map(StreamingQuality.autoBitrate(measured:)) ?? StreamingQuality.fallbackAutoBitrate, .now)
    }

    private func cancelMeasurement() {
        measurementTask?.cancel()
        measurementTask = nil
    }

    private static func mbps(_ bitsPerSecond: Int) -> String {
        (Double(bitsPerSecond) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + " Mbps"
    }

    private func seek(to offset: TimeInterval) {
        let tolerance = CMTime(seconds: 2, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: max(0, offset), preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func fail(_ error: (any Error)?, airing: Airing) {
        if let error = error as? JellyfinError, error == .unauthorized {
            stop()
            onUnauthorized?()
            return
        }
        let failedReencode = current.map { $0.airing == airing && $0.reencodesVideo && !airing.isFiller } ?? false
        let failedCap = current?.cap
        unloadEverything()
        self.airing = airing
        let delay = min(Self.maxRetryDelay, 5 * pow(2, Double(consecutiveFailures)))
        consecutiveFailures += 1
        if failedReencode, let failedCap {
            // Jellyfin couldn't re-encode fast enough: retry this programme with less work.
            stepDownAfterReencodeFailure(of: airing, from: failedCap)
        } else if quality == .auto {
            // The server or connection may be struggling: measure again before the retry.
            needsMeasurementFirst = true
        }
        status = .failed(message: FriendlyError.message(for: error), retryAt: .now.addingTimeInterval(delay))
    }

    /// 720p first, then a step lower each time, down to the lowest.
    private func stepDownAfterReencodeFailure(of airing: Airing, from cap: Int) {
        let hd720 = StreamingQuality.hd720.fixedBitrate!
        let lower = cap > hd720 ? hd720 : StreamingQuality.bitrate(below: cap) ?? StreamingQuality.lowestBitrate
        fixedProgramme = (airing, lower)
        programmeFix = lower == hd720 ? .hd720 : .stepDown
    }

    private func unloadEverything() {
        tuneTask?.cancel()
        tuneTask = nil
        standbyHandoff?.cancel()
        standbyHandoff = nil
        nextIsOnStandby = false
        for player in players {
            player.pause()
            player.removeAllItems()
            player.actionAtItemEnd = .advance
        }
        [current, next, afterBreak].compactMap { $0 }.forEach(release)
        current = nil
        next = nil
        afterBreak = nil
        preloadedBreakEnd = nil
        isPreparingNext = false
        isBuffering = false
        lastProgress = nil
        bufferingSince = nil
        streamDescription = nil   // don't show the previous stream's details while tuning
        diagnostics = nil
    }

    /// Tells Jellyfin to stop transcoding for an airing we've finished with.
    private func release(_ loaded: LoadedAiring) {
        guard let id = loaded.transcodeSessionID else { return }
        let client = client
        Task.detached { try? await client.stopTranscoding(playSessionID: id) }
    }
}

/// A commercial that would make the server re-encode video, so it isn't played.
struct SkippedCommercial: Error {}

/// Playback made no progress for `ChannelPlayer.stallTimeout` seconds.
struct StallError: LocalizedError {
    var errorDescription: String? {
        "The server isn't sending video fast enough. It may be busy, or unable to convert this programme in real time."
    }
}
