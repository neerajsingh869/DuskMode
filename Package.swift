// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuskMode",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic (no AppKit): colour maths, NOAA solar calculator, circadian
        // timeline. Split out so DuskModeSelfTest can exercise it — this machine
        // has only Command Line Tools, which ship neither XCTest nor Swift Testing,
        // so `swift test` is unavailable and tests run as a plain executable.
        .target(
            name: "DuskModeCore",
            path: "Sources/DuskModeCore"
        ),
        .executableTarget(
            name: "DuskMode",
            dependencies: ["DuskModeCore"],
            path: "Sources/DuskMode"
        ),
        // Run with: swift run DuskModeSelfTest   (exits non-zero on any failure)
        .executableTarget(
            name: "DuskModeSelfTest",
            dependencies: ["DuskModeCore"],
            path: "Sources/DuskModeSelfTest"
        )
    ],
    swiftLanguageVersions: [.v5]
)
