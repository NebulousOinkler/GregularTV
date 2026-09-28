/// Custom channels (made on the Apple TV) use their own range of numbers, so
/// they never clash with the bundled channels or with each other.
struct CustomChannelNumbers: LineupRule {
    static let id = "custom-channel-numbers"
    static let summary = "Custom channels are numbered 20 to 99, and no two channels share a number."

    func problems(withCustom custom: [Channel], bundled: [Channel]) -> [String] {
        let taken = Set(bundled.map(\.number))
        var seen = Set<Int>()
        return custom.compactMap { channel in
            if !CustomChannel.numbers.contains(channel.number) {
                return "Custom channels are numbered \(CustomChannel.numbers.lowerBound) to \(CustomChannel.numbers.upperBound)."
            }
            if taken.contains(channel.number) || !seen.insert(channel.number).inserted {
                return "Channel \(channel.number) is already taken."
            }
            return nil
        }
    }
}
