import GregularScreens

/// Each special mode's page in a browser, by its id in special-modes.jsonc
/// (see `SpecialModeRegistry`). The web version only accepts the keywords
/// of the modes listed here.
@MainActor enum SpecialModePages {
    static let all = SpecialModeScreens<any Page>([
        .karaoke: { KaraokePage(session: $0) },
    ])
}
