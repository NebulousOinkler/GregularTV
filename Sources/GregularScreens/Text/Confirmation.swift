import Foundation

/// A question to ask before something that can't be undone, so one stray
/// click (or a button pressed by anything paired with the device) isn't
/// enough. Every front end must ask it before doing the action: Screens
/// decides which actions need one and what it says, so a new front end
/// can't forget. Plain text, like everything Screens hands a front end.
public struct Confirmation: Sendable, Equatable {
    /// The action, as its button says it: "Sign Out".
    public let action: String
    /// "Sign out of Home Media?"
    public let question: String
    /// What happens, and how to undo it if that's possible at all.
    public let detail: String
}

extension Confirmation {
    /// Closing the channel editor with changes that aren't saved.
    public static let discardEdits = Confirmation(
        action: "Close Without Saving",
        question: "Close without saving?",
        detail: "Your changes to your channels and set times will be lost.")

    /// Signing out of every server, then forgetting everything the app
    /// keeps `here` (such as "in this browser"): your channels, set times
    /// and settings.
    public static func forgetEverything(_ here: String) -> Confirmation {
        Confirmation(
            action: "Forget Everything",
            question: "Forget everything \(here)?",
            detail: "Signs out of every server, then deletes your channels, set times and settings kept \(here), "
                + "and the app starts again. This can't be undone.")
    }
}
