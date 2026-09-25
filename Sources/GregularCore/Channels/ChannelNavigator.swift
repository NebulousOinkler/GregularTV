/// Moves between channel numbers the way a TV does.
///
/// Channel numbers can have gaps: `channels.json` fixes the numbers, and
/// channels with no content are hidden. Up and down skip gaps and wrap
/// around at either end.
public struct ChannelNavigator: Sendable, Equatable {
    /// Available channel numbers, ascending.
    public let numbers: [Int]

    public init(numbers: [Int]) {
        self.numbers = Array(Set(numbers)).sorted()
    }

    /// The most digits a channel number has. Number entry tunes as soon as
    /// this many digits are typed.
    public var maxDigits: Int {
        String(numbers.last ?? 0).count
    }

    public func contains(_ number: Int) -> Bool {
        numbers.contains(number)
    }

    /// Channel up: the next higher channel, wrapping to the lowest.
    /// Works from a number that isn't itself a channel.
    public func channel(after number: Int) -> Int? {
        numbers.first { $0 > number } ?? numbers.first
    }

    /// Channel down: the next lower channel, wrapping to the highest.
    public func channel(before number: Int) -> Int? {
        numbers.last { $0 < number } ?? numbers.last
    }

    /// The channel to open on launch: the preferred one (last watched) if
    /// it still exists, otherwise the lowest-numbered.
    public func startingChannel(preferred: Int?) -> Int? {
        if let preferred, contains(preferred) { return preferred }
        return numbers.first
    }
}
