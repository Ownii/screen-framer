// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFramer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ScreenFramerCore"),
        .executableTarget(
            name: "ScreenFramer",
            dependencies: ["ScreenFramerCore"]
        ),
        .testTarget(
            name: "ScreenFramerCoreTests",
            dependencies: ["ScreenFramerCore"]
        ),
    ]
)
