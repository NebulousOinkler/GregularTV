import GregularCore

/// A special mode, open (`AppModel.Phase.special`): which mode, and the
/// programmes it plays from, fetched from the server and held in memory
/// only. Each front end draws it with the screens it lists for `mode.id`
/// (`SpecialModeScreens`); nothing here knows what they look like.
@MainActor public final class SpecialModeSession {
    public let mode: SpecialMode
    /// What it can play: the whole library, or what's in its own libraries (`SpecialMode.Catalogue`).
    public let programmes: [MediaItem]
    /// What this device plays.
    public let formats: PlayableFormats
    /// The server, for the mode's models: songs' lyrics, and original files to play whole.
    let media: any LyricsSource & OriginalFiles
    private let onExit: @MainActor (SpecialModeSession) -> Void

    init(mode: SpecialMode, programmes: [MediaItem], formats: PlayableFormats, media: any LyricsSource & OriginalFiles,
         onExit: @escaping @MainActor (SpecialModeSession) -> Void) {
        self.mode = mode
        self.programmes = programmes
        self.formats = formats
        self.media = media
        self.onExit = onExit
    }

    /// Leaves the mode, back to live TV.
    public func exit() {
        onExit(self)
    }
}
