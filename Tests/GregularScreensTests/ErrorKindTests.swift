import Foundation
import GregularCore
import GregularJellyfin
import Testing
@testable import GregularScreens

/// Every error gets one kind, which the retries and the words on screen both use.
struct ErrorKindTests {
    @Test func theServersOwnErrors() {
        #expect(ErrorKind(JellyfinError.unauthorized) == .signedOut)
        #expect(ErrorKind(JellyfinError.httpStatus(500)) == .server)
        #expect(ErrorKind(JellyfinError.invalidResponse) == .server)
        #expect(ErrorKind(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))) == .server)
    }

    /// Only these say the connection couldn't carry the stream.
    @Test func connectionTrouble() {
        #expect(ErrorKind(StallError()) == .connection)
        #expect(ErrorKind(URLError(.networkConnectionLost)) == .connection)
        #expect(ErrorKind(URLError(.timedOut)) == .timedOut)
    }

    @Test func networkErrorsByCode() {
        let kinds: [(URLError.Code, ErrorKind)] = [
            (.notConnectedToInternet, .offline), (.cannotFindHost, .unreachable), (.cannotConnectToHost, .unreachable),
            (.dnsLookupFailed, .unreachable), (.serverCertificateUntrusted, .insecure), (.secureConnectionFailed, .insecure),
            (.appTransportSecurityRequiresSecureConnection, .needsHTTPS), (.badServerResponse, .server), (.cancelled, .unknown),
        ]
        for (code, kind) in kinds { #expect(ErrorKind(URLError(code)) == kind, "\(code)") }
    }

    /// A network error inside an `NSError` (as players report them) is still that error.
    @Test func bridgedNetworkErrors() {
        #expect(ErrorKind(NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue)) == .connection)
    }

    @Test func anythingElseIsUnknown() {
        struct Mystery: Error {}
        #expect(ErrorKind(Mystery()) == .unknown && ErrorKind(nil) == .unknown)
    }
}
