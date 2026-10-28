// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpellCheckCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SpellCheckCore", targets: ["SpellCheckCore"])
    ],
    targets: [
        .target(name: "SpellCheckCore"),
        .testTarget(name: "SpellCheckCoreTests", dependencies: ["SpellCheckCore"])
    ]
)
