// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SpellCheck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SpellCheck", targets: ["SpellCheck"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Engine"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "SpellCheck",
            dependencies: [
                .product(name: "SpellCheckCore", package: "Core"),
                .product(name: "SpellCheckEngine", package: "Engine"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SpellCheck"
        ),
        .testTarget(
            name: "SpellCheckTests",
            dependencies: ["SpellCheck"],
            path: "Tests/SpellCheckTests"
        )
    ]
)
