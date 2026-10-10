import GregularCore
import GregularKeychain
import GregularScreens

extension AppModel {
    /// How this app appears in the server's device list: the kind of device,
    /// not the name the user gave their Apple TV (which often contains a
    /// person's name).
    static let deviceName = "Apple TV"

    /// The model the app starts with, playing on Apple TV's decks
    /// (VLC and AVFoundation, as `ChannelPlayer` chooses). Release
    /// builds always use the saved sign-in (or show sign-in); Debug builds
    /// can instead start in demo mode (see `DemoCredentials`).
    static func forLaunch() -> AppModel {
        #if DEBUG
        if let demo = DemoCredentials.fromLaunchArguments() {
            return AppModel(deviceName: deviceName, formats: .appleTV, addOnFormats: .vlcOnAppleTV, store: demo,
                            makeDecks: TVDeck.pair, specialModes: SpecialModeViews.all.registry)
        }
        #endif
        return AppModel(deviceName: deviceName, formats: .appleTV, addOnFormats: .vlcOnAppleTV, store: KeychainStore(),
                        makeDecks: TVDeck.pair, specialModes: SpecialModeViews.all.registry)
    }
}
