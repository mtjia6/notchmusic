// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchMusic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchMusic",
            path: "Sources/NotchMusic",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
