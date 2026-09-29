import Foundation
import GregularCore

extension SetTimes {
    /// What's set: "Alpha, Explosions".
    public var summary: String {
        programmes.map(\.match.title).joined(separator: ", ")
    }
}
