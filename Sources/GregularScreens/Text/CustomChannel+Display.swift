import GregularCore

extension CustomChannel {
    /// What it plays, in a line: "Comedy · Episodes", "1950–1979 · Movies".
    public var summary: String {
        let rule = switch rule {
        case .everything: "Everything"
        case .genre(let name), .series(let name), .tag(let name): name
        case .years(let from, let to): "\(from.map(String.init) ?? "Any year")–\(to.map(String.init) ?? "now")"
        }
        return "\(rule) · \(ChannelEditorModel.Content(kinds: kinds).label)"
    }
}
