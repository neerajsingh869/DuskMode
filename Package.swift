// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NightFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NightFlow",
            path: "Sources/NightFlow"
        )
    ],
    swiftLanguageVersions: [.v5]
)
