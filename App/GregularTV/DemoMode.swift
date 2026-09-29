import GregularKeychain
import GregularScreens

extension AppModel {
    /// How this app appears in Jellyfin's device list: the kind of device,
    /// not the name the user gave their Apple TV (which often contains a
    /// person's name).
    static let deviceName = "Apple TV"

    /// The model the app starts with, playing on AVFoundation decks. Release
    /// builds always use the saved sign-in (or show sign-in); Debug builds
    /// can instead start in demo mode (see `DemoCredentials`).
    static func forLaunch() -> AppModel {
        #if DEBUG
        if let demo = DemoCredentials.fromLaunchArguments() {
            return AppModel(deviceName: deviceName, store: demo, makeDecks: AVPlayerDeck.pair)
        }
        #endif
        return AppModel(deviceName: deviceName, store: KeychainStore(), makeDecks: AVPlayerDeck.pair)
    }
}
