// swift-tools-version: 6.0
import PackageDescription

// Three parts, each depending only on the ones before it:
//
//   GregularCore       the logic: schedules, shuffles, channels, commercials,
//                      the guide, preferences, and the interfaces a media
//                      server must provide (`MediaLibrary`, `StreamSource`).
//                      Foundation only: no Jellyfin, no Apple TV, no UI.
//   GregularJellyfin   the connection to a Jellyfin server: sign-in, the
//                      library, streams. Implements Core's interfaces.
//   The tvOS app       (App/GregularTV.xcodeproj) the screens and the player.
//                      Its player and views use only Core; only the app's
//                      top-level model and sign-in screen know about Jellyfin.
//
// A radio app could reuse GregularCore and GregularJellyfin as they are, with
// its own player and screens.
let package = Package(
    name: "Gregular",
    platforms: [.tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GregularCore", targets: ["GregularCore"]),
        .library(name: "GregularJellyfin", targets: ["GregularJellyfin"]),
    ],
    targets: [
        .target(name: "GregularCore", resources: [.process("Resources")]),
        .target(name: "GregularJellyfin", dependencies: ["GregularCore"]),
        .testTarget(name: "GregularCoreTests", dependencies: ["GregularCore"]),
        .testTarget(name: "GregularJellyfinTests", dependencies: ["GregularJellyfin", "GregularCore"]),
    ]
)
