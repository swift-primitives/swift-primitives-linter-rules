// swift-tools-version: 6.3.1

// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-primitives-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-primitives-linter-rules",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        // A5 move (2026-07-07) — the RawValue and Cardinal brand-consumer
        // packs relocated to swift-institute-linter-rules so they enforce at
        // L2/L3 too. Only the tower-author rules (genuinely L1-only) remain.
        // Round M ζ pilot (2026-06-12) — tower-scoped structural rules.
        .library(
            name: "Primitives Linter Rule Tower",
            targets: ["Primitives Linter Rule Tower"]
        ),

        // Aggregate bundle — publishes `Lint.Rule.Bundle.primitives`
        // (= institute + primitives-tier rules). Primitives-tier
        // consumers depend on this product alone.
        .library(
            name: "Linter Primitives Rules",
            targets: ["Linter Primitives Rules"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-primitives/swift-linter-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-institute-linter-rules.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-linter-rules.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0"),
    ],
    targets: [
        .target(
            name: "Primitives Linter Rule Tower",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Linter Primitives Rules",
            dependencies: [
                .product(name: "Linter Primitives", package: "swift-linter-primitives"),
                "Primitives Linter Rule Tower",
                .product(name: "Linter Institute Rules", package: "swift-institute-linter-rules"),
            ]
        ),
        .testTarget(
            name: "Primitives Linter Rule Tower Tests",
            dependencies: [
                "Primitives Linter Rule Tower",
                .product(name: "Linter Rules Test Support", package: "swift-linter-rules"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem
}
