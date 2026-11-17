// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-interposed-clock",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Interposed Clock", targets: ["Interposed Clock"]),
        .library(name: "Interposed Clock Interposition", type: .dynamic, targets: ["Interposed Clock Interposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-clock.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-tagged.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-time.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-test-apple.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Interposed Clock",
            dependencies: [
                .product(name: "Clock Concurrency", package: "swift-clock"),
                .product(name: "Tagged", package: "swift-tagged"),
                .product(name: "Time", package: "swift-time"),
            ]
        ),
        .target(name: "Interposed Clock Interposition"),
        .executableTarget(
            name: "Interposed Clock Fixture",
            dependencies: [
                .target(name: "Interposed Clock")
            ],
            path: "Tests/Interposed Clock Fixture"
        ),
        .testTarget(
            name: "Interposed Clock Tests",
            dependencies: [
                .target(name: "Interposed Clock Fixture"),
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
