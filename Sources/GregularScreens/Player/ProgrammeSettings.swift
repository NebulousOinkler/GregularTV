import Foundation
import GregularCore

/// Everything that applies to one programme only: the viewer's fixes and
/// choice of player, and what was learned from the programme's trouble.
///
/// One value, so it goes together. `ChannelPlayer` holds one, for the
/// programme on now (every part of a split film shares it), and lets it go
/// when the next programme starts or the channel changes, so those start
/// with none of it. A quality change clears only what's about quality
/// (`clearQuality()`): the choice of player, and stereo sound, stay.
///
/// It decides, without a deck or a server: the cap a programme plays at,
/// the step-down ladder, asking for less re-encoding or less sound
/// conversion, and what a speed test makes Auto's cap.
struct ProgrammeSettings {
    let programme: Airing
    /// The fix in use (the viewer's, or one asked for after re-encoding
    /// trouble), and the cap it plays at.
    private(set) var fix: (kind: ChannelPlayer.ProgrammeFix, cap: Int)?
    /// Auto's cap after trouble on the connection, and when it was measured.
    private(set) var autoCap: (bitsPerSecond: Int, measuredAt: Date)?
    /// It had trouble on the connection in Auto: measure before tuning in again.
    var measuresFirst = false
    /// The viewer asked for the add-on player (VLC on Apple TV).
    var prefersAddOn = false
    /// Sound the server converts is mixed down to stereo: the viewer asked,
    /// or the server couldn't convert it fast enough.
    var stereoSound = false
    /// A stream whose sound the server converts gets a head start, as a
    /// re-encode does: it couldn't keep up without one.
    var soundHeadStart = false
    /// Nothing this device plays can show it (`UnplayableFormats`): it isn't
    /// asked for again.
    var cantPlay = false

    /// While capped, Auto measures again in the background after this long,
    /// which may raise the cap.
    static let remeasureInterval: TimeInterval = 600

    init(programme: Airing) {
        self.programme = programme
    }

    /// They're for `airing`'s programme (any part of it).
    func apply(to airing: Airing) -> Bool {
        programme.isSameProgramme(as: airing)
    }

    /// The cap it plays at: the fix's, else the quality setting's, else, in
    /// Auto, the cap measured after trouble, else none (the maximum).
    func cap(at quality: StreamingQuality) -> Int {
        if let fix { return fix.cap }
        if let fixed = quality.fixedBitrate { return fixed }
        return autoCap?.bitsPerSecond ?? StreamingQuality.maximumBitrate
    }

    // MARK: - Fixes

    /// The viewer's fix, from `cap` (what it's playing at now). *Step Down*
    /// goes one step below it; *Standard* takes the fix away.
    mutating func setFix(_ kind: ChannelPlayer.ProgrammeFix, from cap: Int) {
        switch kind {
        case .standard: fix = nil
        case .stepDown: fix = (.stepDown, StreamingQuality.bitrate(below: cap) ?? StreamingQuality.lowestBitrate)
        case .hd720: fix = (.hd720, StreamingQuality.hd720.fixedBitrate!)
        }
    }

    /// *Step Down*, buffering again: one step lower. False if it isn't
    /// stepping down, or it's already at the lowest.
    mutating func stepDownAgain() -> Bool {
        guard let fix, fix.kind == .stepDown, let lower = StreamingQuality.bitrate(below: fix.cap) else { return false }
        self.fix = (.stepDown, lower)
        return true
    }

    /// A re-encode the server couldn't keep up with, at `cap`: 720p first,
    /// then a step lower each time, down to the lowest. False at the lowest:
    /// there's nothing less to ask for.
    mutating func askForLessReencoding(from cap: Int) -> Bool {
        let hd720 = StreamingQuality.hd720.fixedBitrate!
        guard let lower = cap > hd720 ? hd720 : StreamingQuality.bitrate(below: cap) else { return false }
        fix = (lower == hd720 ? .hd720 : .stepDown, lower)
        return true
    }

    /// The server couldn't convert the sound fast enough, the video copied
    /// as it is: first stereo, which is less to make (where there's surround
    /// to mix down); then a head start, so the server gets ahead. Never a
    /// lower bitrate, which would make it re-encode the video too. Not the
    /// add-on player either: it was asked before the server converted
    /// anything, and can't play this file as it is. False once both are
    /// asked for: then the trouble may be the connection's.
    mutating func askForLessSoundWork(offersStereo: Bool) -> Bool {
        if offersStereo, !stereoSound {
            stereoSound = true
        } else if !soundHeadStart {
            soundHeadStart = true
        } else {
            return false
        }
        return true
    }

    // MARK: - Auto

    /// Auto's cap from a speed test that measured `bitsPerSecond`: 70% of it.
    /// With `raiseOnly` (a test run while video downloads, which understates
    /// the connection) it can only go up. A cap at the maximum is no cap.
    mutating func measured(_ bitsPerSecond: Int, raiseOnly: Bool, at date: Date) {
        let cap = StreamingQuality.autoBitrate(measured: bitsPerSecond)
        let newCap = raiseOnly ? autoCap.map { max($0.bitsPerSecond, cap) } : cap
        autoCap = newCap.flatMap { $0 < StreamingQuality.maximumBitrate ? ($0, date) : nil }
    }

    /// Auto's cap is old enough to measure again in the background.
    func needsRemeasuring(at date: Date) -> Bool {
        autoCap.map { date.timeIntervalSince($0.measuredAt) >= Self.remeasureInterval } ?? false
    }

    /// The quality setting changed: the fix and Auto's measurement go; the
    /// choice of player and stereo sound stay.
    mutating func clearQuality() {
        fix = nil
        autoCap = nil
        measuresFirst = false
    }
}
