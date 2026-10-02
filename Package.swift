// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Blinker",
    platforms: [
        .macOS(.v15),
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
        .executableTarget(
            name: "BlinkerApp",
            dependencies: ["BlinkerCore"],
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
            dependencies: ["BlinkerApp", "BlinkerCore"],
            path: "Tests/BlinkerAppTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
