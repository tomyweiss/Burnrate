// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tokens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Tokens", targets: ["Tokens"])
    ],
    targets: [
        .executableTarget(
            name: "Tokens",
            path: "Sources/Tokens"
        )
    ]
)
