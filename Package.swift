// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-clock-interposed",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Clock Interposed", targets: ["Clock Interposed"]),
        .library(name: "Clock Interposed Interposition", type: .dynamic, targets: ["Clock Interposed Interposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-clock.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-lock.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-rate.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-tagged.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-time.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-test-apple.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Clock Interposed",
            dependencies: [
                .product(name: "Clock Concurrency", package: "swift-clock"),
                .product(name: "Lock", package: "swift-lock"),
                .product(name: "Rate", package: "swift-rate"),
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "Time", package: "swift-time"),
            ]
        ),
        .target(name: "Clock Interposed Interposition"),
        .executableTarget(
            name: "Clock Interposed Fixture",
            dependencies: [
                .target(name: "Clock Interposed")
            ],
            path: "Tests/Clock Interposed Fixture"
        ),
        .testTarget(
            name: "Clock Interposed Tests",
            dependencies: [
                .target(name: "Clock Interposed Fixture"),
                .product(name: "Test Apple", package: "swift-test-apple"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableExperimentalFeature("Lifetimes"),
            .treatAllWarnings(as: .error),
        ]
}
