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
/// `-breakEndTest`: shifts every channel's schedule so launch lands 8
/// seconds before the end of the last commercial in a break between two
/// programmes (not a film's mid-roll), with the Up next card after it, to test the end of a break without waiting.
/// `-breakEndTest late` also starts that commercial from its beginning
/// instead of joining it live, so it runs late, as after a slow load.
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
    static let breakEndLeadTime: TimeInterval = 8

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// `-breakEndTest late`: commercials joined mid-way start from their beginning.
    static var startsCommercialsLate: Bool {
        guard let flag = arguments.firstIndex(of: "-breakEndTest"), flag + 1 < arguments.count else { return false }
        return arguments[flag + 1] == "late"
    }

    static var opensChannelList: Bool {
        ProcessInfo.processInfo.arguments.contains("-openChannelList")
    }

    /// `-openGuide`: opens the guide on launch, to check it without a Menu button.
    static var opensGuide: Bool {
        ProcessInfo.processInfo.arguments.contains("-openGuide")
    }

    static func apply(to channels: [ChannelSchedule], items: [MediaItem], fillerPool: [MediaItem]) -> [ChannelSchedule] {
        if arguments.contains("-breakEndTest") {
            return channels.map { shifted($0, by: breakEndShift(in: $0), items: items, fillerPool: fillerPool) }
        }
        guard arguments.contains("-handoffTest") else { return channels }
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
        return shifted(schedule, by: remaining - handoffLeadTime, items: items, fillerPool: fillerPool)
    }

    /// How far to move the epoch back so the last commercial of a break
    /// before a new programme (with time left for the Up next card) ends
    /// `breakEndLeadTime` after now.
    private static func breakEndShift(in schedule: ChannelSchedule) -> TimeInterval {
        let lastClip = schedule.airings(from: .now, to: .now.addingTimeInterval(12 * 3600)).first {
            $0.isFiller && $0.end.timeIntervalSinceNow > breakEndLeadTime && $0.slotEnd.timeIntervalSince($0.end) > 1
                && schedule.airings(from: $0.slotEnd, to: $0.slotEnd.addingTimeInterval(1)).first?.mediaOffset == 0
        }
        return (lastClip?.end.timeIntervalSinceNow ?? breakEndLeadTime) - breakEndLeadTime
    }

    private static func shifted(_ schedule: ChannelSchedule, by seconds: TimeInterval,
                                items: [MediaItem], fillerPool: [MediaItem]) -> ChannelSchedule {
        let c = schedule.channel
        let shifted = Channel(number: c.number, name: c.name, itemTypes: c.itemTypes, source: c.source,
                              strategyID: c.strategyID, seed: c.seed, padToMinutes: c.padToMinutes,
                              fillerID: c.fillerID, epoch: c.epoch.addingTimeInterval(-seconds))
        let clipIDs = Set(fillerPool.map(\.id))
        return ChannelSchedule(channel: shifted, items: items.filter { !clipIDs.contains($0.id) },
                               fillerPool: fillerPool, code: schedule.code) ?? schedule
    }
}
#endif
