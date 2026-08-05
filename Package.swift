// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var swiftSettings: [SwiftSetting] = [
    // https://github.com/apple/swift-evolution/blob/main/proposals/0335-existential-any.md
    .enableUpcomingFeature("ExistentialAny"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0444-member-import-visibility.md
    .enableUpcomingFeature("MemberImportVisibility"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md
    .enableUpcomingFeature("InternalImportsByDefault"),

    // https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),

    .enableExperimentalFeature("AvailabilityMacro=hummingbird 2.0:macOS 14.0, iOS 17.0, tvOS 17.0, visionOS 1.0, Android 28"),
]

let package = Package(
    name: "hummingbird-dashboard",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18), .tvOS(.v18), .visionOS(.v1)],
    products: [
        .library(name: "HummingbirdDashboard", targets: ["HummingbirdDashboard"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.26.0", traits: []),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.11.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.12.0", traits: []),
        .package(url: "https://github.com/hummingbird-project/swift-openapi-hummingbird.git", from: "2.0.1"),
    ],
    targets: [
        .target(
            name: "HummingbirdDashboard",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIHummingbird", package: "swift-openapi-hummingbird"),
            ],
            swiftSettings: swiftSettings,
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "HummingbirdDashboardTests",
            dependencies: [
                "HummingbirdDashboard",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
