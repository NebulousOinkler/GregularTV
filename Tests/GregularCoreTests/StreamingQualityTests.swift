import Foundation
import Testing
@testable import GregularCore

struct StreamingQualityTests {
    @Test func autoUsesSeventyPercentOfMeasuredBandwidth() {
        #expect(StreamingQuality.autoBitrate(measured: 20_000_000) == 14_000_000)
    }

    @Test func autoIsClampedToTheAvailableRange() {
        #expect(StreamingQuality.autoBitrate(measured: 100_000) == 1_500_000)
        #expect(StreamingQuality.autoBitrate(measured: 1_000_000_000) == StreamingQuality.maximumBitrate)
    }

    @Test func onlyAutoHasNoFixedCap() {
        #expect(StreamingQuality.allCases.filter { $0.fixedBitrate == nil } == [.auto])
    }

    @Test func fixedCapsDescendInMenuOrder() {
        let caps = StreamingQuality.allCases.compactMap(\.fixedBitrate)
        #expect(caps == caps.sorted(by: >))
    }

    @Test func steppingDownGoesOneOptionAtATime() {
        #expect(StreamingQuality.bitrate(below: StreamingQuality.maximumBitrate) == 20_000_000)
        #expect(StreamingQuality.bitrate(below: 20_000_000) == 10_000_000)
        #expect(StreamingQuality.bitrate(below: 8_000_000) == 4_000_000, "Auto's cap falls to the next option below it")
        #expect(StreamingQuality.bitrate(below: 4_000_000) == StreamingQuality.lowestBitrate)
        #expect(StreamingQuality.bitrate(below: StreamingQuality.lowestBitrate) == nil)
    }
}
