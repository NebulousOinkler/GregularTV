import Foundation

/// Set times, laid over the shared schedule (see `ChannelSchedule`).
///
/// Each set time is a *window*: from its local time to the end of its
/// programme's slot. Inside a window, its programme is on (with its own
/// breaks, like any slot). Outside every window, the shared schedule is on,
/// exactly as for anyone with the same code: a programme cut by a window's
/// start stops there, and one still on at a window's end is joined partway
/// through, as when changing channel.
///
/// The only other change is *covering*: an airing of the shared schedule is
/// swapped for a stand-in (see `CoverRule`) when a set time's `exclusive`
/// keeps its programme to the set times, or when it's the same programme as
/// a set time right next to it (the rules against airing it twice in a row).
extension ChannelSchedule {
    /// A set time's window, in milliseconds since the epoch.
    struct SetTimeWindow {
        let item: MediaItem
        let start: Int64
        let end: Int64
    }

    /// The set times whose windows overlap `start..<end`, in order. One is
    /// left out if it overlaps the one before it, or if it's the same
    /// programme straight after it (the sequence rules win).
    func setTimeWindows(from start: Int64, to end: Int64) -> [SetTimeWindow] {
        guard !channel.fixed.isEmpty else { return [] }
        // From a day further back, so a set time is left out the same way whichever range asks.
        let lookBack = date(atMilliseconds: start - longestSetTime - Int64(Self.minimumRunLength * 1000))
        let until = date(atMilliseconds: end)
        var pins: [Pin] = []
        for (entry, programmes) in zip(channel.fixed, setProgrammes) where !programmes.isEmpty {
            guard let zone = entry.timeZone else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let firstDay = calendar.startOfDay(for: channel.epoch)
            var day = calendar.startOfDay(for: lookBack)
            while day < until {
                let index = calendar.dateComponents([.day], from: firstDay, to: day).day ?? 0
                let scheduleDay = ScheduleDay(index: index, start: day, calendar: calendar, firstDay: firstDay)
                pins += pinRules.flatMap { $0.pins(for: entry, programmes: programmes, on: scheduleDay) }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        var windows: [SetTimeWindow] = []
        for pin in pins.sorted(by: { ($0.start, $0.item.id) < ($1.start, $1.item.id) }) {
            let from = milliseconds(since: channel.epoch, to: pin.start)
            let window = SetTimeWindow(item: pin.item, start: from,
                                       end: Self.slotEnd(of: pin.item, startingAt: from, padToMinutes: channel.padToMinutes))
            if let last = windows.last,
               window.start < last.end || window.start == last.end && !programmeRules.allow(window.item, after: last.item) {
                continue
            }
            windows.append(window)
        }
        return windows.filter { $0.end > start && $0.start < end }
    }

    /// The programmes at set times from `start` to `end`, each as its window:
    /// from its set time to the end of its slot.
    public func setTimeAirings(from start: Date, to end: Date) -> [Airing] {
        setTimeWindows(from: milliseconds(since: channel.epoch, to: start), to: milliseconds(since: channel.epoch, to: end))
            .map { window in
                Airing(item: window.item, start: date(atMilliseconds: window.start),
                       end: date(atMilliseconds: window.start + Self.milliseconds(of: window.item.duration)),
                       slotEnd: date(atMilliseconds: window.end), isFiller: false)
            }
    }

    /// Whether a household's set times cover this slot of the shared schedule:
    /// a `CoverRule` says so, or it's the last programme before a set time
    /// (or still on after one) that the rules don't allow next to it.
    func covers(_ slot: Slot, windows: [SetTimeWindow]) -> Bool {
        coverRules.contains { $0.covers(slot.item, on: channel) } || windows.contains { window in
            let lastBefore = slot.start < window.start && window.start <= slot.end
            let onAfter = slot.start <= window.end && window.end < slot.end
            return lastBefore && !programmeRules.allow(window.item, after: slot.item)
                || onAfter && !programmeRules.allow(slot.item, after: window.item)
        }
    }

    /// `shared` (slots of the shared schedule, up to `end`) with the set times
    /// laid over it. Slots cut by a window are clipped at its start and joined
    /// partway through at its end; the window's own slot goes between.
    func laidOver(_ shared: [[Airing]], until end: Int64) -> [[Airing]] {
        guard let first = shared.first?.first else { return shared }
        let windows = setTimeWindows(from: milliseconds(since: channel.epoch, to: first.start), to: end)
        guard !windows.isEmpty else { return shared }

        var pieces: [(airing: Airing, opensSlot: Bool)] = []
        /// Whether a part of the current shared slot's programme has been
        /// kept since it began or a window came: the next part only opens a
        /// slot of its own if none has.
        var programmeKept = false
        var nextWindow = 0
        func placeWindows(startingBy time: Int64) {
            while nextWindow < windows.count, windows[nextWindow].start <= time {
                pieces += airings(in: windows[nextWindow]).enumerated().map { ($1, $0 == 0) }
                nextWindow += 1
                programmeKept = false
            }
        }
        /// Airtime from `from` to `to` added to the break before it, if there's one.
        func extendBreak(from: Int64, to: Int64) -> Bool {
            guard let last = pieces.last, milliseconds(since: channel.epoch, to: last.airing.slotEnd) == from else { return false }
            pieces[pieces.count - 1].airing = last.airing.with(slotEnd: date(atMilliseconds: to))
            return true
        }
        /// The part of `airing` from `from` to `to`, outside every window.
        /// `blank` leaves it out: its time is a break after what's before.
        func keep(_ airing: Airing, from: Int64, to: Int64, blank: Bool) {
            placeWindows(startingBy: from)
            let start = milliseconds(since: channel.epoch, to: airing.start)
            let contentEnd = milliseconds(since: channel.epoch, to: airing.end)
            // Only the gap after it is left: the break before it grows instead.
            if blank || from >= contentEnd, extendBreak(from: from, to: to) { return }
            let cut = Airing(item: airing.item, start: date(atMilliseconds: from), end: date(atMilliseconds: max(from, min(contentEnd, to))),
                             slotEnd: date(atMilliseconds: to), isFiller: airing.isFiller,
                             mediaOffset: airing.mediaOffset + TimeInterval(from - start) / 1000,
                             programmeStart: airing.programmeStart)
            // The programme's first part kept, from its start or joined partway
            // through after a window, starts a slot; clips join the slot before.
            let opensSlot = !airing.isFiller && !programmeKept
            if !airing.isFiller { programmeKept = true }
            pieces.append((cut, opensSlot))
        }

        for slot in shared {
            let slotStart = milliseconds(since: channel.epoch, to: slot[0].start)
            let slotEnd = milliseconds(since: channel.epoch, to: slot[slot.count - 1].slotEnd)
            let item = (slot.first { !$0.isFiller } ?? slot[0]).item
            // Where covering found no stand-in, the programme can't air next to a set time
            // (the rules): the part before the set time, or after it, is a break instead.
            let blankUntil = windows.first { slotStart < $0.start && $0.start <= slotEnd && !programmeRules.allow($0.item, after: item) }?.start
            let blankFrom = windows.first { slotStart <= $0.end && $0.end < slotEnd && !programmeRules.allow(item, after: $0.item) }?.end
            programmeKept = false
            for airing in slot {
                let start = milliseconds(since: channel.epoch, to: airing.start)
                let end = milliseconds(since: channel.epoch, to: airing.slotEnd)
                var time = start
                func keepPart(to: Int64) {
                    keep(airing, from: time, to: to,
                         blank: blankUntil.map { time < $0 } ?? false || blankFrom.map { time >= $0 } ?? false)
                }
                for window in windows where window.end > start && window.start < end {
                    if window.start > time { keepPart(to: window.start) }
                    time = max(time, window.end)
                }
                if time < end { keepPart(to: end) }
            }
        }
        placeWindows(startingBy: end)

        var slots: [[Airing]] = []
        for piece in pieces {
            if piece.opensSlot || slots.isEmpty { slots.append([piece.airing]) } else { slots[slots.count - 1].append(piece.airing) }
        }
        return keepingTheRules(slots, windows: windows)
    }

    /// Where no stand-in could be found, a programme of the shared schedule
    /// the rules don't allow next to a set time becomes a break instead: the
    /// programme before it runs on into its time, blank.
    private func keepingTheRules(_ slots: [[Airing]], windows: [SetTimeWindow]) -> [[Airing]] {
        let starts = Set(windows.map { date(atMilliseconds: $0.start) })
        func isSetTime(_ slot: [Airing]) -> Bool { starts.contains(Self.wholeProgramme(in: slot).start) }
        /// Blanks the last slot kept, adding its time to the break before it.
        func blankLast(of result: inout [[Airing]]) {
            let end = result.removeLast().last!.slotEnd
            result[result.count - 1][result[result.count - 1].count - 1] = result[result.count - 1].last!.with(slotEnd: end)
        }
        var result: [[Airing]] = []
        for slot in slots {
            if let previous = result.last,
               !programmeRules.allow(Self.wholeProgramme(in: slot).item, after: Self.wholeProgramme(in: previous).item) {
                // Two set times next to each other are the user's choice.
                switch (isSetTime(previous), isSetTime(slot)) {
                case (true, false):
                    result.append(slot)
                    blankLast(of: &result)
                    continue
                case (false, true) where result.count > 1:
                    blankLast(of: &result)
                default:
                    break
                }
            }
            result.append(slot)
        }
        return result
    }

    /// A window's airings: its programme, then its breaks, like any slot, with
    /// commercials from about where the shared schedule's are by then.
    private func airings(in window: SetTimeWindow) -> [Airing] {
        var commercials = CommercialQueue(commercials(startingAt: Int(Double(window.start) / Double(runLength) * clipsPerRun)))
        return airingsInSlot(window.item, slotStart: window.start, slotEnd: window.end, commercials: &commercials)
    }
}

extension Airing {
    /// The same airing, with its slot ending at `slotEnd`.
    func with(slotEnd: Date) -> Airing {
        Airing(item: item, start: start, end: end, slotEnd: slotEnd, isFiller: isFiller,
               mediaOffset: mediaOffset, programmeStart: programmeStart)
    }
}
