import Foundation

/// Works out what a channel is showing at any moment, and produces guide
/// entries. It's a pure function of the channel config, the items and the
/// clock, so nothing is stored (see PLAN.md §2 and §6).
///
/// **Time model: runs.**
/// - From `channel.epoch`, time is split into *runs* of a day (longer only if
///   a single programme needs it).
/// - Each run has one stream from the channel's strategy (an endless
///   generator, like Python's). Programmes are pulled from it and played back
///   to back, so nothing repeats or is skipped within a run.
/// - Near the end of a run, a programme that wouldn't finish in time is passed
///   over for one that does, if the strategy allows. Whatever time is left
///   becomes a gap after the run's last programme, like padding, which the
///   channel's `GapFiller` may fill.
///
/// Each run is worked out from the channel's key and the run number alone.
/// To find any moment, the engine walks at most from the start of that run:
/// about a day of programmes, however big the library or however many
/// channels. It never builds a whole schedule, and never replays from the
/// epoch. The one approximation: where one run meets the next (once a day),
/// the next run's starting point is estimated, so one programme may repeat
/// or be skipped there.
///
/// Each programme gets a *slot*. With `padTo`, a slot is rounded up to the
/// next boundary and the gap is part of it (a break):
/// - **After an episode, always.** Episodes keep the channel on its half-hour
///   lines, with commercials after every one.
/// - **After anything else (a film), only when the gap is `longestBreak`
///   (10 minutes) or shorter.** A longer gap isn't filled: the next programme
///   starts straight away, off the boundary, and the gap after *it* is looked
///   at the same way. So a film that runs a little past the hour is followed
///   by the next programme, not by half an hour of commercials, and an
///   episode after it brings the channel back to the half hour.
/// The last slot in a run also takes the run's leftover time.
public struct ChannelSchedule: Sendable {
    /// Runs are at least this long.
    public static let minimumRunLength: TimeInterval = 24 * 3600
    /// Run lengths are rounded up to a multiple of this, so runs start on
    /// half-hour boundaries (relative to the epoch).
    static let runRounding: Int64 = 30 * 60_000

    public let channel: Channel
    /// The schedule code this channel was built with.
    public let code: ScheduleCode
    /// This channel's key from the code (see `ScheduleCode.key(forChannelSeed:)`).
    /// Every random choice on the channel comes from it.
    private let key: UInt64
    private let content: ChannelContent
    private let strategy: any ScheduleStrategy
    private let filler: any GapFiller
    private let fillerPool: [MediaItem]
    /// Milliseconds.
    private let runLength: Int64
    /// The shortest programme: a run with less than this left has no room for another.
    private let shortestProgramme: Int64
    private let averageSlotLength: Double
    /// Estimated commercials per run, for starting each run's commercial stream.
    private let clipsPerRun: Double

    /// Returns nil when no items match the channel, or none have a runtime.
    /// Those channels are hidden.
    /// - Parameters:
    ///   - fillerPool: clips the channel's `GapFiller` may use.
    ///   - code: the schedule code shared by all channels. The same code gives
    ///     the same schedule everywhere.
    public init?(channel: Channel, items: [MediaItem], fillerPool: [MediaItem] = [], code: ScheduleCode = .standard) {
        guard let strategy = StrategyRegistry.strategy(withID: channel.strategyID) else { return nil }
        self.init(channel: channel, items: items, fillerPool: fillerPool, code: code, strategy: strategy)
    }

    /// Takes an explicit strategy, so tests can inject one.
    init?(channel: Channel, items: [MediaItem], fillerPool: [MediaItem], code: ScheduleCode = .standard,
          strategy: any ScheduleStrategy) {
        guard let filler = GapFillerRegistry.filler(withID: channel.fillerID) else { return nil }
        let eligible = items.filter { channel.accepts($0) && $0.duration > 0 }
        guard !eligible.isEmpty else { return nil }

        self.channel = channel
        self.code = code
        self.key = code.key(forChannelSeed: channel.seed)
        self.content = ChannelContent(items: eligible, seed: key)
        self.strategy = strategy
        self.filler = filler
        // Numbered alphabetically, like the shows.
        let pool = fillerPool.filter { $0.duration > 0 }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        self.fillerPool = pool

        let slots = eligible.map { Self.slotLength(of: $0, padToMinutes: channel.padToMinutes) }
        let minimum = Int64(Self.minimumRunLength * 1000)
        let unit = Self.runRounding
        self.runLength = (max(minimum, slots.max() ?? minimum) + unit - 1) / unit * unit
        self.shortestProgramme = eligible.map { Self.milliseconds(of: $0.duration) }.min() ?? 1
        // As if each started on a boundary: only a guide to where each run's stream starts.
        let typicalSlots = eligible.map {
            Self.slotEnd(of: $0, startingAt: 0, padToMinutes: channel.padToMinutes)
        }
        self.averageSlotLength = Double(typicalSlots.reduce(0, +)) / Double(typicalSlots.count)
        // Roughly how many commercials air in a run: the share of a slot that's
        // gap, over the run, divided by the average clip. Only used to guess
        // where each run's commercial stream starts.
        let averageLength = Double(eligible.reduce(0) { $0 + Self.milliseconds(of: $1.duration) }) / Double(eligible.count)
        let averageClip = pool.isEmpty ? 1 : Double(pool.reduce(0) { $0 + Self.milliseconds(of: $1.duration) }) / Double(pool.count)
        self.clipsPerRun = Double(runLength) * max(0, 1 - averageLength / averageSlotLength) / averageClip
    }

    /// Number of distinct programmes the channel can play.
    public var itemCount: Int { content.items.count }

    /// How long each run of this channel's schedule is.
    public var runDuration: TimeInterval { TimeInterval(runLength) / 1000 }

    /// What's on at `date` (a programme or a filler clip), and how far into it.
    public func tune(at date: Date) -> Tuning {
        let airings = slot(containing: date)
        let airing = airings.last { $0.start <= date } ?? airings[0]
        return Tuning(airing: airing, offset: date.timeIntervalSince(airing.start))
    }

    /// The programme whose slot contains `date`, even during its filler.
    /// Use this for "what's on" displays such as the guide and channel list.
    public func programme(at date: Date) -> Airing {
        slot(containing: date)[0]
    }

    /// What's on screen at `date`: a programme, or a break after one (its
    /// commercials, or blank airtime) until the next. Use this wherever a
    /// channel is shown, so every view tells the two apart the same way.
    public func nowShowing(at date: Date) -> Onscreen {
        let airings = slot(containing: date)
        let programme = airings[0]
        guard date >= programme.end, let slotEnd = airings.last?.slotEnd else { return .programme(programme) }
        return .inBreak(ended: programme, next: slot(containing: slotEnd)[0])
    }

    /// The whole commercial break playing at `date`, from its first clip to
    /// the next programme, or nil when no filler clip is playing. Each clip's
    /// own `slotEnd` is only the next clip's start, so use this for "Back at".
    public func commercialBreak(at date: Date) -> DateInterval? {
        let airings = slot(containing: date)
        guard let now = airings.last(where: { $0.start <= date }), now.isFiller,
              let first = airings.first(where: \.isFiller), let last = airings.last else { return nil }
        return DateInterval(start: first.start, end: last.slotEnd)
    }

    /// Every airing that overlaps `start..<end`, in order. The first one may
    /// have started before `start`. Leave out filler clips for guide listings.
    public func airings(from start: Date, to end: Date, includingFillers: Bool = true) -> [Airing] {
        guard start < end else { return [] }
        var walker = SlotWalker(self, startingAt: runIndex(containing: start))
        var result: [Airing] = []
        while true {
            let airings = walker.nextSlot()
            guard airings[0].start < end else { break }
            result += airings.filter { (includingFillers || !$0.isFiller) && $0.slotEnd > start && $0.start < end }
        }
        return result
    }

    // MARK: - Runs and slots

    private func runIndex(containing date: Date) -> Int {
        Int(Self.floorDivide(milliseconds(since: channel.epoch, to: date), runLength))
    }

    /// The programme and any filler after it, in the slot that contains `date`.
    private func slot(containing date: Date) -> [Airing] {
        var walker = SlotWalker(self, startingAt: runIndex(containing: date))
        while true {
            let airings = walker.nextSlot()
            if let last = airings.last, last.slotEnd > date { return airings }
        }
    }

    /// The filler's stream of commercials for one run, starting at an estimate
    /// of how many aired before it, so the order carries on from the day before.
    private func commercials(forRun run: Int) -> AnyIterator<MediaItem> {
        guard !fillerPool.isEmpty else { return AnyIterator { nil } }
        let position = Int((Double(run) * clipsPerRun).rounded(.down))
        return filler.clips(from: fillerPool, for: content, startingAt: position)
    }

    /// The strategy's stream for one run. It starts at an estimate of how many
    /// programmes aired before the run, so sequences carry on from the day before.
    private func stream(forRun run: Int) -> AnyIterator<MediaItem> {
        let runStart = Int64(run) * runLength
        let position = Int((Double(runStart) / averageSlotLength).rounded(.down))
        return strategy.programmes(from: content, startingAt: position, rng: SeededRandom(seed: key, cycle: run))
    }

    /// How many too-long programmes the end of a run may pass over, looking
    /// for one that finishes in time.
    static let maxSkipsAtRunEnd = 15

    /// Lays out the slots of one run after another, starting at the beginning
    /// of a run. Programmes follow each other back to back; only the end of a
    /// run is a hard edge.
    private struct SlotWalker {
        let schedule: ChannelSchedule
        private var run: Int
        private var programmes: AnyIterator<MediaItem>
        /// Milliseconds since the epoch where the next slot starts.
        private var cursor: Int64
        /// Pulled, but only placed once we know whether it's the run's last slot.
        private var upcoming: (item: MediaItem, start: Int64, end: Int64)?
        /// This run's commercials, dealt break after break.
        private var commercials: CommercialQueue

        init(_ schedule: ChannelSchedule, startingAt run: Int) {
            self.schedule = schedule
            self.run = run
            programmes = schedule.stream(forRun: run)
            commercials = CommercialQueue(schedule.commercials(forRun: run))
            cursor = Int64(run) * schedule.runLength
        }

        /// The next slot's airings: its programme first, then any filler clips.
        mutating func nextSlot() -> [Airing] {
            var slot = upcoming ?? takeFirstOfRun()
            upcoming = take()
            // Nothing else fits before the run ends: the leftover joins this slot.
            if upcoming == nil {
                slot.end = runEnd
                cursor = runEnd
            }
            return schedule.airingsInSlot(slot.item, slotStart: slot.start, slotEnd: slot.end, commercials: &commercials)
        }

        private var runEnd: Int64 { Int64(run + 1) * schedule.runLength }

        /// Starts the next run. A run is at least as long as the longest slot,
        /// so its first programme always fits.
        private mutating func takeFirstOfRun() -> (item: MediaItem, start: Int64, end: Int64) {
            if cursor >= runEnd {
                run += 1
                programmes = schedule.stream(forRun: run)
                commercials = CommercialQueue(schedule.commercials(forRun: run))
                cursor = Int64(run) * schedule.runLength
            }
            if let slot = take() { return slot }
            // Only a broken strategy gets here.
            assertionFailure("Strategy '\(type(of: schedule.strategy).id)' produced nothing for a run")
            let item = schedule.content.items[ChannelContent.wrap(run, schedule.content.items.count)]
            cursor = runEnd
            return (item, runEnd - schedule.runLength, runEnd)
        }

        /// The next programme that finishes before the run ends, or nil when
        /// none does. Only near the end of a run does anything get passed over.
        private mutating func take() -> (item: MediaItem, start: Int64, end: Int64)? {
            guard runEnd - cursor >= schedule.shortestProgramme else { return nil }
            let mayReorder = type(of: schedule.strategy).mayReorderToFit
            var passedOver: [MediaItem] = []
            while let item = programmes.next() {
                let length = ChannelSchedule.milliseconds(of: item.duration)
                // A show that was passed over keeps its place: its later episodes wait too.
                let showIsWaiting = passedOver.contains { $0.seriesKey == item.seriesKey }
                if cursor + length <= runEnd, !showIsWaiting {
                    let end = min(runEnd, ChannelSchedule.slotEnd(of: item, startingAt: cursor,
                                                                  padToMinutes: schedule.channel.padToMinutes))
                    defer { cursor = end }
                    return (item, cursor, end)
                }
                passedOver.append(item)
                if !mayReorder || passedOver.count > ChannelSchedule.maxSkipsAtRunEnd { return nil }
            }
            return nil
        }
    }

    /// A run's commercial stream, where a clip can be looked at before it's
    /// taken: one that doesn't fit this break waits to open the next.
    private struct CommercialQueue {
        private let stream: AnyIterator<MediaItem>
        private var waiting: MediaItem?

        init(_ stream: AnyIterator<MediaItem>) { self.stream = stream }

        mutating func peek() -> MediaItem? {
            if waiting == nil { waiting = stream.next() }
            return waiting
        }

        mutating func take() { waiting = nil }
    }

    /// A gap this long or shorter (milliseconds) gets no commercials: the
    /// screen stays blank, with the "Up next" card, until the next programme.
    static let shortestBreak: Int64 = 60_000

    /// With `padTo`, the longest gap (milliseconds) a film's slot is rounded up
    /// by. A film that would leave more is followed straight away by the next
    /// programme. (An episode's slot is always rounded up.)
    public static let longestBreak: Int64 = 10 * 60_000

    /// The end of every break is blank for this long (milliseconds), with the
    /// "Up next" card, before the next programme: no commercial plays into it.
    public static let upNextLead: Int64 = 15_000

    /// The programme, then any filler clips, in one slot. Each airing's
    /// `slotEnd` is the next one's start; the last one owns any leftover gap.
    ///
    /// Commercials are dealt from the run's stream (see `GapFiller`):
    /// - A gap of a minute or less gets none (`shortestBreak`).
    /// - The last 15 seconds before the next programme get none either
    ///   (`upNextLead`): they're blank, with the "Up next" card.
    /// - Clips play back to back. When one ends, the next only starts if at
    ///   least half of it will play before those last 15 seconds. Otherwise it
    ///   waits to open the next break, and the rest of this gap is blank.
    /// - A clip still playing when the last 15 seconds begin is cut off
    ///   (`end` is the cut).
    private func airingsInSlot(_ item: MediaItem, slotStart: Int64, slotEnd: Int64,
                                   commercials: inout CommercialQueue) -> [Airing] {
        let programmeEnd = slotStart + Self.milliseconds(of: item.duration)
        var pieces: [(item: MediaItem, start: Int64, end: Int64, isFiller: Bool)] = [(item, slotStart, programmeEnd, false)]

        if slotEnd - programmeEnd > Self.shortestBreak {
            let commercialsEnd = slotEnd - Self.upNextLead
            var t = programmeEnd
            while t < commercialsEnd, let clip = commercials.peek() {
                let length = Self.milliseconds(of: clip.duration)
                // At least half of it must play, or it doesn't start.
                guard (commercialsEnd - t) * 2 >= length else { break }
                commercials.take()
                // Up next is on time: a clip still playing is cut off.
                let clipEnd = min(t + length, commercialsEnd)
                pieces.append((clip, t, clipEnd, true))
                t = clipEnd
            }
        }

        return pieces.indices.map { i in
            let piece = pieces[i]
            let next = i + 1 < pieces.count ? pieces[i + 1].start : slotEnd
            return Airing(item: piece.item,
                          start: date(atMilliseconds: piece.start),
                          end: date(atMilliseconds: piece.end),
                          slotEnd: date(atMilliseconds: next),
                          isFiller: piece.isFiller)
        }
    }

    // MARK: - Time

    private func date(atMilliseconds ms: Int64) -> Date {
        channel.epoch.addingTimeInterval(TimeInterval(ms) / 1000)
    }

    private func milliseconds(since epoch: Date, to date: Date) -> Int64 {
        Int64((date.timeIntervalSince(epoch) * 1000).rounded(.down))
    }

    static func milliseconds(of duration: TimeInterval) -> Int64 {
        max(1, Int64((duration * 1000).rounded()))
    }

    /// Where a slot ends, for `item` starting at `start` (milliseconds since
    /// the epoch): at the next `padTo` boundary after an episode, or after
    /// anything else if that leaves `longestBreak` or less; otherwise as soon
    /// as it ends.
    static func slotEnd(of item: MediaItem, startingAt start: Int64, padToMinutes: Int?) -> Int64 {
        let end = start + milliseconds(of: item.duration)
        guard let pad = padToMinutes, pad > 0 else { return end }
        let unit = Int64(pad) * 60_000
        let boundary = -floorDivide(-end, unit) * unit   // rounded up, before the epoch too
        return item.kind == .episode || boundary - end <= longestBreak ? boundary : end
    }

    /// The longest a slot can be: the programme rounded up to a whole `padTo`.
    static func slotLength(of item: MediaItem, padToMinutes: Int?) -> Int64 {
        let length = milliseconds(of: item.duration)
        guard let pad = padToMinutes, pad > 0 else { return length }
        let unit = Int64(pad) * 60_000
        return (length + unit - 1) / unit * unit
    }

    /// Integer division that rounds towards negative infinity, so times
    /// before the epoch land in run -1, -2, and so on.
    static func floorDivide(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}
