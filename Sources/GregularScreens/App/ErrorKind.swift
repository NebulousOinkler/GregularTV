import Foundation
import GregularCore

/// What kind of trouble an error is, decided in one place for everything
/// that reacts to errors: the player's retries (`ChannelPlayer`: would a
/// lower quality help?) and the words on screen (`FriendlyError`).
public enum ErrorKind: Equatable, Sendable {
    /// The server rejected the session: only signing in again helps.
    case signedOut
    /// The connection dropped or couldn't keep up (`ConnectionFailure`): a
    /// lower quality may help.
    case connection
    /// The server took too long to answer: busy, or the connection was.
    case timedOut
    /// This device isn't on a network.
    case offline
    /// The server can't be found or reached at all.
    case unreachable
    /// A secure connection to the server failed (its certificate).
    case insecure
    /// The address needs https.
    case needsHTTPS
    /// The server answered with an error, or with something the app didn't understand.
    case server
    case unknown

    public init(_ error: (any Error)?) {
        switch error {
        case let failure as any MediaServiceFailure:
            self = failure.isSessionExpired ? .signedOut : .server
        case is any ConnectionFailure:
            self = .connection
        case let url as URLError:
            self = Self.kind(of: url.code)
        case is DecodingError:
            self = .server
        // A network error as an `NSError`, as players report them. Apple's
        // Foundation makes it a `URLError` above; others' don't.
        case let error as NSError where error.domain == NSURLErrorDomain:
            // (Optional only where the code might not be a known one.)
            let code: URLError.Code? = URLError.Code(rawValue: error.code)
            self = code.map(Self.kind(of:)) ?? .unknown
        default:
            self = .unknown
        }
    }

    private static func kind(of code: URLError.Code) -> ErrorKind {
        switch code {
        case .networkConnectionLost: .connection
        case .timedOut: .timedOut
        case .notConnectedToInternet: .offline
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: .unreachable
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected: .insecure
        case .appTransportSecurityRequiresSecureConnection: .needsHTTPS
        case .badServerResponse, .cannotParseResponse, .zeroByteResource: .server
        default: .unknown
        }
    }
}
