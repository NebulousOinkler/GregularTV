import Foundation
import GregularCore
import Testing
@testable import GregularScreens

/// One programme's settings, on their own: no deck, no server.
struct ProgrammeSettingsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// A film's first part, an hour long.
    private var film: Airing {
        Airing(item: MediaItem(id: "m", kind: .movie, name: "Film", duration: 7200),
               start: start, end: start.addingTimeInterval(3600), slotEnd: start.addingTimeInterval(3600), isFiller: false)
    }

    @Test func theyApplyToEveryPartOfTheProgrammeOnly() {
        let settings = ProgrammeSettings(programme: film)
        let secondPart = Airing(item: film.item, start: start.addingTimeInterval(3900), end: start.addingTimeInterval(7500),
                                slotEnd: start.addingTimeInterval(7500), isFiller: false, mediaOffset: 3600, programmeStart: start)
        let nextShowing = Airing(item: film.item, start: start.addingTimeInterval(9000), end: start.addingTimeInterval(16200),
                                 slotEnd: start.addingTimeInterval(16200), isFiller: false)
        #expect(settings.apply(to: film) && settings.apply(to: secondPart))
        #expect(!settings.apply(to: nextShowing), "Another showing is another programme")
    }

    /// The fix's cap, else the quality's, else Auto's after trouble, else none.
    @Test func theCapComesFromTheFixThenTheQualityThenAuto() {
        var settings = ProgrammeSettings(programme: film)
        #expect(settings.cap(at: .auto) == StreamingQuality.maximumBitrate)
        #expect(settings.cap(at: .hd10) == 10_000_000)
        settings.measured(10_000_000, raiseOnly: false, at: start)
        #expect(settings.cap(at: .auto) == 7_000_000, "70% of the measurement")
        settings.setFix(.hd720, from: 7_000_000)
        #expect(settings.cap(at: .auto) == 4_000_000 && settings.cap(at: .hd20) == 4_000_000)
    }

    @Test func stepDownGoesOneStepAtATimeToTheLowest() {
        var settings = ProgrammeSettings(programme: film)
        settings.setFix(.stepDown, from: StreamingQuality.maximumBitrate)
        #expect(settings.fix?.cap == 20_000_000)
        var caps = [settings.fix!.cap]
        while settings.stepDownAgain() { caps.append(settings.fix!.cap) }
        #expect(caps == [20_000_000, 10_000_000, 4_000_000, 1_500_000])
        settings.setFix(.standard, from: 1_500_000)
        #expect(settings.fix == nil && !settings.stepDownAgain(), "Only Step Down steps down again")
    }

    /// Re-encoding trouble: 720p first, then a step lower each time; nothing below the lowest.
    @Test func reencodingTroubleAsksForLessEachTime() {
        var settings = ProgrammeSettings(programme: film)
        let first = settings.askForLessReencoding(from: 20_000_000)
        #expect(first && settings.fix?.kind == .hd720 && settings.fix?.cap == 4_000_000)
        let second = settings.askForLessReencoding(from: 4_000_000)
        #expect(second && settings.fix?.kind == .stepDown && settings.fix?.cap == 1_500_000)
        let third = settings.askForLessReencoding(from: 1_500_000)
        #expect(!third && settings.fix?.cap == 1_500_000, "Nothing less to ask for")
    }

    /// A test run while video plays only raises Auto's cap; one at the maximum is no cap.
    @Test func backgroundTestsOnlyRaiseTheCap() {
        var settings = ProgrammeSettings(programme: film)
        settings.measured(10_000_000, raiseOnly: false, at: start)
        settings.measured(5_000_000, raiseOnly: true, at: start)
        #expect(settings.autoCap?.bitsPerSecond == 7_000_000)
        settings.measured(20_000_000, raiseOnly: true, at: start)
        #expect(settings.autoCap?.bitsPerSecond == 14_000_000)
        settings.measured(1_000_000_000, raiseOnly: true, at: start)
        #expect(settings.autoCap == nil)
    }

    @Test func aCapIsMeasuredAgainAfterTenMinutes() {
        var settings = ProgrammeSettings(programme: film)
        #expect(!settings.needsRemeasuring(at: start), "No cap, nothing to raise")
        settings.measured(10_000_000, raiseOnly: false, at: start)
        #expect(!settings.needsRemeasuring(at: start.addingTimeInterval(599)))
        #expect(settings.needsRemeasuring(at: start.addingTimeInterval(600)))
    }

    /// A quality change clears what's about quality; the choice of player stays.
    @Test func aQualityChangeKeepsTheChoiceOfPlayer() {
        var settings = ProgrammeSettings(programme: film)
        settings.prefersAddOn = true
        settings.measuresFirst = true
        settings.measured(10_000_000, raiseOnly: false, at: start)
        settings.setFix(.hd720, from: 7_000_000)
        settings.clearQuality()
        #expect(settings.fix == nil && settings.autoCap == nil && !settings.measuresFirst)
        #expect(settings.prefersAddOn)
    }

    /// Sound conversion trouble: stereo, then a head start, never a lower bitrate; then nothing left.
    @Test func soundTroubleAsksForStereoThenAHeadStart() {
        var settings = ProgrammeSettings(programme: film)
        let first = settings.askForLessSoundWork(offersStereo: true)
        #expect(first && settings.stereoSound && !settings.soundHeadStart && !settings.prefersAddOn)
        let second = settings.askForLessSoundWork(offersStereo: true)
        #expect(second && settings.soundHeadStart)
        let third = settings.askForLessSoundWork(offersStereo: true)
        #expect(!third)
        #expect(settings.cap(at: .auto) == StreamingQuality.maximumBitrate, "Never a lower bitrate")
    }

    /// With no surround to mix down (a browser), the head start comes first.
    @Test func withoutSurroundTheHeadStartComesFirst() {
        var settings = ProgrammeSettings(programme: film)
        let first = settings.askForLessSoundWork(offersStereo: false)
        #expect(first && settings.soundHeadStart && !settings.stereoSound)
        let second = settings.askForLessSoundWork(offersStereo: false)
        #expect(!second)
    }

    @Test func aQualityChangeKeepsStereoSound() {
        var settings = ProgrammeSettings(programme: film)
        settings.stereoSound = true
        settings.clearQuality()
        #expect(settings.stereoSound)
    }

    /// A break's settings start as its programme's cap and sound, not its
    /// player or what's learned about its file, and apply to its clips only.
    @Test func aBreakStartsWithItsProgrammesCapAndSound() {
        var settings = ProgrammeSettings(programme: film)
        settings.setFix(.hd720, from: StreamingQuality.maximumBitrate)
        settings.measured(10_000_000, raiseOnly: false, at: start)
        settings.stereoSound = true
        settings.prefersAddOn = true
        settings.cantPlay = true
        settings.measuresFirst = true
        settings.soundHeadStart = true
        let time = DateInterval(start: film.end, duration: 600)
        let forBreak = settings.forBreak(time)
        #expect(forBreak.cap(at: .auto) == 4_000_000 && forBreak.autoCap?.bitsPerSecond == 7_000_000 && forBreak.stereoSound)
        #expect(!forBreak.prefersAddOn && !forBreak.cantPlay && !forBreak.measuresFirst && !forBreak.soundHeadStart)

        let clip = { (start: Date) in
            Airing(item: MediaItem(id: "ad", kind: .video, name: "Ad", duration: 60),
                   start: start, end: start.addingTimeInterval(60), slotEnd: start.addingTimeInterval(60), isFiller: true)
        }
        #expect(forBreak.apply(to: clip(film.end)) && forBreak.apply(to: clip(film.end.addingTimeInterval(300))))
        #expect(!forBreak.apply(to: clip(film.end.addingTimeInterval(900))), "Another break")
        #expect(!forBreak.apply(to: film) && !settings.apply(to: clip(film.end)), "Breaks and programmes keep their own")
    }
}
