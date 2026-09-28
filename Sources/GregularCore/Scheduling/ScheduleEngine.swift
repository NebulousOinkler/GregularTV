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
/// Each run is worked out from the channel's key and the run number alone,
/// never from the run before, so any walk gives the same result. To find any
/// moment, the engine walks that run from its start, and the run before it
/// for what aired last: about two days of programmes, however big the
/// library or however many channels. It never builds a whole schedule, and
/// never replays from the epoch. Where one run meets the next (once a day):
/// - the next run's starting point is estimated, so a programme may repeat
///   or be skipped there;
/// - if the next run's first programme mustn't follow the last one (the
///   `SequenceRule`s), a programme that the rules allow takes its slot.
///
/// **Special rules** (`ScheduleRules`) apply on top of the strategy: what
/// may air straight after what, what the shuffle leaves out, and programmes
/// at set local times. A channel with set times runs on local days
/// (`RunCalendar`), and each pinned programme is a hard edge, like the end
/// of a run: programmes that wouldn't finish before it wait until after it,
/// and the time left before it is a break.
///
/// Each programme gets a *slot*. With `padTo` (every bundled channel uses
/// 30), a slot is rounded up to the next boundary, so every programme starts
/// on the half hour, and the time left over is commercials:
/// - **After an episode:** all of it, after the episode.
/// - **In a film:** a film's leftover can be up to half an hour. Up to 10
///   minutes goes after it; more is shared out evenly between breaks after
///   the film and one or two *mid-roll* breaks inside it (at a third and two
///   thirds, or halfway), each at most `longestMidRoll` (10 minutes). The
///   film airs as parts, each resuming where the last stopped (`mediaOffset`).
///   With commercials off, the breaks are the same, only blank, so the
///   schedule is identical either way.
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
    private let calendar: RunCalendar
    /// For each of the channel's `fixed` entries, what it can play.
    private let pinnedProgrammes: [[MediaItem]]
    private let pinRules: [any PinRule]
    /// What may air straight after what (`SequenceRule`s for programmes).
    private let programmeRules = ScheduleRules.sequenceRules(for: .programmes)
    /// Fills a gap before a pinned programme when nothing else within reach fits.
    private let shortestItem: MediaItem
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
        let contentRules = ScheduleRules.rules(of: (any ContentRule).self)
        let eligible = items.filter { item in
            channel.accepts(item) && item.duration > 0 && contentRules.allSatisfy { $0.keepsInShuffle(item, on: channel) }
        }
        guard let shortestItem = eligible.min(by: { ($0.duration, $0.id) < ($1.duration, $1.id) }) else { return nil }

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
        self.shortestItem = shortestItem
        self.shortestProgramme = Self.milliseconds(of: shortestItem.duration)
        self.calendar = RunCalendar(for: channel, length: runLength)
        self.pinnedProgrammes = channel.fixed.map { $0.programmes(in: items) }
        self.pinRules = channel.fixed.isEmpty ? [] : ScheduleRules.rules(of: (any PinRule).self)
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

    /// How long each run of this channel's schedule is.
    public var runDuration: TimeInterval { TimeInterval(runLength) / 1000 }

    /// What's on at `date` (a programme or a filler clip), and how far into it.
    public func tune(at date: Date) -> Tuning {
        let airings = slot(containing: date)
        let airing = airings.last { $0.start <= date } ?? airings[0]
        return Tuning(airing: airing, offset: date.timeIntervalSince(airing.start))
    }

    /// The programme whose slot contains `date`, even during its filler,
    /// as a whole: a film split by mid-roll breaks is one airing from its
    /// first part's start to its last part's end, and `slotEnd` is when the
    /// next programme starts. Use this for "what's on" displays such as the
    /// guide and channel list.
    public func programme(at date: Date) -> Airing {
        Self.wholeProgramme(in: slot(containing: date))
    }

    /// Every programme (whole, as `programme(at:)` gives them) whose slot
    /// overlaps `start..<end`, in order. For guide listings.
    public func programmes(from start: Date, to end: Date) -> [Airing] {
        guard start < end else { return [] }
        var walker = walker(from: start)
        var result: [Airing] = []
        while true {
            let slot = walker.nextSlot()
            guard slot[0].start < end else { break }
            let programme = Self.wholeProgramme(in: slot)
            if programme.slotEnd > start { result.append(programme) }
        }
        return result
    }

    /// A slot's programme as one airing, however many parts it's in.
    private static func wholeProgramme(in slot: [Airing]) -> Airing {
        let parts = slot.filter { !$0.isFiller }
        let first = parts[0]
        return Airing(item: first.item, start: first.start, end: parts[parts.count - 1].end,
                      slotEnd: slot[slot.count - 1].slotEnd, isFiller: false)
    }

    /// What's on screen at `date`: a programme, or a break after one (its
    /// commercials, or blank airtime) until the next. Use this wherever a
    /// channel is shown, so every view tells the two apart the same way.
    public func nowShowing(at date: Date) -> Onscreen {
        let programme = programme(at: date)
        guard date >= programme.end else { return .programme(programme) }
        return .inBreak(ended: programme, next: self.programme(at: programme.slotEnd))
    }

    /// The whole commercial break playing at `date`, from its first clip to
    /// the programme (or the film's next part) after it, or nil when no
    /// filler clip is playing. Each clip's own `slotEnd` is only the next
    /// clip's start, so use this for "Back at".
    public func commercialBreak(at date: Date) -> DateInterval? {
        let airings = slot(containing: date)
        guard let now = airings.lastIndex(where: { $0.start <= date }), airings[now].isFiller else { return nil }
        var first = now
        while first > 0, airings[first - 1].isFiller { first -= 1 }
        var last = now
        while last + 1 < airings.count, airings[last + 1].isFiller { last += 1 }
        return DateInterval(start: airings[first].start, end: airings[last].slotEnd)
    }

    /// Every airing (programme parts and filler clips) that overlaps
    /// `start..<end`, in order. The first one may have started before `start`.
    /// For listings of whole programmes, use `programmes(from:to:)`.
    public func airings(from start: Date, to end: Date) -> [Airing] {
        guard start < end else { return [] }
        var walker = walker(from: start)
        var result: [Airing] = []
        while true {
            let airings = walker.nextSlot()
            guard airings[0].start < end else { break }
            result += airings.filter { $0.slotEnd > start && $0.start < end }
        }
        return result
    }

    // MARK: - Runs and slots

    /// A walker from the start of the run containing `date`. Runs start at
    /// their `Join`, which can be a little after the calendar's midnight.
    private func walker(from date: Date) -> SlotWalker {
        let ms = milliseconds(since: channel.epoch, to: date)
        var run = calendar.run(containing: ms)
        var join = self.join(ofRun: run, after: lastProgramme(ofRun: run - 1))
        if ms < join.start {
            run -= 1
            join = self.join(ofRun: run, after: lastProgramme(ofRun: run - 1))
        }
        return SlotWalker(self, startingAt: run, join: join)
    }

    /// The last programme of `run`. A run is laid out on its own, and what
    /// aired before only changes how it starts (its `Join`), never what it
    /// takes from the strategy, so this is one run's walk, not a chain.
    private func lastProgramme(ofRun run: Int) -> MediaItem {
        var walker = SlotWalker(self, startingAt: run, join: nil)
        while true {
            let slot = walker.place()
            if walker.finishedRun { return slot.item }
        }
    }

    /// Where a run meets the one before. Normally nothing changes, but if the
    /// rules (`SequenceRule`) don't allow the run's first programme straight
    /// after the last one before it:
    /// - a programme they allow takes its slot, if one fits and may come
    ///   before the next; or else
    /// - the first slots are left out until one may follow, and their time
    ///   is a break after the run before's last programme.
    /// The rest of the run is the same either way, so every walk agrees.
    private struct Join {
        /// Takes the run's first slot.
        var standIn: MediaItem?
        /// How many of the run's first slots are left out.
        var leftOut = 0
        /// Where the run starts, after any slots left out.
        var start: Int64
    }

    /// The most slots a join leaves out looking for one that may follow. If
    /// none within that may (a channel with one programme), the rules give way.
    static let maxLeftOutAtJoin = 4

    /// How `run` joins the run before, whose last programme was `last`.
    private func join(ofRun run: Int, after last: MediaItem) -> Join {
        var walker = SlotWalker(self, startingAt: run, join: nil)
        var slot = walker.place()
        var join = Join(start: slot.start)
        guard !slot.isPinned, !programmeRules.allow(slot.item, after: last) else { return join }
        let next = walker.upcomingItem
        join.standIn = standIns(from: slot.start, to: slot.end, after: last, before: next).first
        guard join.standIn == nil else { return join }
        let kept = join
        repeat {
            join.leftOut += 1
            join.start = slot.end
            slot = walker.place()
            if slot.isPinned || programmeRules.allow(slot.item, after: last) { return join }
        } while join.leftOut < Self.maxLeftOutAtJoin
        return kept   // nothing within reach may follow: the rules give way
    }

    /// A programme's slot, in milliseconds since the epoch: from its start to
    /// where the next programme starts.
    private struct Slot {
        let item: MediaItem
        let start: Int64
        var end: Int64
        /// A programme at a set time.
        var isPinned = false
    }

    /// The programmes at set times in `run`, in order. One is left out that
    /// day if it would overlap the one before it (a programme from the day
    /// before counts), or if it's the same one again with no room for
    /// anything between (the sequence rules win).
    private func pinnedSlots(inRun run: Int) -> [Slot] {
        pinnedSlots(onDay: run, after: pinnedSlots(onDay: run - 1, after: nil).last)
    }

    /// `run`'s programmes at set times, checked in order against each other
    /// and against `earlier`, the day before's last. (That one is checked
    /// against its own day only, so days don't chain.)
    private func pinnedSlots(onDay run: Int, after earlier: Slot?) -> [Slot] {
        guard !pinRules.isEmpty, let day = calendar.day(run) else { return [] }
        var slots: [Slot] = []
        for pin in pinRules.flatMap({ $0.pins(on: channel, day: day, programmes: pinnedProgrammes) }).sorted(by: { $0.start < $1.start }) {
            let start = milliseconds(since: channel.epoch, to: pin.start)
            let slot = Slot(item: pin.item, start: start,
                            end: Self.slotEnd(of: pin.item, startingAt: start, padToMinutes: channel.padToMinutes),
                            isPinned: true)
            if let last = slots.last ?? earlier, !mayFollow(last, slot) { continue }
            slots.append(slot)
        }
        return slots
    }

    /// Whether a programme at a set time can come after an earlier one: it
    /// doesn't overlap it, and either the rules allow it straight after, or a
    /// programme they allow between the two fits there.
    private func mayFollow(_ earlier: Slot, _ later: Slot) -> Bool {
        guard later.start >= earlier.end else { return false }
        return programmeRules.allow(later.item, after: earlier.item)
            || standIns(from: earlier.end, to: later.start, after: earlier.item, before: later.item).first != nil
    }

    /// The channel's programmes that could fill the time from `start` to
    /// `end`, when the stream has nothing suitable: they fit, and the rules
    /// allow them straight after `previous` and straight before `next`.
    private func standIns(from start: Int64, to end: Int64, after previous: MediaItem?,
                          before next: MediaItem?) -> LazyFilterSequence<[MediaItem]> {
        content.items.lazy.filter { item in
            start + Self.milliseconds(of: item.duration) <= end
                && (previous.map { self.programmeRules.allow(item, after: $0) } ?? true)
                && (next.map { self.programmeRules.allow($0, after: item) } ?? true)
        }
    }

    /// How `run` is laid out from its start, on its own: at its place in the
    /// calendar, but later if a pinned programme from the day before is still
    /// on, and at the day's first pinned programme if nothing fits before it.
    /// When exactly one programme fits there, it's `onlyFiller`: it fills
    /// that time as a stand-in, so the strategy's stream starts the same way
    /// whatever happens at the join.
    private func opening(ofRun run: Int) -> (start: Int64, onlyFiller: MediaItem?) {
        var start = calendar.start(ofRun: run)
        guard !pinRules.isEmpty else { return (start, nil) }
        if let running = pinnedSlots(onDay: run - 1, after: nil).last?.end, running > start { start = running }
        guard let first = pinnedSlots(inRun: run).first(where: { $0.start >= start }) else { return (start, nil) }
        let fillers = Array(standIns(from: start, to: first.start, after: nil, before: first.item).prefix(2))
        switch fillers.count {
        case 0: return (first.start, nil)
        case 1: return (start, fillers[0])
        default: return (start, nil)
        }
    }

    /// The programme and any filler after it, in the slot that contains `date`.
    private func slot(containing date: Date) -> [Airing] {
        var walker = walker(from: date)
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
        let position = Int((Double(calendar.start(ofRun: run)) / averageSlotLength).rounded(.down))
        return strategy.programmes(from: content, startingAt: position, rng: SeededRandom(seed: key, cycle: run))
    }

    /// How many too-long programmes the end of a run may pass over, looking
    /// for one that finishes in time.
    static let maxSkipsAtRunEnd = 15

    /// Lays out the slots of one run after another, starting at the beginning
    /// of a run. Programmes follow each other back to back; the end of a run
    /// and each programme at a set time are hard edges. Each run is laid out
    /// on its own; only its `Join` depends on the run before.
    private struct SlotWalker {
        let schedule: ChannelSchedule
        private var run: Int
        /// Milliseconds since the epoch where the next slot starts.
        private var cursor: Int64 = 0
        /// Where this run ends, as far as choosing programmes goes. The last
        /// slot reaches on to the next run's `Join`.
        private var runEnd: Int64 = 0
        /// This run's programmes at set times still to come.
        private var pins: [Slot] = []
        /// The next run's first programme, when it's at a set time right at this run's end.
        private var pinAtRunEnd: Slot?
        private var programmes: RuledStream
        /// This run's commercials, dealt break after break.
        private var commercials: CommercialQueue
        /// Chosen, but only placed once we know whether it's the last before an edge.
        private var upcoming: Slot?
        /// Fills the time before this run's first pinned programme, if only one can.
        private var openingFiller: MediaItem?
        /// How this run meets the one before; nil lays runs out on their own.
        private var join: Join?
        /// Whether joins are worked out as runs end (false while working one out).
        private let joinsRuns: Bool
        /// The next slot is its run's first.
        private var opensRun = true
        /// True when the slot just placed was its run's last.
        private(set) var finishedRun = false

        /// - Parameter join: how the first run meets the one before, or nil to
        ///   lay runs out on their own (to work out a `Join`, or a run's last programme).
        init(_ schedule: ChannelSchedule, startingAt run: Int, join: Join?) {
            self.schedule = schedule
            self.run = run
            self.join = join
            joinsRuns = join != nil
            programmes = RuledStream(AnyIterator { nil }, for: .programmes)
            commercials = CommercialQueue(AnyIterator { nil })
            begin(run)
        }

        /// The next slot's airings: its programme first, then any filler clips.
        /// Slots a join leaves out are skipped, clips and all.
        mutating func nextSlot() -> [Airing] {
            var slot = place()
            while leftOut > 0 {
                leftOut -= 1
                slot = place()
            }
            return schedule.airingsInSlot(slot.item, slotStart: slot.start, slotEnd: slot.end, commercials: &commercials)
        }

        /// The programme after the slot just placed, if it's known yet.
        var upcomingItem: MediaItem? { upcoming?.item }

        /// Slots of this run still to leave out at its join.
        private var leftOut = 0

        /// Lays out the next slot.
        mutating func place() -> Slot {
            var slot = upcoming ?? firstSlotOfRun()
            let standIn = opensRun ? join?.standIn : nil
            opensRun = false
            let before = programmes.previous
            programmes.aired(slot.item)
            upcoming = following()
            // Nothing else fits before the edge: the leftover joins this slot.
            if upcoming == nil, let pin = edgePin, !programmes.allows(pin.item, after: slot.item) {
                // The last before a programme at a set time that mustn't follow it:
                // another fills the rest of the gap, or else (unless it's at a set
                // time itself) takes its place.
                if let item = schedule.standIns(from: slot.end, to: edge, after: slot.item, before: pin.item).first {
                    upcoming = Slot(item: item, start: slot.end, end: edge)
                    cursor = edge
                } else if !slot.isPinned {
                    slot = lastBefore(pin, instead: slot, after: before)
                }
            }
            finishedRun = upcoming == nil && pins.isEmpty
            if upcoming == nil {
                // The run's last slot reaches on to where the next run starts.
                slot.end = finishedRun && joinsRuns ? nextJoin(after: slot.item).start : edge
                cursor = slot.end
                upcoming = following()   // the programme at a set time, if that's the edge
            }
            if let standIn { slot = Slot(item: standIn, start: slot.start, end: slot.end) }
            if finishedRun { opensRun = true }
            return slot
        }

        /// Works out, and keeps for when it starts, how the next run meets this one.
        private mutating func nextJoin(after last: MediaItem) -> Join {
            let next = schedule.join(ofRun: run + 1, after: last)
            join = next
            return next
        }

        /// The next pinned programme's start, or the end of the run.
        private var edge: Int64 { pins.first?.start ?? runEnd }

        /// The programme at a set time right at the edge, if there is one.
        private var edgePin: Slot? { pins.first ?? pinAtRunEnd }

        /// Starts `run` afresh: nothing carries over from the run before.
        private mutating func begin(_ run: Int) {
            self.run = run
            let opening = schedule.opening(ofRun: run)
            cursor = opening.start
            openingFiller = opening.onlyFiller
            leftOut = join?.leftOut ?? 0
            runEnd = schedule.opening(ofRun: run + 1).start
            pins = schedule.pinnedSlots(inRun: run).filter { $0.start >= cursor }
            pinAtRunEnd = schedule.pinnedSlots(inRun: run + 1).first { $0.start == runEnd }
            programmes = RuledStream(schedule.stream(forRun: run), for: .programmes)
            commercials = CommercialQueue(schedule.commercials(forRun: run))
        }

        /// The first slot of the next run. A run is at least as long as the
        /// longest slot, so its first programme always fits unless a pinned
        /// programme comes first.
        private mutating func firstSlotOfRun() -> Slot {
            if cursor >= runEnd { begin(run + 1) }
            if let item = openingFiller {
                openingFiller = nil
                defer { cursor = edge }
                return Slot(item: item, start: cursor, end: edge)
            }
            if let slot = following() { return slot }
            // Nothing within reach fits before the first pinned programme: one of
            // the channel's that the rules allow does, or else the shortest.
            // (Without pins, only a broken strategy gets here.)
            assert(!pins.isEmpty, "Strategy '\(type(of: schedule.strategy).id)' produced nothing for a run")
            let item = edgePin.flatMap { schedule.standIns(from: cursor, to: edge, after: nil, before: $0.item).first }
                ?? schedule.shortestItem
            let end = min(edge, ChannelSchedule.slotEnd(of: item, startingAt: cursor, padToMinutes: schedule.channel.padToMinutes))
            defer { cursor = end }
            return Slot(item: item, start: cursor, end: end)
        }

        /// The programme at a set time starting now, or else the next one from
        /// the stream that finishes before the edge. Nil when none does.
        private mutating func following() -> Slot? {
            if let pin = pins.first, pin.start <= cursor {
                pins.removeFirst()
                cursor = pin.end
                return pin
            }
            return take(before: edge, pinned: edgePin?.item)
        }

        /// The next programme that finishes by `edge`. Programmes passed over
        /// on the way wait, in order, for after the edge (at the end of a run
        /// they're dropped). Before a programme at a set time (`pinned`), one
        /// the rules don't allow straight before it only goes if an allowed one
        /// could still follow it; with `last`, none can.
        private mutating func take(before edge: Int64, pinned: MediaItem?, last: Bool = false) -> Slot? {
            guard edge - cursor >= schedule.shortestProgramme else { return nil }
            let mayReorder = type(of: schedule.strategy).mayReorderToFit
            var passedOver: [MediaItem] = []
            defer { programmes.putBack(passedOver) }
            while let item = programmes.next() {
                let length = ChannelSchedule.milliseconds(of: item.duration)
                // A show that was passed over keeps its place: its later episodes wait too.
                let showIsWaiting = passedOver.contains { $0.seriesKey == item.seriesKey }
                let fits = cursor + length <= edge && !showIsWaiting
                if fits {
                    let end = min(edge, ChannelSchedule.slotEnd(of: item, startingAt: cursor,
                                                                padToMinutes: schedule.channel.padToMinutes))
                    // Before a programme at a set time that mustn't follow this one,
                    // it can only go if something allowed could still fit after it.
                    let mayPrecedePin = pinned.map { pin in
                        programmes.allows(pin, after: item)
                            || !(last || edge - end < schedule.shortestProgramme)
                            && schedule.standIns(from: end, to: edge, after: item, before: pin).first != nil
                    } ?? true
                    if mayPrecedePin {
                        defer { cursor = end }
                        return Slot(item: item, start: cursor, end: end)
                    }
                }
                passedOver.append(item)
                // Held back by a rule (or replacing one that was), the search goes
                // on whatever the strategy; otherwise passing over needs `mayReorderToFit`.
                if (!fits && !mayReorder && !last) || passedOver.count > ChannelSchedule.maxSkipsAtRunEnd { return nil }
            }
            return nil
        }

        /// `slot` turned out to be the last before `pin`, which mustn't follow
        /// it: another programme takes its place, and it waits. First choice is
        /// the stream's next that fits; failing that, any of the channel's
        /// programmes that fits (`standIns`). With neither, the rules give way.
        private mutating func lastBefore(_ pin: Slot, instead slot: Slot, after before: MediaItem?) -> Slot {
            cursor = slot.start
            programmes.aired(before)
            programmes.putBack([slot.item])
            var chosen = take(before: edge, pinned: pin.item, last: true)
            if chosen == nil {
                programmes.withdraw(slot.item)
                chosen = schedule.standIns(from: slot.start, to: edge, after: before, before: pin.item).first
                    .map { Slot(item: $0, start: slot.start, end: edge) } ?? slot
            }
            programmes.aired(chosen!.item)
            return chosen!
        }
    }

    /// A run's commercial stream, where a clip can be looked at before it's
    /// taken: one that doesn't fit this break waits to open the next.
    private struct CommercialQueue {
        private var stream: RuledStream
        private var waiting: MediaItem?

        init(_ clips: AnyIterator<MediaItem>) {
            stream = RuledStream(clips, for: .commercials)
        }

        mutating func peek() -> MediaItem? {
            if waiting == nil { waiting = stream.next() }
            return waiting
        }

        mutating func take() {
            if let waiting { stream.aired(waiting) }
            waiting = nil
        }
    }

    /// A gap this long or shorter (milliseconds) gets no commercials: the
    /// screen stays blank, with the "Up next" card, until the next programme.
    static let shortestBreak: Int64 = 60_000

    /// The longest a mid-roll break inside a film can be (milliseconds). A
    /// film's leftover up to this long all goes after it; more is shared with
    /// one mid-roll (up to twice this) or two.
    public static let longestMidRoll: Int64 = 10 * 60_000
    /// The most mid-roll breaks in one film.
    public static let maxMidRolls = 2
    /// An episode at least this long (milliseconds) gets mid-rolls like a
    /// film; a shorter one has its whole leftover after it.
    public static let longEpisode: Int64 = 60 * 60_000
    /// The least of a film that plays between two breaks (milliseconds), so
    /// mid-rolls are never close together. A short film gets fewer mid-rolls,
    /// or none, and the rest of its leftover goes after it.
    public static let shortestPart: Int64 = 15 * 60_000

    /// The most commercials in one break (milliseconds). A longer break (after
    /// an episode that ends well before the half hour, a short film, or at the
    /// end of a day) is blank after this, with the "Up next" card.
    public static let longestCommercialRun: Int64 = 20 * 60_000

    /// The end of every break is blank for this long (milliseconds), with the
    /// "Up next" card, before the next programme: no commercial plays into it.
    public static let upNextLead: Int64 = 15_000

    /// The programme, then any filler clips, in one slot; a film with
    /// mid-roll breaks is its parts with clips between. Each airing's
    /// `slotEnd` is the next one's start; the last one owns any leftover gap.
    ///
    /// Commercials are dealt from the run's stream (see `GapFiller`), break
    /// after break, the same way in a mid-roll as after the programme:
    /// - A gap of a minute or less gets none (`shortestBreak`).
    /// - The last 15 seconds before the programme (or the film's next part)
    ///   get none either (`upNextLead`): they're blank, with the "Up next" card.
    /// - No more than 20 minutes of commercials (`longestCommercialRun`); any
    ///   more of the break is blank, with the "Up next" card.
    /// - Clips play back to back. When one ends, the next only starts if at
    ///   least half of it will play before commercials stop (the last 15
    ///   seconds, or 20 minutes in). Otherwise it waits to open the next
    ///   break, and the rest of this gap is blank.
    /// - A clip still playing when commercials stop is cut off (`end` is the cut).
    private func airingsInSlot(_ item: MediaItem, slotStart: Int64, slotEnd: Int64,
                                   commercials: inout CommercialQueue) -> [Airing] {
        let length = Self.milliseconds(of: item.duration)
        let gap = slotEnd - slotStart - length
        let midRolls = midRollCount(for: item, length: length, gap: gap)
        let midRollLength = min(Self.longestMidRoll, gap / Int64(midRolls + 1))
        let partLength = length / Int64(midRolls + 1)

        var pieces: [Piece] = []
        var t = slotStart
        for part in 0...midRolls {
            let isLast = part == midRolls
            let thisPart = isLast ? length - partLength * Int64(midRolls) : partLength
            pieces.append(Piece(item: item, start: t, end: t + thisPart, isFiller: false,
                                offset: partLength * Int64(part)))
            t += thisPart
            let breakEnd = isLast ? slotEnd : t + midRollLength
            pieces += clips(from: t, to: breakEnd, commercials: &commercials)
            t = breakEnd
        }

        let programmeStart = date(atMilliseconds: slotStart)
        return pieces.indices.map { i in
            let piece = pieces[i]
            let next = i + 1 < pieces.count ? pieces[i + 1].start : slotEnd
            return Airing(item: piece.item,
                          start: date(atMilliseconds: piece.start),
                          end: date(atMilliseconds: piece.end),
                          slotEnd: date(atMilliseconds: next),
                          isFiller: piece.isFiller,
                          mediaOffset: TimeInterval(piece.offset) / 1000,
                          programmeStart: piece.isFiller ? nil : programmeStart)
        }
    }

    private struct Piece {
        let item: MediaItem
        let start: Int64
        let end: Int64
        let isFiller: Bool
        var offset: Int64 = 0
    }

    /// How many mid-roll breaks a programme gets, for a leftover `gap`:
    /// none for an episode under an hour (`longEpisode`); for a film or a
    /// long episode, none up to 10 minutes, one up to 20,
    /// else two, but only as many as leave every part at least
    /// `shortestPart` long. The same with commercials on or off (off, they're
    /// blank), so the schedule doesn't change with the setting.
    private func midRollCount(for item: MediaItem, length: Int64, gap: Int64) -> Int {
        guard channel.padToMinutes != nil, item.kind != .episode || length >= Self.longEpisode,
              gap > Self.longestMidRoll else { return 0 }
        let wanted = Int((gap - 1) / Self.longestMidRoll)
        let roomFor = Int(length / Self.shortestPart) - 1
        return max(0, min(Self.maxMidRolls, wanted, roomFor))
    }

    /// The clips for one break, from `start` to the programme at `end`.
    private func clips(from start: Int64, to end: Int64, commercials: inout CommercialQueue) -> [Piece] {
        guard end - start > Self.shortestBreak else { return [] }
        let commercialsEnd = min(end - Self.upNextLead, start + Self.longestCommercialRun)
        var result: [Piece] = []
        var t = start
        while t < commercialsEnd, let clip = commercials.peek() {
            let length = Self.milliseconds(of: clip.duration)
            // At least half of it must play, or it doesn't start.
            guard (commercialsEnd - t) * 2 >= length else { break }
            commercials.take()
            // Up next is on time: a clip still playing is cut off.
            let clipEnd = min(t + length, commercialsEnd)
            result.append(Piece(item: clip, start: t, end: clipEnd, isFiller: true))
            t = clipEnd
        }
        return result
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
    /// the epoch): at the next `padTo` boundary, or with no `padTo`, as soon
    /// as it ends.
    static func slotEnd(of item: MediaItem, startingAt start: Int64, padToMinutes: Int?) -> Int64 {
        let end = start + milliseconds(of: item.duration)
        guard let pad = padToMinutes, pad > 0 else { return end }
        let unit = Int64(pad) * 60_000
        return -floorDivide(-end, unit) * unit   // rounded up, before the epoch too
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
