// swift-tools-version: 6.0
import PackageDescription

// The parts, each depending only on the ones before it:
//
//   GregularCore       the logic: schedules, shuffles, channels, commercials,
//                      the guide, preferences, and the interfaces a media
//                      server must provide (`MediaLibrary`, `StreamSource`).
//                      Foundation only: no Jellyfin, no Apple TV, no UI.
//   GregularJellyfin   the connection to a Jellyfin server: sign-in, the
//                      library, streams. Implements Core's interfaces, and
//                      keeps its security rules itself (plain http only on
//                      the local network, `TransportRules`), so they hold on
//                      any platform. Foundation only.
//   GregularScreens    what the screens do, without drawing anything: the app's
//                      state and sign-in, channel surfing, the watch screen's
//                      rules (banner, overlays, curtain, remote actions), the
//                      remote's button tables, the words on screen, and
//                      ChannelPlayer's decisions. Foundation and Observation
//                      only. It reaches video through `PlayerDeck`. Every
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
        // channels.json is compiled in (not a bundle file), so it's there on every platform, a browser included.
        .target(name: "GregularCore", resources: [.embedInCode("Resources/channels.json")], swiftSettings: strictImports),
        .target(name: "GregularJellyfin", dependencies: ["GregularCore"], swiftSettings: strictImports),
        // The editing page's files are compiled in for the Apple TV to serve; the web version copies them.
        .target(name: "GregularScreens", dependencies: ["GregularCore", "GregularJellyfin"],
                resources: [.embedInCode("Editing/Page/editor.css"), .embedInCode("Editing/Page/editor-body.html"),
                            .embedInCode("Editing/Page/editor.js")],
                swiftSettings: strictImports),
        .target(name: "GregularKeychain", dependencies: ["GregularJellyfin"], swiftSettings: strictImports),
        .testTarget(name: "GregularCoreTests", dependencies: ["GregularCore"], swiftSettings: strictImports),
        .testTarget(name: "GregularJellyfinTests", dependencies: ["GregularJellyfin", "GregularCore"], swiftSettings: strictImports),
        // Tests/Shared is compiled into the app's tests too (the Xcode project).
        .testTarget(name: "GregularScreensTests", dependencies: ["GregularScreens", "GregularCore", "GregularJellyfin"],
                    path: "Tests", exclude: ["GregularCoreTests", "GregularJellyfinTests"],
                    sources: ["GregularScreensTests", "Shared"], swiftSettings: strictImports),
    ]
)
