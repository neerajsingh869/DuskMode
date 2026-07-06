// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuskMode",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DuskMode",
            path: "Sources/DuskMode"
        )
    ],
    swiftLanguageVersions: [.v5]
)
