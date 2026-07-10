// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ScreenFramer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "ScreenFramerCore", dependencies: ["Yams"]),
        .target(name: "CGVirtualDisplayShim"),
        .executableTarget(
            name: "ScreenFramer",
            dependencies: ["ScreenFramerCore", "CGVirtualDisplayShim"]
        ),
        .testTarget(
            name: "ScreenFramerCoreTests",
            dependencies: ["ScreenFramerCore"]
        ),
    ]
)
