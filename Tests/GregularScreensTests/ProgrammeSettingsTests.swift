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

    /// Re-encoding trouble: 720p first, then a step lower each time.
    @Test func reencodingTroubleAsksForLessEachTime() {
        var settings = ProgrammeSettings(programme: film)
        settings.askForLessReencoding(from: 20_000_000)
        #expect(settings.fix?.kind == .hd720 && settings.fix?.cap == 4_000_000)
        settings.askForLessReencoding(from: 4_000_000)
        #expect(settings.fix?.kind == .stepDown && settings.fix?.cap == 1_500_000)
        settings.askForLessReencoding(from: 1_500_000)
        #expect(settings.fix?.cap == 1_500_000, "No lower than the lowest")
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
}
