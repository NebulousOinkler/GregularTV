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

    /// Whether `host` names something on the local network: `localhost`, a
    /// `.local` or `.home.arpa` name, or a loopback, private or link-local
    /// address (`LocalNetwork`, which reads only the plain dotted form of an
    /// IPv4 address as local).
    ///
    /// Not a one-word name (`nas`): a network's DNS can add its own domain
    /// to one (`nas.office.example.com`) and reach a host somewhere else, and
    /// a password sent there over plain http would cross networks unencrypted.
    public static func isOnLocalNetwork(_ host: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        // Anything made only of numbers is an address, in some form, as is anything with a colon (IPv6).
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if host.contains(":") || labels.allSatisfy({ label in !label.isEmpty && (label.allSatisfy(\.isNumber) || label.hasPrefix("0x")) }) {
            return LocalNetwork.contains(address: host)
        }
        return host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".home.arpa")
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
