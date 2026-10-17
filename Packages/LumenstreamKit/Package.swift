// swift-tools-version: 6.4

import PackageDescription

/// Settings shared by every target: Swift 6 language mode plus the
/// "approachable concurrency" feature set the app target also uses.
let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LumenstreamKit",
    platforms: [
        .iOS(.v27),
        .macOS(.v27),
    ],
    products: [
        .library(name: "IBKit", targets: ["IBKit"]),
        .library(name: "LumenstreamData", targets: ["LumenstreamData"]),
        .library(name: "LumenstreamUI", targets: ["LumenstreamUI"]),
    ],
    targets: [
        // Wire protocol + socket transport for the TWS API. No UI, no main actor:
        // everything here is either a Sendable value type or an actor.
        .target(
            name: "IBKit",
            swiftSettings: concurrencySettings
        ),
        // App model, SwiftData schema and domain types. Main-actor by default,
        // like the app target, so @Observable state is UI-ready.
        .target(
            name: "LumenstreamData",
            dependencies: ["IBKit"],
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        // Reusable Liquid Glass components and design tokens.
        .target(
            name: "LumenstreamUI",
            dependencies: ["LumenstreamData"],
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "IBKitTests",
            dependencies: ["IBKit"],
            swiftSettings: concurrencySettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
