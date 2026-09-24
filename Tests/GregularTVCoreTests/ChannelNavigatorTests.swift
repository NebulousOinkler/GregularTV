import Testing
@testable import GregularTVCore

struct ChannelNavigatorTests {
    /// Like the default line-up with some channels hidden: note the gaps.
    let navigator = ChannelNavigator(numbers: [14, 1, 2, 5, 10])

    @Test func sortsAndDeduplicates() {
        #expect(ChannelNavigator(numbers: [3, 1, 3, 2]).numbers == [1, 2, 3])
    }

    @Test func upSkipsGapsAndWraps() {
        #expect(navigator.channel(after: 2) == 5)
        #expect(navigator.channel(after: 5) == 10)
        #expect(navigator.channel(after: 14) == 1)
    }

    @Test func downSkipsGapsAndWraps() {
        #expect(navigator.channel(before: 10) == 5)
        #expect(navigator.channel(before: 1) == 14)
    }

    @Test func worksFromANumberThatIsntAChannel() {
        #expect(navigator.channel(after: 3) == 5)
        #expect(navigator.channel(before: 3) == 2)
    }

    @Test func startingChannelFallsBackToLowest() {
        #expect(navigator.startingChannel(preferred: 10) == 10)
        #expect(navigator.startingChannel(preferred: 7) == 1)
        #expect(navigator.startingChannel(preferred: nil) == 1)
    }

    @Test func maxDigits() {
        #expect(navigator.maxDigits == 2)
        #expect(ChannelNavigator(numbers: [1, 9]).maxDigits == 1)
        #expect(ChannelNavigator(numbers: [1, 100]).maxDigits == 3)
    }

    @Test func emptyLineup() {
        let empty = ChannelNavigator(numbers: [])
        #expect(empty.channel(after: 1) == nil)
        #expect(empty.channel(before: 1) == nil)
        #expect(empty.startingChannel(preferred: 1) == nil)
    }
}
