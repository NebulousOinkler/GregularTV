// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GregularTVCore",
    platforms: [.tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GregularTVCore", targets: ["GregularTVCore"]),
    ],
    targets: [
        .target(name: "GregularTVCore", resources: [.process("Resources")]),
        .testTarget(name: "GregularTVCoreTests", dependencies: ["GregularTVCore"]),
    ]
)
