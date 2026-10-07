import GregularCore

/// A front end's screens for the special modes, by mode id: the other half
/// of `SpecialModeRegistry`, which takes a keyword to a mode. Each front end
/// keeps one, of its own kind of screen, and hands `registry` to `AppModel`,
/// so the keywords it accepts are only those of modes it can draw.
@MainActor public struct SpecialModeScreens<Screen> {
    public typealias Make = @MainActor (SpecialModeSession) -> Screen

    private let screens: [SpecialMode.ID: Make]
    /// The modes these screens are for, from `bundled`.
    public let registry: SpecialModeRegistry

    /// - Parameter bundled: every mode there is; those without a screen here are left out.
    public init(_ screens: [SpecialMode.ID: Make], bundled: SpecialModeRegistry? = try? .bundled()) {
        self.screens = screens
        registry = (bundled ?? SpecialModeRegistry()).limited(to: Set(screens.keys))
    }

    /// `session`'s screen.
    public func screen(for session: SpecialModeSession) -> Screen? {
        screens[session.mode.id]?(session)
    }
}
