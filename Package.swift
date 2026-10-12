// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blinker",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .library(name: "BlinkerCore", targets: ["BlinkerCore"]),
        .executable(name: "Blinker", targets: ["BlinkerApp"]),
    ],
    targets: [
        .target(
            name: "BlinkerCore",
            path: "Sources/BlinkerCore",
            resources: [.process("Resources")]
        ),
        .target(
            name: "BlinkerHelperXPC",
            path: "Sources/BlinkerHelperXPC"
        ),
        .executableTarget(
            name: "BlinkerLowPowerHelper",
            dependencies: ["BlinkerHelperXPC"],
            path: "Sources/BlinkerLowPowerHelper"
        ),
        .executableTarget(
            name: "BlinkerApp",
            dependencies: ["BlinkerCore", "BlinkerHelperXPC"],
            path: "Sources/BlinkerApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BlinkerCoreTests",
            dependencies: ["BlinkerCore"],
            path: "Tests/BlinkerCoreTests"
        ),
        .testTarget(
            name: "BlinkerAppTests",
            dependencies: ["BlinkerApp", "BlinkerCore", "BlinkerHelperXPC"],
            path: "Tests/BlinkerAppTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
