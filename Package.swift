// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tokens",
    platforms: [
        .macOS(.v26)
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
