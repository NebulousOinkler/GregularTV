import Foundation
import GregularTVCore
import Testing
@testable import GregularTV

/// What reaches the screen is plain language, and never the server's address.
struct FriendlyErrorTests {
    let host = "rasp.example.ts.net"

    @Test func systemNetworkErrorsNeverShowTheServerAddress() {
        let codes: [URLError.Code] = [.serverCertificateUntrusted, .secureConnectionFailed, .cannotFindHost,
                                      .timedOut, .notConnectedToInternet, .badServerResponse]
        for code in codes {
            let error = URLError(code, userInfo: [
                NSURLErrorFailingURLErrorKey: URL(string: "https://\(host)/Items?ApiKey=secret")!,
                NSLocalizedDescriptionKey: "A server pretending to be “\(host)” … ApiKey=secret",
            ])
            let message = FriendlyError.message(for: error)
            #expect(!message.contains(host) && !message.contains("secret"), "\(code): \(message)")
        }
    }

    @Test func ourOwnMessagesPassThrough() {
        #expect(FriendlyError.message(for: JellyfinError.unauthorized) == JellyfinError.unauthorized.localizedDescription)
        #expect(FriendlyError.message(for: StallError()) == StallError().localizedDescription)
    }

    @Test func unknownErrorsGetAGenericMessage() {
        struct Mystery: Error {}
        #expect(FriendlyError.message(for: Mystery()) == "Something went wrong.")
        #expect(FriendlyError.message(for: nil) == "Something went wrong.")
    }
}
