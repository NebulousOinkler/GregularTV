import Foundation
import GregularBrowser
import JavaScriptKit
import Testing

/// Times are shown in the viewer's time zone, not GMT.
@Suite(.serialized) struct BrowserTimeZoneTests {
    /// Minutes the browser says `date` is behind GMT where it is
    /// (`Date.getTimezoneOffset`): 420 in California in summer.
    private func browserOffset(at date: Date) -> Int {
        let jsDate = JSObject.global.Date.function!.new(date.timeIntervalSince1970 * 1000)
        return Int(jsDate.getTimezoneOffset!().number!)
    }

    @Test func foundationTakesTheBrowsersTimeZone() throws {
        let zone = try #require(BrowserTimeZone.browser)
        BrowserTimeZone.adopt()
        // The same zone, though not always by name: Foundation calls "UTC" "GMT".
        #expect(TimeZone.current == TimeZone(identifier: zone))
        // Summer and winter, so daylight saving time is followed too.
        for date in [Date(timeIntervalSince1970: 1_783_000_000), Date(timeIntervalSince1970: 1_798_000_000)] {
            #expect(-TimeZone.current.secondsFromGMT(for: date) / 60 == browserOffset(at: date))
        }
    }

    @Test(arguments: [("America/Los_Angeles", 12, "12:15"), ("Asia/Kolkata", 0, "12:45")])
    func aClockTimeIsReadInThatZone(zone: String, hour: Int, shown: String) {
        defer { BrowserTimeZone.adopt() }
        BrowserTimeZone.adopt(zone)
        // 19:15 GMT on 2 October 2026: 12:15 in California, 00:45 in India.
        let date = Date(timeIntervalSince1970: 1_790_968_500)
        #expect(Calendar.current.component(.hour, from: date) == hour)
        #expect(date.formatted(date: .omitted, time: .shortened).hasPrefix(shown))
    }

    @Test func anUnknownZoneChangesNothing() {
        let before = TimeZone.current
        BrowserTimeZone.adopt("Nowhere/Atlantis")
        #expect(TimeZone.current == before)
    }
}
