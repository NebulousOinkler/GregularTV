import GregularCore

extension CustomChannel {
    /// What it plays, in a line: "Comedy · Episodes", "1950–1979 · Movies",
    /// "Comedy or Taskmaster, not Christmas · Episodes and Movies".
    public var summary: String {
        "\(rule.summary) · \(playsLabel)"
    }

    /// "Episodes", "Movies" or "Episodes and Movies".
    private var playsLabel: String {
        switch (kinds.contains(.episode), kinds.contains(.movie)) {
        case (true, false): "Episodes"
        case (false, true): "Movies"
        default: "Episodes and Movies"
        }
    }
}

extension CustomChannel.Rule {
    /// The conditions in words: "Comedy or Taskmaster, and 1990–1999, not Christmas".
    public var summary: String {
        let any = conditions(.anyOf).map(\.label).joined(separator: " or ")
        let all = conditions(.allOf).map(\.label).joined(separator: " and ")
        let none = conditions(.noneOf).map(\.label).joined(separator: " or ")
        let parts = [any.isEmpty ? nil : any,
                     all.isEmpty ? nil : (any.isEmpty ? all : "and \(all)"),
                     none.isEmpty ? nil : "not \(none)"].compactMap { $0 }
        return parts.isEmpty ? "Everything" : parts.joined(separator: ", ")
    }
}

extension CustomChannel.Rule.Match {
    /// "Comedy", "Taskmaster", "1950–1979".
    public var label: String {
        switch self {
        case .genre(let name), .series(let name), .tag(let name): name
        case .years(let from, let to): "\(from.map(String.init) ?? "Any year")–\(to.map(String.init) ?? "now")"
        }
    }
}
