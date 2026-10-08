import Foundation
import GregularBrowser
import Testing

/// Which requests the browser is told are going to the home network.
struct BrowserNetworkTests {
    @Test(arguments: [
        ("http://192.168.1.5:8096", true),
        ("http://jellyfin:8096", false),         // a one-word name: refused (ServerAddress.isOnLocalNetwork)
        ("http://nas.local:8096", true),
        ("http://localhost:8096", false),        // this computer: already secure to a browser
        ("http://127.0.0.1:8765", false),
        ("https://192.168.1.5:8920", false),     // https is never mixed content
        ("http://tv.example.com", false),        // not the home network: refused anyway
    ])
    func plainHTTPOnTheHomeNetworkIsMarkedLocal(url: String, local: Bool) {
        #expect(BrowserNetwork.isLocalHTTP(URL(string: url)!) == local)
    }
}
