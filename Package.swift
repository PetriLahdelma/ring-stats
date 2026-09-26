// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RingStats",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RingStats", targets: ["RingStats"])],
    targets: [
        .executableTarget(
            name: "RingStats",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "RingStatsTests", dependencies: ["RingStats"]),
    ]
)
