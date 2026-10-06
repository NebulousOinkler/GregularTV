import GregularScreens
import SwiftUI

/// Each special mode's screen on Apple TV, by its id in special-modes.jsonc
/// (see `SpecialModeRegistry`). Apple TV only accepts the keywords of the
/// modes listed here.
@MainActor enum SpecialModeViews {
    static let all = SpecialModeScreens<AnyView>([:])   // ← add each mode's screen: ["its-id": { session in … }]
}
