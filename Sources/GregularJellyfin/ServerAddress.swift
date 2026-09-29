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
    /// loopback, private, link-local or carrier-grade NAT address (the last is
    /// what Tailscale uses).
    public static func isOnLocalNetwork(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let ipv4 = ipv4Octets(host) {
            switch (ipv4[0], ipv4[1]) {
            case (10, _), (127, _), (169, 254), (192, 168): return true
            case (172, let b): return (16...31).contains(b)
            case (100, let b): return (64...127).contains(b)
            default: return false
            }
        }
        if host.contains(":") {   // IPv6: loopback, link-local (fe80::/10), unique local (fc00::/7)
            return host == "::1" || ["fe8", "fe9", "fea", "feb", "fc", "fd"].contains { host.hasPrefix($0) }
        }
        return host == "localhost" || !host.contains(".") || host.hasSuffix(".local") || host.hasSuffix(".home.arpa")
    }

    private static func ipv4Octets(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { part in Int(part).flatMap { (0...255).contains($0) && part.allSatisfy(\.isNumber) ? $0 : nil } }
        return parts.count == 4 && octets.count == 4 ? octets : nil
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
