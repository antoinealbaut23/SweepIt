// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SweepIt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SweepIt",
            path: "Sources/SweepIt",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
