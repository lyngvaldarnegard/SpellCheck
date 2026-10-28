// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpellCheckEngine",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SpellCheckEngine", targets: ["SpellCheckEngine"])
    ],
    dependencies: [
        .package(path: "../Core")
    ],
    targets: [
        .target(
            name: "SpellCheckEngine",
            dependencies: [
                .product(name: "SpellCheckCore", package: "Core")
            ]
        ),
        .testTarget(
            name: "SpellCheckEngineTests",
            dependencies: ["SpellCheckEngine"]
        )
    ]
)
