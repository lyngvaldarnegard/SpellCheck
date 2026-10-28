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
        .package(path: "../Engine")
    ],
    targets: [
        .executableTarget(
            name: "SpellCheck",
            dependencies: [
                .product(name: "SpellCheckCore", package: "Core"),
                .product(name: "SpellCheckEngine", package: "Engine")
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
