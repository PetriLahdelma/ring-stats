// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RingStats",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "RingStats", targets: ["RingStats"])],
    targets: [
        // Provider-neutral models, freshness, merging, diagnostics, Keychain
        // storage, and the loopback OAuth callback.
        .target(name: "RingStatsCore"),
        // One target per provider, compiled in.
        .target(name: "RingStatsOura", dependencies: ["RingStatsCore"]),
        .executableTarget(
            name: "RingStats",
            dependencies: ["RingStatsCore", "RingStatsOura"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RingStatsTests",
            dependencies: ["RingStats", "RingStatsCore", "RingStatsOura"]
        ),
    ]
)
