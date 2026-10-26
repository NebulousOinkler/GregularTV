import Foundation
import GregularCore

/// Turns any error into a short, plain message for the screen.
///
/// The system's own error text can be technical, and can include the server's
/// address (for example, certificate errors name the host). A TV screen is
/// seen by anyone in the room, so errors are always shown through this.
public enum FriendlyError {
    public static func message(for error: (any Error)?) -> String {
        guard let error else { return "Something went wrong." }
        // The media server's own errors are already written for people.
        if let failure = error as? any MediaServiceFailure { return failure.localizedDescription }
        // The system's network errors aren't: say what kind of trouble it is (`ErrorKind`).
        if error is URLError { return message(for: ErrorKind(error)) }
        if error is DecodingError { return "Your server sent a reply the app didn't understand. Is it a \(AppModel.serverName) server?" }
        // (The app's own errors, such as a stall or a format a player can't
        // show, come as LocalizedErrors written for people: see each `PlayerDeck`.)
        return (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    /// A system network error's words, by its kind.
    private static func message(for kind: ErrorKind) -> String {
        switch kind {
        case .offline, .connection:
            "This device isn't connected to the network."
        case .timedOut:
            "Your \(AppModel.serverName) server took too long to respond."
        case .unreachable:
            "Can't reach your \(AppModel.serverName) server. Check that it's switched on and connected."
        case .insecure:
            "Couldn't make a secure connection to your \(AppModel.serverName) server."
        case .needsHTTPS:
            "This server needs a secure (https) address."
        case .signedOut, .server, .unplayable, .unknown:
            "Couldn't talk to your \(AppModel.serverName) server."
        }
    }
}
