import Foundation
import Testing
@testable import GregularCore

struct LocalNetworkTests {
    @Test(arguments: ["192.168.1.20", "10.0.0.5", "172.16.0.1", "172.31.255.255", "169.254.3.4", "127.0.0.1",
                      "::1", "fe80::1%en0", "febf::1", "fd12:3456::1", "fc00::1", "::ffff:192.168.1.20"])
    func homeAddresses(address: String) {
        #expect(LocalNetwork.contains(address: address))
    }

    @Test(arguments: ["8.8.8.8", "172.32.0.1", "100.64.0.1", "0.0.0.0", "2001:4860::8888", "::ffff:8.8.8.8", "", "example.com",
                      // Short forms of addresses outside fc00::/7 and fe80::/10: 0fc1::1, 0fe8::1.
                      "fc1::1", "fe8::1", "fec0::1",
                      // Other ways to write an IPv4 address, which a resolver may read as a public one.
                      "010.0.0.5", "10.0.0.256", "10.1.1", "0x0a.1.1.1"])
    func elsewhere(address: String) {
        #expect(!LocalNetwork.contains(address: address))
    }
}
