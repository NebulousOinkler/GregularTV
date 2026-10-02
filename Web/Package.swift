// swift-tools-version: 6.0
import PackageDescription

// Gregular TV in a web browser (WEB_PLAN.md). A package of its own, so the
// Apple TV app never fetches the web's dependencies. It reuses the main
// package's parts and brings what a browser needs instead of Apple's:
//
//   GregularBrowser   the browser's side of GregularJellyfin and
//                     GregularCore: requests through fetch(), the sign-ins
//                     kept encrypted in the browser, preferences in local
//                     storage. The only web code that sees Jellyfin types.
//   GregularWeb       the web app: pages drawn from GregularScreens' models,
//                     <video> playback (`VideoDeck`), the keyboard. Never
//                     imports GregularJellyfin (scripts/layer-check.sh).
//
// Build with scripts/build-web.sh, which needs the swift.org toolchain and
// its WebAssembly SDK (README, *The web version*).
let strictImports: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

let package = Package(
    name: "GregularWebApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "Gregular", path: ".."),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", exact: "0.59.0"),
    ],
    targets: [
        .target(name: "GregularBrowser", dependencies: [
            .product(name: "GregularCore", package: "Gregular"),
            .product(name: "GregularJellyfin", package: "Gregular"),
            .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            .product(name: "JavaScriptFoundationCompat", package: "JavaScriptKit"),
        ], swiftSettings: strictImports),
        .executableTarget(name: "GregularWeb", dependencies: [
            "GregularBrowser",
            .product(name: "GregularCore", package: "Gregular"),
            .product(name: "GregularScreens", package: "Gregular"),
            .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
        ], swiftSettings: strictImports,
        // An 8 MB stack. WebAssembly has no tail calls, so an `await` that
        // finishes without suspending stays on the stack until its caller
        // returns, and the linker's default stack is tiny.
        linkerSettings: [.unsafeFlags(["-Xlinker", "-z", "-Xlinker", "stack-size=8388608"])]),
        .testTarget(name: "GregularBrowserTests", dependencies: [
            "GregularBrowser",
            .product(name: "GregularCore", package: "Gregular"),
            .product(name: "GregularJellyfin", package: "Gregular"),
            .product(name: "JavaScriptKit", package: "JavaScriptKit"),
            .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
        ], swiftSettings: strictImports),
    ]
)
