// swift-tools-version: 6.0
import PackageDescription

// The parts, each depending only on the ones before it:
//
//   GregularCore       the logic: schedules, shuffles, channels, commercials,
//                      the guide, preferences, what a typed code means
//                      (`CodeEntry`: a schedule code, or a special mode's
//                      keyword, by its hash in special-modes.jsonc), and the interfaces
//                      a media server must provide (`MediaLibrary`, `StreamSource`).
//                      Foundation only: no Jellyfin, no Apple TV, no UI.
//   GregularJellyfin   the connection to a Jellyfin server: sign-in, the
//                      library, streams. Implements Core's interfaces, and
//                      keeps its security rules itself (plain http only on
//                      the local network, `TransportRules`), so they hold on
//                      any platform. Foundation only.
//   GregularScreens    what the screens do, without drawing anything: the app's
//                      state and sign-in, channel surfing, the watch screen's
//                      rules (banner, overlays, curtain, remote actions), the
//                      remote's button tables, the words on screen,
//                      ChannelPlayer's decisions, and special modes (open,
//                      with their programmes; each front end lists its own
//                      screens for them in a `SpecialModeScreens`).
//                      Foundation and Observation only. It reaches video
//                      through `PlayerDeck`. Every
//                      string it hands a front end is plain text, to be shown
//                      as text (a web front end must escape it).
//   GregularKeychain   Apple platforms only: the sign-in kept in the Keychain
//                      (a `CredentialStore`). Other platforms bring their own.
//   The tvOS app       (App/GregularTV.xcodeproj) Apple TV itself: SwiftUI
//                      views that draw GregularScreens' models, the
//                      AVFoundation PlayerDeck, and the Siri Remote.
//
// A web version would reuse the first three and bring its own views,
// PlayerDeck, HTTPTransport and CredentialStore. A radio app could reuse
// GregularCore and GregularJellyfin.
// Each file sees only what it imports, members of extensions included (by
// default Swift lets one file's import leak extension members into every
// file of the module). So the layers in scripts/layer-check.sh hold file by
// file, checked by the compiler.
let strictImports: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

let package = Package(
    name: "Gregular",
    platforms: [.tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GregularCore", targets: ["GregularCore"]),
        .library(name: "GregularJellyfin", targets: ["GregularJellyfin"]),
        .library(name: "GregularScreens", targets: ["GregularScreens"]),
        .library(name: "GregularKeychain", targets: ["GregularKeychain"]),
    ],
    targets: [
        // channels.json and special-modes.jsonc are compiled in (not bundle files), so they're there on every platform, a browser included.
        .target(name: "GregularCore", resources: [.embedInCode("Resources/channels.json"), .embedInCode("Resources/special-modes.jsonc")],
                swiftSettings: strictImports),
        .target(name: "GregularJellyfin", dependencies: ["GregularCore"], swiftSettings: strictImports),
        // The pages served on the home network (the editing page, karaoke's song picker) are compiled in for
        // the Apple TV to serve; the web version copies the editing page's.
        .target(name: "GregularScreens", dependencies: ["GregularCore", "GregularJellyfin"],
                resources: [.embedInCode("LocalPages/Page/local-page.js"),
                             .embedInCode("Editing/Page/editor.css"), .embedInCode("Editing/Page/editor-body.html"),
                             .embedInCode("Editing/Page/editor.js"),
                             .embedInCode("Karaoke/Picker/picker.css"), .embedInCode("Karaoke/Picker/picker-body.html"),
                             .embedInCode("Karaoke/Picker/picker.js")],
                swiftSettings: strictImports),
        .target(name: "GregularKeychain", dependencies: ["GregularJellyfin"], swiftSettings: strictImports),
        // A tool, not part of the app: hashes a special mode's keyword for special-modes.jsonc.
        .executableTarget(name: "keyword-hash", dependencies: ["GregularCore"], path: "Tools/KeywordHash", swiftSettings: strictImports),
        .testTarget(name: "GregularCoreTests", dependencies: ["GregularCore"], swiftSettings: strictImports),
        .testTarget(name: "GregularJellyfinTests", dependencies: ["GregularJellyfin", "GregularCore"], swiftSettings: strictImports),
        // Tests/Shared is compiled into the app's tests too (the Xcode project).
        .testTarget(name: "GregularScreensTests", dependencies: ["GregularScreens", "GregularCore", "GregularJellyfin"],
                    path: "Tests", exclude: ["GregularCoreTests", "GregularJellyfinTests"],
                    sources: ["GregularScreensTests", "Shared"], swiftSettings: strictImports),
    ]
)
