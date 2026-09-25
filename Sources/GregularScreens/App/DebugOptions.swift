#if DEBUG
import Foundation
import GregularCore

/// Launch arguments for testing. Compiled into Debug builds only.
///
/// `-handoffTest`: shifts every channel's schedule so the programme on now
/// ends about 50 seconds after launch, to test the hand-off to the next
/// programme without waiting. It works by moving the channel's epoch; the
/// schedule is pure maths from the epoch, so nothing else changes.
///
///     xcrun simctl launch booted dev.gregulartv.GregularTV -handoffTest
///
/// `-openChannelList`: opens the channel list on launch, to check its focus
/// handling without arrow keys. `-openGuide` does the same for the guide.
///
/// `-pretendCommercials`: borrows a dozen real videos from the library as
/// 30–120 second "commercials", so breaks can be tested before a real
/// commercials library exists. Each plays from its start and is cut at its
/// pretend length.
enum DebugOptions {
    static let handoffLeadTime: TimeInterval = 50

    static var opensChannelList: Bool {
        ProcessInfo.processInfo.arguments.contains("-openChannelList")
    }

    /// `-openGuide`: opens the guide on launch, to check it without a Menu button.
    static var opensGuide: Bool {
        ProcessInfo.processInfo.arguments.contains("-openGuide")
    }

    static func apply(to channels: [ChannelSchedule], items: [MediaItem], fillerPool: [MediaItem]) -> [ChannelSchedule] {
        guard ProcessInfo.processInfo.arguments.contains("-handoffTest") else { return channels }
        return channels.map { endingSoon($0, items: items, fillerPool: fillerPool) }
    }

    static var usesPretendCommercials: Bool {
        ProcessInfo.processInfo.arguments.contains("-pretendCommercials")
    }

    static func pretendCommercials(from library: [MediaItem]) -> [MediaItem] {
        let lengths: [TimeInterval] = [30, 45, 60, 90, 120]
        let step = max(1, library.count / 12)
        return stride(from: 0, to: library.count, by: step).prefix(12).enumerated().map { n, index in
            let real = library[index]
            return MediaItem(id: real.id, kind: .video, name: "Pretend ad \(n + 1)", duration: lengths[n % lengths.count])
        }
    }

    private static func endingSoon(_ schedule: ChannelSchedule, items: [MediaItem], fillerPool: [MediaItem]) -> ChannelSchedule {
        let remaining = schedule.tune(at: .now).airing.end.timeIntervalSinceNow
        let c = schedule.channel
        let shifted = Channel(number: c.number, name: c.name, itemTypes: c.itemTypes, source: c.source,
                              strategyID: c.strategyID, seed: c.seed, padToMinutes: c.padToMinutes,
                              fillerID: c.fillerID, epoch: c.epoch.addingTimeInterval(-(remaining - handoffLeadTime)))
        let clipIDs = Set(fillerPool.map(\.id))
        return ChannelSchedule(channel: shifted, items: items.filter { !clipIDs.contains($0.id) },
                               fillerPool: fillerPool, code: schedule.code) ?? schedule
    }
}
#endif
