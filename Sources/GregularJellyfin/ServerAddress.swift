import Foundation
import GregularCore

public enum ServerAddress {
    /// The URLs to try, in order, for what the user typed. Typing "https://"
    /// with a TV remote is tedious, so when no scheme is given we try https
    /// first, then http (common for LAN servers on port 8096). Plain http is
    /// only tried on the local network (see `isAllowed(_:)`).
    public static func candidates(for input: String) -> [URL] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = trimmed.contains("://") ? normalize(trimmed).map { [$0] } ?? []
            : ["https://", "http://"].compactMap { normalize($0 + trimmed) }
        return urls.filter(isAllowed)
    }

    /// Whether the app may talk to `url` at all: https anywhere, but plain
    /// http only on the local network, where a password sent in the clear
    /// doesn't cross the internet. Every request checks this (`JellyfinAPI`),
    /// whatever platform the app runs on; Apple's App Transport Security is
    /// only a second line of defence on Apple TV.
    public static func isAllowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": true
        case "http": url.host().map(isOnLocalNetwork) ?? false
        default: false
        }
    }

    /// Whether `host` names something on the local network: `localhost`, an
    /// unqualified name (`jellyfin`), a `.local` or `.home.arpa` name, or a
    /// loopback, private or link-local address.
    ///
    /// Only the plain dotted form of an IPv4 address counts. Resolvers also
    /// read a lone number (`134744072`), hex (`0x08080808`) or zero-padded
    /// parts (`010`, octal on some platforms) as addresses, which could be
    /// public, so those are never local. Carrier-grade NAT addresses
    /// (100.64/10) aren't either: Tailscale uses them, but so do internet
    /// providers, whose networks plain http would cross.
    public static func isOnLocalNetwork(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host.contains(":") {   // IPv6: loopback, link-local (fe80::/10), unique local (fc00::/7)
            return host == "::1" || ["fe8", "fe9", "fea", "feb", "fc", "fd"].contains { host.hasPrefix($0) }
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        // Anything made only of numbers is an address: local only in the plain dotted form.
        if labels.allSatisfy({ label in !label.isEmpty && (label.allSatisfy(\.isNumber) || label.hasPrefix("0x")) }) {
            guard let ipv4 = dottedIPv4(labels) else { return false }
            switch (ipv4[0], ipv4[1]) {
            case (10, _), (127, _), (169, 254), (192, 168): return true
            case (172, let b): return (16...31).contains(b)
            default: return false
            }
        }
        return host == "localhost" || !host.contains(".") || host.hasSuffix(".local") || host.hasSuffix(".home.arpa")
    }

    /// The four parts of a plain dotted IPv4 address, each 0 to 255 in
    /// decimal with no leading zero, or nil for any other form.
    private static func dottedIPv4(_ labels: [Substring]) -> [Int]? {
        guard labels.count == 4 else { return nil }
        let octets = labels.compactMap { label -> Int? in
            guard label.allSatisfy(\.isASCIIDigit), label == "0" || !label.hasPrefix("0"), let value = Int(label),
                  (0...255).contains(value) else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }

    /// Turns what the user typed into a server base URL.
    ///
    /// `"192.168.1.5:8096"` becomes `http://192.168.1.5:8096`, and
    /// `"https://media.example.com/jellyfin/"` becomes
    /// `https://media.example.com/jellyfin`. A reverse-proxy sub-path is kept.
    /// Returns nil for input that isn't an http(s) address.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }

        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
