import GregularScreens

extension AppModel {
    /// The model the app starts with, playing on AVFoundation decks. Release
    /// builds always use the saved sign-in (or show sign-in); Debug builds
    /// can instead start in demo mode (see `DemoCredentials`).
    static func forLaunch() -> AppModel {
        #if DEBUG
        if let demo = DemoCredentials.fromLaunchArguments() {
            return AppModel(store: demo, makeDecks: AVPlayerDeck.pair)
        }
        #endif
        return AppModel(makeDecks: AVPlayerDeck.pair)
    }
}
