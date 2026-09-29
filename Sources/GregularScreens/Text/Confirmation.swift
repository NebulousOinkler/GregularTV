import Foundation

/// A question to ask before something that can't be undone, so one stray
/// click (or a button pressed by anything paired with the device) isn't
/// enough. Every front end must ask it before doing the action: Screens
/// decides which actions need one and what it says, so a new front end
/// can't forget. Plain text, like everything Screens hands a front end.
public struct Confirmation: Sendable, Equatable {
    /// The action, as its button says it: "Sign Out".
    public let action: String
    /// "Sign out of Jellyfin?"
    public let question: String
    /// What happens, and how to undo it if that's possible at all.
    public let detail: String
}
