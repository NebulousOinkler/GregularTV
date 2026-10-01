import Foundation

/// Works out what a channel is showing at any moment, and produces guide
/// entries. It's a pure function of the channel config, the items and the
/// clock, so nothing is stored (see PLAN.md §2 and §6).
///
/// **Two layers.** The *shared schedule* comes from the schedule code and
/// the channel alone, so everyone with the same code, channels and library
/// sees the same one. *Set times* (`channel.fixed`, from `channels.json` or a
/// household's `SetTimes`) are laid over it: during a set time's window its
/// programme is on; outside every window the shared schedule is, joined
/// partway through if a programme was already on. So two households that
/// share a code see the same programmes whenever neither has a set time.
///
/// **Time model: runs.** From `channel.epoch`, the shared schedule is split
/// into *runs* of a day (longer only if a single programme needs it):
/// - Each run has one stream from the channel's strategy (an endless
///   generator, like Python's). Programmes are pulled from it and played back
///   to back, so nothing repeats or is skipped within a run.
/// - Near the end of a run, a programme that wouldn't finish in time is passed
///   over for one that does, if the strategy allows. Whatever time is left
///   becomes a gap after the run's last programme, like padding, which the
///   channel's `GapFiller` may fill.
/// - Each run is laid out from the channel's key and the run number alone,
///   so any walk gives the same result. To find any moment, the engine walks
///   that run from its start, and the run before it for what aired last:
///   about two days of programmes, however big the library.
/// - Where runs meet, the next run's starting point is estimated, so a
///   programme may repeat or be skipped there; and if its first programme
///   mustn't follow the last one (`SequenceRule`s), its `Join` fixes that.
///
/// **Special rules** (`ScheduleRules`) apply on top of the strategy: what
/// may air straight after what, set times, and which airings a household's
/// set times cover with a stand-in.
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
    let content: ChannelContent
    let filler: any GapFiller
    let fillerPool: [MediaItem]
    private let strategy: any ScheduleStrategy
    /// What may air straight after what (`SequenceRule`s for programmes).
    let programmeRules = ScheduleRules.sequenceRules(for: .programmes)
    /// Which of the shared schedule's airings set times cover (`CoverRule`s).
    let coverRules = ScheduleRules.rules(of: (any CoverRule).self)
    /// Place set times (`PinRule`s).
    let pinRules = ScheduleRules.rules(of: (any PinRule).self)
    /// For each set time on the channel (`channel.fixed`), what it can play.
    let setProgrammes: [[MediaItem]]
    /// The longest set time's slot (milliseconds), to look back far enough for one still on.
    let longestSetTime: Int64
    /// The longest slot in the shared schedule (milliseconds).
    private let longestSlot: Int64
    /// Milliseconds.
    let runLength: Int64
    /// The shortest programme: a run with less than this left has no room for another.
    private let shortestProgramme: Int64
    private let averageSlotLength: Double
    /// Estimated commercials per run, for starting each run's commercial stream.
    let clipsPerRun: Double

    /// Returns nil when no items match the channel, or none have a runtime.
    /// Those channels are hidden.
    /// - Parameters:
    ///   - items: the library. Set times may name anything in it, even what
    ///     the channel doesn't otherwise play.
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
        let key = code.key(forChannelSeed: channel.seed)
        var content = ChannelContent(items: eligible, seed: key)
        let slotLength = { Self.slotLength(of: $0, padToMinutes: channel.padToMinutes) }
        let variety = ChannelVariety(shows: content.series, slotLength: slotLength)
        // A themed channel this library can't fill with enough variety is hidden.
        guard !channel.needsVariety || variety.fillsADay else { return nil }
        if let wanted = channel.filmShare {
            content.filmSlotShare = variety.filmSlotShare(forAirtime: variety.filmShare(wanted: wanted))
        }

        self.channel = channel
        self.code = code
        self.key = key
        self.content = content
        self.strategy = strategy
        self.filler = filler
        // Numbered alphabetically, like the shows.
        let pool = fillerPool.filter { $0.duration > 0 }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
        self.fillerPool = pool

        let slots = eligible.map { Self.slotLength(of: $0, padToMinutes: channel.padToMinutes) }
        self.longestSlot = slots.max() ?? 0
        let minimum = Int64(Self.minimumRunLength * 1000)
        let unit = Self.runRounding
        self.runLength = (max(minimum, slots.max() ?? minimum) + unit - 1) / unit * unit
        self.shortestProgramme = eligible.map { Self.milliseconds(of: $0.duration) }.min() ?? 1
        let setProgrammes = channel.fixed.map { $0.programmes(in: items) }
        self.setProgrammes = setProgrammes
        self.longestSetTime = setProgrammes.joined().map { Self.slotLength(of: $0, padToMinutes: channel.padToMinutes) }.max() ?? 0
        // As if each started on a boundary: only a guide to where each run's stream starts.
        let typicalSlots = eligible.map {
            Self.slotEnd(of: $0, startingAt: 0, padToMinutes: channel.padToMinutes)
        }
        self.averageSlotLength = strategy.averageSlotLength(of: content, slotLength: slotLength)
            ?? Double(typicalSlots.reduce(0, +)) / Double(typicalSlots.count)
        // Roughly how many commercials air in a run: the share of a slot that's
        // gap, over the run, divided by the average clip. Only used to guess
        // where each run's commercial stream starts.
        let averageLength = Double(eligible.reduce(0) { $0 + Self.milliseconds(of: $1.duration) }) / Double(eligible.count)
        let averageClip = pool.isEmpty ? 1 : Double(pool.reduce(0) { $0 + Self.milliseconds(of: $1.duration) }) / Double(pool.count)
        self.clipsPerRun = Double(runLength) * max(0, 1 - averageLength / averageSlotLength) / averageClip
    }

    /// How long each run of this channel's shared schedule is.
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
        return slots(from: start, to: end).map(Self.wholeProgramme(in:)).filter { $0.slotEnd > start && $0.start < end }
    }

    /// A slot's programme as one airing, however many parts it's in.
    static func wholeProgramme(in slot: [Airing]) -> Airing {
        let parts = slot.filter { !$0.isFiller }
        let first = parts.first ?? slot[0]
        return Airing(item: first.item, start: first.start, end: (parts.last ?? first).end,
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
        return slots(from: start, to: end).joined().filter { $0.slotEnd > start && $0.start < end }
    }

    // MARK: - Slots

    /// The slots from the start of the run containing `start` until one
    /// starts at or after `end`, with set times laid over the shared schedule.
    /// Each slot is a programme's airings: its parts, then its clips.
    private func slots(from start: Date, to end: Date) -> [[Airing]] {
        // With set times, from a slot earlier: a programme next to a set time
        // may become a break after the one before it, which must be there.
        let from = channel.fixed.isEmpty ? start : start.addingTimeInterval(-TimeInterval(longestSlot) / 1000)
        var walker = walker(from: from)
        var shared: [[Airing]] = []
        repeat { shared.append(walker.nextSlot()) } while shared[shared.count - 1][0].start < end
        // Every set time up to the last shared slot's end, even past `end`: one may cut a slot before `end`.
        return laidOver(shared, until: milliseconds(since: channel.epoch, to: shared[shared.count - 1].last!.slotEnd))
    }

    /// The programme and any filler after it, in the slot that contains `date`.
    private func slot(containing date: Date) -> [Airing] {
        let slots = slots(from: date, to: date.addingTimeInterval(0.001))
        return slots.last { $0[0].start <= date && date < $0[$0.count - 1].slotEnd } ?? slots[slots.count - 1]
    }

    // MARK: - Runs of the shared schedule

    /// A walker from the start of the run containing `date`. Runs start at
    /// their `Join`, which can be a little after their place in the calendar.
    private func walker(from date: Date) -> SlotWalker {
        let ms = milliseconds(since: channel.epoch, to: date)
        var run = Int(Self.floorDivide(ms, runLength))
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
        /// The last programme of the run before.
        let after: MediaItem
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
        var join = Join(after: last, start: slot.start)
        guard !programmeRules.allow(slot.item, after: last) else { return join }
        join.standIn = standIns(fitting: slot, after: last, before: walker.upcomingItem).first { _ in true }
        guard join.standIn == nil else { return join }
        let kept = join
        repeat {
            join.leftOut += 1
            join.start = slot.end
            slot = walker.place()
            if programmeRules.allow(slot.item, after: last) { return join }
        } while join.leftOut < Self.maxLeftOutAtJoin
        return kept   // nothing within reach may follow: the rules give way
    }

    /// A programme's slot in the shared schedule, in milliseconds since the
    /// epoch: from its start to where the next programme starts.
    struct Slot {
        let item: MediaItem
        let start: Int64
        var end: Int64
    }

    /// The channel's programmes that could take `slot`, when the one there
    /// can't stay: they fit, and the rules allow them straight after
    /// `previous` and straight before `next`. The search starts at a point
    /// picked from the channel's key and the slot, so stand-ins vary from
    /// slot to slot, yet every walk picks the same one.
    private func standIns(fitting slot: Slot, after previous: MediaItem?, before next: MediaItem?) -> some Sequence<MediaItem> {
        let items = content.items
        var rng = SeededRandom(seed: key, cycle: Int(Self.floorDivide(slot.start, 60_000)))
        let first = rng.int(below: items.count)
        return (0..<items.count).lazy.map { items[(first + $0) % items.count] }.filter { item in
            slot.start + Self.milliseconds(of: item.duration) <= slot.end
                && (previous.map { self.programmeRules.allow(item, after: $0) } ?? true)
                && (next.map { self.programmeRules.allow($0, after: item) } ?? true)
        }
    }

    /// `slot` with a stand-in if set times cover it (see
    /// `covers(_:windows:)`), or unchanged. Only this slot changes, so the rest
    /// of the shared schedule is the same as everyone else's.
    private func coveringIfNeeded(_ slot: Slot, after previous: MediaItem?, before next: MediaItem?,
                                  windows: [SetTimeWindow]) -> Slot {
        guard !channel.fixed.isEmpty, covers(slot, windows: windows) else { return slot }
        let standIn = standIns(fitting: slot, after: previous, before: next).first { item in
            !covers(Slot(item: item, start: slot.start, end: slot.end), windows: windows)
        }
        return standIn.map { Slot(item: $0, start: slot.start, end: slot.end) } ?? slot
    }

    /// The filler's stream of commercials for one run, starting at an estimate
    /// of how many aired before it, so the order carries on from the day before.
    private func commercials(forRun run: Int) -> AnyIterator<MediaItem> {
        commercials(startingAt: Int((Double(run) * clipsPerRun).rounded(.down)))
    }

    func commercials(startingAt position: Int) -> AnyIterator<MediaItem> {
        guard !fillerPool.isEmpty else { return AnyIterator { nil } }
        return filler.clips(from: fillerPool, for: content, startingAt: position)
    }

    /// The strategy's stream for one run. It starts at an estimate of how many
    /// programmes aired before the run, so sequences carry on from the day before.
    private func stream(forRun run: Int) -> AnyIterator<MediaItem> {
        let position = Int((Double(Int64(run) * runLength) / averageSlotLength).rounded(.down))
        return strategy.programmes(from: content, startingAt: position, rng: SeededRandom(seed: key, cycle: run))
    }

    /// How many too-long programmes the end of a run may pass over, looking
    /// for one that finishes in time.
    static let maxSkipsAtRunEnd = 15

    /// Lays out the shared schedule's slots, one run after another, starting
    /// at the beginning of a run. Programmes follow each other back to back;
    /// only the end of a run is a hard edge. Each run is laid out on its own;
    /// only its `Join` depends on the run before.
    private struct SlotWalker {
        let schedule: ChannelSchedule
        private var run: Int
        /// Milliseconds since the epoch where the next slot starts, and where
        /// this run ends as far as choosing programmes goes (the last slot
        /// reaches on to the next run's `Join`).
        private var cursor: Int64 = 0
        private var runEnd: Int64 = 0
        private var programmes: RuledStream
        /// This run's commercials, dealt break after break.
        private var commercials: CommercialQueue
        /// Chosen, but only placed once we know whether it's the run's last.
        private var upcoming: Slot?
        /// What the slot just placed aired, stand-in and all.
        private var placed: MediaItem?
        /// How this run meets the one before; nil lays runs out on their own.
        private var join: Join?
        /// Whether joins are worked out as runs end (false while working one out).
        private let joinsRuns: Bool
        /// Set times around this run, for the airings they cover.
        private var windows: [SetTimeWindow] = []
        /// Slots of this run still to leave out at its join.
        private var leftOut = 0
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
                placed = join?.after   // what's left out doesn't air
                slot = place()
            }
            return schedule.airingsInSlot(slot.item, slotStart: slot.start, slotEnd: slot.end, commercials: &commercials)
        }

        /// The programme after the slot just placed, if it's known yet.
        var upcomingItem: MediaItem? { upcoming?.item }

        /// Lays out the next slot.
        mutating func place() -> Slot {
            var slot = upcoming ?? firstSlotOfRun()
            let opening = opensRun
            opensRun = false
            let before = opening ? join?.after : placed
            programmes.aired(slot.item)
            upcoming = take()
            finishedRun = upcoming == nil
            if finishedRun {
                slot.end = runEnd
                opensRun = true
            }
            if opening, let standIn = join?.standIn { slot = Slot(item: standIn, start: slot.start, end: slot.end) }
            slot = schedule.coveringIfNeeded(slot, after: before, before: upcoming?.item, windows: windows)
            if finishedRun {
                // The run's last slot reaches on to where the next run starts,
                // which depends on what airs in it, stand-in and all.
                if joinsRuns { slot.end = nextJoin(after: slot.item).start }
                cursor = slot.end
            }
            placed = slot.item
            return slot
        }

        /// Works out, and keeps for when it starts, how the next run meets this one.
        private mutating func nextJoin(after last: MediaItem) -> Join {
            let next = schedule.join(ofRun: run + 1, after: last)
            join = next
            return next
        }

        /// Starts `run` afresh: nothing carries over from the run before.
        private mutating func begin(_ run: Int) {
            self.run = run
            cursor = Int64(run) * schedule.runLength
            runEnd = cursor + schedule.runLength
            leftOut = join?.leftOut ?? 0
            programmes = RuledStream(schedule.stream(forRun: run), for: .programmes)
            commercials = CommercialQueue(schedule.commercials(forRun: run))
            windows = schedule.setTimeWindows(from: cursor - schedule.longestSetTime, to: runEnd + schedule.longestSetTime)
        }

        /// The first slot of the next run. A run is at least as long as the
        /// longest slot, so its first programme always fits.
        private mutating func firstSlotOfRun() -> Slot {
            if cursor >= runEnd {
                cursor = runEnd
                begin(run + 1)
            }
            if let slot = take() { return slot }
            // Only a broken strategy gets here.
            assertionFailure("Strategy '\(type(of: schedule.strategy).id)' produced nothing for a run")
            let item = schedule.content.items[ChannelContent.wrap(run, schedule.content.items.count)]
            cursor = runEnd
            return Slot(item: item, start: runEnd - schedule.runLength, end: runEnd)
        }

        /// The next programme that finishes before the run ends, or nil when
        /// none does. Only near the end of a run does anything get passed over.
        private mutating func take() -> Slot? {
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
                    return Slot(item: item, start: cursor, end: end)
                }
                passedOver.append(item)
                if !mayReorder || passedOver.count > ChannelSchedule.maxSkipsAtRunEnd { return nil }
            }
            return nil
        }
    }

    /// A run's commercial stream, where a clip can be looked at before it's
    /// taken: one that doesn't fit this break waits to open the next.
    struct CommercialQueue {
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
    func airingsInSlot(_ item: MediaItem, slotStart: Int64, slotEnd: Int64,
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

    func date(atMilliseconds ms: Int64) -> Date {
        channel.epoch.addingTimeInterval(TimeInterval(ms) / 1000)
    }

    func milliseconds(since epoch: Date, to date: Date) -> Int64 {
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
