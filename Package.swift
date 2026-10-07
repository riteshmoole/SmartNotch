// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SmartNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SmartNotch",
            path: "Sources/SmartNotch"
        )
    ],
    swiftLanguageModes: [.v5]
)
