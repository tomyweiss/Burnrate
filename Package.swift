// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tokens",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Tokens", targets: ["Tokens"]),
        .library(name: "TokensCore", targets: ["TokensCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .target(
            name: "TokensCore",
            path: "Sources/TokensCore"
        ),
        .executableTarget(
            name: "Tokens",
            dependencies: [
                "TokensCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Tokens",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TokensTests",
            dependencies: ["TokensCore", "Tokens"],
            path: "Tests/TokensTests"
        )
    ]
)
