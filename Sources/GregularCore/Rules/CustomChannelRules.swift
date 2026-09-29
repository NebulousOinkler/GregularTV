/// Custom channels (made on the Apple TV) use their own range of numbers, so
/// they never clash with the bundled channels or with each other.
struct CustomChannelNumbers: LineupRule {
    static let id = "custom-channel-numbers"
    static let summary = "Custom channels are numbered 20 to 99, and no two channels share a number."

    func problems(with additions: LineupAdditions) -> [String] {
        let taken = Set(additions.bundled.map(\.number))
        var seen = Set<Int>()
        return additions.custom.compactMap { channel in
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

/// A household's set times belong to a channel in the line-up, bundled or
/// custom, and each channel has at most one set of them.
struct SetTimesNeedTheirChannel: LineupRule {
    static let id = "set-times-need-their-channel"
    static let summary = "Set times belong to a channel in the line-up, one set per channel."

    func problems(with additions: LineupAdditions) -> [String] {
        let numbers = Set((additions.bundled + additions.custom).map(\.number))
        var seen = Set<Int>()
        return additions.setTimes.compactMap { setTimes in
            if !numbers.contains(setTimes.channelNumber) { return "There's no channel \(setTimes.channelNumber) for these set times." }
            if !seen.insert(setTimes.channelNumber).inserted { return "Channel \(setTimes.channelNumber) already has set times." }
            return nil
        }
    }
}
