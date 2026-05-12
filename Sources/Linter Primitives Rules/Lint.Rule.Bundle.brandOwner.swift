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

/// Brand-owner primitives-tier rule bundle.
///
/// Equals ``Lint/Rule/Bundle/primitives`` minus the four consumer-side
/// rules that fire at consumer call sites but are reserved for the
/// brand-newtype's own implementation. Brand-newtype-owning primitive
/// packages — `swift-ordinal-primitives`, `swift-cardinal-primitives`,
/// `swift-affine-primitives` — load this bundle in their `Lint.swift`
/// instead of the full primitives bundle:
///
/// ```swift
/// // swift-linter-tools-version: 0.1
/// import Linter
/// import Linter_Primitives_Rules
///
/// Lint.run(
///     dependencies: [.package(path: ".", products: ["..."])]
/// ) {
///     Lint.Rule.Bundle.brandOwner
/// }
/// ```
///
/// The excluded rules are:
///   - ``Lint/Rule/raw value access`` ([PATTERN-017])
///   - ``Lint/Rule/chained rawvalue access`` ([CONV-016])
///   - ``Lint/Rule/int public parameter`` ([IMPL-010])
///   - ``Lint/Rule/pointer advanced by`` ([IMPL-011])
///
/// These four rules continue to fire on cross-package consumers — the
/// brand-owner package excludes them locally by loading this bundle
/// instead of ``Lint/Rule/Bundle/primitives``. Consumer-side firing is
/// preserved by NOT loading this bundle.
///
/// See
/// `swift-foundations/swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`
/// for the architectural rationale (Option 7: rule decomposition via
/// bundle composition, replacing the brand-feature with hierarchical
/// loading).
extension Lint.Rule.Bundle {
    public static let brandOwner: [Lint.Rule.Configuration] = {
        let excludedIDs: Swift.Set<Lint.Rule.ID> = [
            "raw value access",
            "chained rawvalue access",
            "int public parameter",
            "pointer advanced by",
        ]
        return Lint.Rule.Bundle.primitives.filter { !excludedIDs.contains($0.rule.id) }
    }()
}
