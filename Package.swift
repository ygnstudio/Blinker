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
            path: "Sources/BlinkerCore"
        ),
        .executableTarget(
            name: "BlinkerApp",
            dependencies: ["BlinkerCore"],
            path: "Sources/BlinkerApp"
        ),
        .testTarget(
            name: "BlinkerCoreTests",
            dependencies: ["BlinkerCore"],
            path: "Tests/BlinkerCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
