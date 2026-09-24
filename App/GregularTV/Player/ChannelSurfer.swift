import Foundation
import GregularTVCore
import Observation

/// Turns remote input into channel changes: up/down, picking from the list,
/// and typing a number.
///
/// Rapid up/down presses only move a *preview* (the banner shows the target
/// channel and what's on). The player tunes once presses stop for
/// `settleDelay`, so flicking past five channels doesn't start five streams
/// on the server.
@MainActor @Observable
final class ChannelSurfer {
    static let settleDelay: Duration = .milliseconds(700)
    static let digitTimeout: Duration = .milliseconds(1500)

    let player: ChannelPlayer
    let channels: [ChannelSchedule]
    let navigator: ChannelNavigator

    /// The channel being previewed while the user is still surfing.
    private(set) var preview: ChannelSchedule?
    /// Digits typed so far, for example "1" while waiting for a second digit.
    private(set) var typedDigits = ""
    /// A short message such as "No channel 9", cleared after a moment.
    private(set) var notice: String?

    private let preferences: AppPreferences
    private var settleTask: Task<Void, Never>?
    private var digitTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(channels: [ChannelSchedule], startingWith channel: ChannelSchedule,
         client: JellyfinClient, preferences: AppPreferences) {
        self.channels = channels
        self.preferences = preferences
        navigator = ChannelNavigator(numbers: channels.map(\.channel.number))
        player = ChannelPlayer(schedule: channel, client: client, quality: preferences.streamingQuality)
    }

    /// The channel the banner should show: the preview while surfing,
    /// otherwise what's playing.
    var displayedChannel: ChannelSchedule { preview ?? player.schedule }

    // MARK: - Input

    func channelUp() {
        surf(to: navigator.channel(after: displayedChannel.channel.number))
    }

    func channelDown() {
        surf(to: navigator.channel(before: displayedChannel.channel.number))
    }

    /// Picking a channel from the list tunes straight away.
    func tune(to number: Int) {
        guard let schedule = schedule(number) else {
            show(notice: "No channel \(number)")
            return
        }
        settleTask?.cancel()
        preview = nil
        guard schedule.channel.number != player.schedule.channel.number else { return }
        player.switchTo(schedule)
        preferences.lastChannelNumber = number
    }

    /// A digit from a keyboard. Tunes when enough digits are typed for the
    /// highest channel number, or after a short pause.
    func type(digit: Character) {
        guard digit.isWholeNumber else { return }
        typedDigits.append(digit)
        digitTask?.cancel()
        if typedDigits.count >= navigator.maxDigits {
            commitDigits()
        } else {
            digitTask = Task {
                try? await Task.sleep(for: Self.digitTimeout)
                guard !Task.isCancelled else { return }
                commitDigits()
            }
        }
    }

    // MARK: - Private

    private func surf(to number: Int?) {
        guard let number, let schedule = schedule(number) else { return }
        preview = schedule
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            tune(to: number)
        }
    }

    private func commitDigits() {
        let number = Int(typedDigits)
        typedDigits = ""
        if let number { tune(to: number) }
    }

    private func schedule(_ number: Int) -> ChannelSchedule? {
        channels.first { $0.channel.number == number }
    }

    private func show(notice: String) {
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.notice = nil
        }
    }
}
