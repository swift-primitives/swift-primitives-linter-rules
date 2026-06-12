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

public import Linter_Primitives
public import Primitives_Linter_Rule_Cardinal
public import Primitives_Linter_Rule_RawValue
public import Primitives_Linter_Rule_Tower
public import Linter_Institute_Rules

/// Primitives-tier rule bundle.
///
/// Equals the institute-tier bundle (which transitively includes the
/// universal bundle) plus primitives-tier rules currently living in
/// `swift-primitives-linter-rules`. A primitives-tier consumer pulls
/// this single product and references the bundle by name:
///
/// ```swift
/// let configuration = Lint.Configuration {
///     Lint.Rule.Bundle.primitives
/// }
/// ```
///
/// The bundle is the single source of truth for "which rules apply at
/// the primitives tier". Adding a new rule to this package extends
/// this bundle; consumers pick up the new rule automatically on their
/// next dependency-resolution.
extension Lint.Rule.Bundle {
    public static let primitives: [Lint.Rule.Configuration] =
        Lint.Rule.Bundle.institute + [
            // Tower pack (Round M ζ pilot 2026-06-12)
            .enable(.`frozen tower type`),
            .enable(.`clone-less box`),
            // Cardinal pack (Wave 3 2026-05-15)
            .enable(.`zero or one literal`),
            .enable(.`count minus one`),
            // RawValue pack
            .enable(.`bitpattern rawvalue chain`),
            .enable(.`chained rawvalue access`),
            .enable(.`tagged extension public init`),
        ]
}
