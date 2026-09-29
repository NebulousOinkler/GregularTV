import Foundation
import GregularCore

extension SetTimes {
    /// What's set, each name once: "Alpha, Explosions".
    public var summary: String {
        var seen = Set<String>()
        return programmes.map(\.match.title).filter { seen.insert($0.lowercased()).inserted }.joined(separator: ", ")
    }
}
