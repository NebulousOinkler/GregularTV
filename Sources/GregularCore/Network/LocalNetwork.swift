import Foundation

/// Which addresses are on the home network. Both of the app's checks read
/// addresses this one way: which servers plain http may reach
/// (`ServerAddress.isOnLocalNetwork`), and which devices may open the pages
/// the Apple TV serves (`LocalPage`).
public enum LocalNetwork {
    /// Whether `address`, an IP address as text, is on the home network:
    /// loopback, private or link-local. That's IPv4 127/8, 10/8, 172.16/12,
    /// 192.168/16 and 169.254/16, and IPv6 ::1, fc00::/7 (unique local) and
    /// fe80::/10 (link-local), with or without a zone ("fe80::1%en0"), and
    /// IPv4 mapped into IPv6 ("::ffff:192.168.1.5").
    ///
    /// Only the plain dotted form of an IPv4 address counts. Resolvers also
    /// read a lone number (`134744072`), hex (`0x08080808`) or zero-padded
    /// parts (`010`, octal on some platforms) as addresses, which could be
    /// public, so those never are. Carrier-grade NAT addresses (100.64/10)
    /// aren't either: Tailscale uses them, but so do internet providers,
    /// whose networks plain http would cross.
    public static func contains(address: String) -> Bool {
        var text = address.lowercased()
        if let zone = text.firstIndex(of: "%") { text = String(text[..<zone]) }
        if text.hasPrefix("::ffff:") { text = String(text.dropFirst(7)) }
        if let octets = dottedIPv4(text) {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (169, 254), (192, 168): return true
            case (172, let second): return (16...31).contains(second)
            default: return false
            }
        }
        guard text.contains(":") else { return false }
        if text == "::1" { return true }
        let first = text.split(separator: ":", omittingEmptySubsequences: false).first.flatMap { UInt16($0, radix: 16) } ?? 0
        return first & 0xFE00 == 0xFC00 || first & 0xFFC0 == 0xFE80
    }

    /// The four parts of a plain dotted IPv4 address, each 0 to 255 in
    /// decimal with no leading zero, or nil for any other form.
    private static func dottedIPv4(_ text: String) -> [Int]? {
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return nil }
        let octets = labels.compactMap { label -> Int? in
            guard !label.isEmpty, label.allSatisfy({ ("0"..."9").contains($0) }), label == "0" || !label.hasPrefix("0"),
                  let value = Int(label), (0...255).contains(value) else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }
}
