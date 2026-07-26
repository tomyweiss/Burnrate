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
    targets: [
        .target(
            name: "TokensCore",
            path: "Sources/TokensCore"
        ),
        .executableTarget(
            name: "Tokens",
            dependencies: ["TokensCore"],
            path: "Sources/Tokens"
        ),
        .testTarget(
            name: "TokensTests",
            dependencies: ["TokensCore"],
            path: "Tests/TokensTests"
        )
    ]
)
