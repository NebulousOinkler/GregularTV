import GregularCore

/// A special mode, open (`AppModel.Phase.special`): which mode, and the
/// programmes it plays from, fetched from the server and held in memory
/// only. Each front end draws it with the screens it lists for `mode.id`
/// (`SpecialModeScreens`); nothing here knows what they look like.
@MainActor public final class SpecialModeSession {
    public let mode: SpecialMode
    /// What it can play: the whole library, or the videos in its own (`SpecialMode.Catalogue`).
    public let programmes: [MediaItem]
    /// Where its programmes play from, for the models that play them.
    let streams: any StreamSource
    private let onExit: @MainActor (SpecialModeSession) -> Void

    init(mode: SpecialMode, programmes: [MediaItem], streams: any StreamSource,
         onExit: @escaping @MainActor (SpecialModeSession) -> Void) {
        self.mode = mode
        self.programmes = programmes
        self.streams = streams
        self.onExit = onExit
    }

    /// Leaves the mode, back to live TV.
    public func exit() {
        onExit(self)
    }
}
