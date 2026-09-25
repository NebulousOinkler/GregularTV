// swift-tools-version: 6.0
import PackageDescription

// Four parts, each depending only on the ones before it:
//
//   GregularCore       the logic: schedules, shuffles, channels, commercials,
//                      the guide, preferences, and the interfaces a media
//                      server must provide (`MediaLibrary`, `StreamSource`).
//                      Foundation only: no Jellyfin, no Apple TV, no UI.
//   GregularJellyfin   the connection to a Jellyfin server: sign-in, the
//                      library, streams. Implements Core's interfaces.
//   GregularScreens    what the screens do, without drawing anything: the app's
//                      state and sign-in, channel surfing, the watch screen's
//                      rules (banner, overlays, curtain, remote actions), the
//                      remote's button tables, the words on screen, and
//                      ChannelPlayer's decisions. Foundation and Observation
//                      only. It reaches video through `PlayerDeck`.
//   The tvOS app       (App/GregularTV.xcodeproj) Apple TV itself: SwiftUI
//                      views that draw GregularScreens' models, the
//                      AVFoundation PlayerDeck, and the Siri Remote.
//
// A web version would reuse the first three and bring its own views and
// PlayerDeck. A radio app could reuse GregularCore and GregularJellyfin.
let package = Package(
    name: "Gregular",
    platforms: [.tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GregularCore", targets: ["GregularCore"]),
        .library(name: "GregularJellyfin", targets: ["GregularJellyfin"]),
        .library(name: "GregularScreens", targets: ["GregularScreens"]),
    ],
    targets: [
        .target(name: "GregularCore", resources: [.process("Resources")]),
        .target(name: "GregularJellyfin", dependencies: ["GregularCore"]),
        .target(name: "GregularScreens", dependencies: ["GregularCore", "GregularJellyfin"]),
        .testTarget(name: "GregularCoreTests", dependencies: ["GregularCore"]),
        .testTarget(name: "GregularJellyfinTests", dependencies: ["GregularJellyfin", "GregularCore"]),
        .testTarget(name: "GregularScreensTests", dependencies: ["GregularScreens", "GregularCore"]),
    ]
)
