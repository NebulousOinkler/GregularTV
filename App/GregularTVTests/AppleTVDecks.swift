import GregularCore
@testable import GregularScreens
@testable import GregularTV

/// The app's tests play on real AVFoundation decks, as the app does.
extension ChannelPlayer {
    convenience init(schedule: ChannelSchedule, streams: any StreamSource, quality: StreamingQuality) {
        self.init(schedule: schedule, streams: streams, quality: quality, decks: AVPlayerDeck.pair())
    }
}

extension ChannelSurfer {
    convenience init(channels: [ChannelSchedule], startingWith channel: ChannelSchedule,
                     streams: any StreamSource, preferences: AppPreferences) {
        self.init(channels: channels, startingWith: channel, streams: streams, preferences: preferences,
                  decks: AVPlayerDeck.pair())
    }
}
