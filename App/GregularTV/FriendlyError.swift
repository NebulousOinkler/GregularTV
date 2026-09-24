import AVFoundation
import Foundation
import GregularTVCore

/// Turns any error into a short, plain message for the screen.
///
/// The system's own error text can be technical, and can include the server's
/// address (for example, certificate errors name the host). A TV screen is
/// seen by anyone in the room, so errors are always shown through this.
enum FriendlyError {
    static func message(for error: (any Error)?) -> String {
        guard let error else { return "Something went wrong." }
        // Our own errors are already written for people.
        if let jellyfin = error as? JellyfinError { return jellyfin.localizedDescription }
        if let stall = error as? StallError { return stall.localizedDescription }
        if let url = error as? URLError { return message(for: url) }
        if error is DecodingError { return "Your server sent a reply the app didn't understand. Is it a Jellyfin server?" }
        if (error as NSError).domain == AVFoundationErrorDomain {
            return "This programme couldn't be played. It may be in a format Apple TV can't show."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            "The Apple TV isn't connected to the network."
        case .timedOut:
            "Your Jellyfin server took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "Can't reach your Jellyfin server. Check that it's switched on and connected."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            "Couldn't make a secure connection to your Jellyfin server."
        case .appTransportSecurityRequiresSecureConnection:
            "This server needs a secure (https) address."
        default:
            "Couldn't talk to your Jellyfin server."
        }
    }
}
