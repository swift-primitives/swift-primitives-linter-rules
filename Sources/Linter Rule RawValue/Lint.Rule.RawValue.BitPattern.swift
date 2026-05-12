// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Linter_Primitives
internal import SwiftSyntax

/// R4 — `X(bitPattern: …rawValue)` integration-overload anti-pattern.
///
/// Subsumes the regex `bitpattern_rawvalue_chain_anti_pattern`. The AST
/// predicate is a `FunctionCallExprSyntax` carrying a `bitPattern:`
/// labeled argument whose expression chains through a `.rawValue`
/// member access (anywhere inside the argument expression).
///
/// Typename-swap evasion (`Int(bitPattern:)` vs `UInt(bitPattern:)` vs
/// `self.init(bitPattern:)` vs `Int.init(bitPattern:)` vs
/// `Int8(bitPattern:)` …) is closed natively: every form parses to a
/// `FunctionCallExprSyntax` carrying the same labeled argument. The
/// predicate doesn't constrain the callee, so all spellings hit.
///
/// ## Package-scoped admission (numerics rule-recognizer, 2026-05-12)
///
/// Mirrors the admission semantics on
/// `Lint.Rule.\`raw value access\``. The
/// `Int.init(bitPattern: Brand)` integration-overload definition
/// lives in exactly one file per brand per package (per [IMPL-010]).
/// When the file's owning package declares any `brandTypes`, the rule
/// admits the chain inside that file — the rule's "this site IS the
/// integration overload definition" admission, made structural.
///
/// See
/// `swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`.
///
/// References:
/// - `swift-institute/Research/cardinal-ordinal-vector-enforcement-design.md`
///   §"R4. `Int(bitPattern: <something>.rawValue ...)`"
/// - `swift-institute/Research/swiftsyntax-based-custom-linter-investigation.md`
///   §"Q2 — Evasion-class closure matrix" (typename-swap row)
extension Lint.Rule {
    public static let `bitpattern rawvalue chain` = Lint.Rule(
        id: "bitpattern rawvalue chain",
        defaultSeverity: .warning,
        findings: { source, severity in
            let visitor = RawValueBitPatternVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter,
                brandTypes: source.brandTypes
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let bitpatternRawvalueChainMessage: Swift.String =
    "[bitpattern rawvalue chain] [CONV-016]: `init(bitPattern:)` whose argument chains "
    + "through `.rawValue` — including `Int(...)`, `UInt(...)`, `Int.init(...)`, "
    + "`self.init(...)`, and other syntactic equivalents — bypasses the canonical "
    + "preference hierarchy. Prefer `.retag()` / `.map()` (Tier 1/2) before resorting "
    + "to the [INFRA-002] integration overload — and when you do use the overload, "
    + "pass the typed value directly: `Int(bitPattern: foo)` not "
    + "`Int(bitPattern: foo.rawValue)`. If this site IS the [INFRA-002] integration "
    + "overload definition itself, escalate to supervisor and apply "
    + "`// swiftlint:disable:next bitpattern_rawvalue_chain  // reason: <citation>`."

internal final class RawValueBitPatternVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    /// See package-scoped admission notes on
    /// ``Lint/Rule/bitpattern rawvalue chain``.
    let brandTypes: Swift.Set<Lint.Brand>
    var matches: [Diagnostic.Record] = []

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter,
        brandTypes: Swift.Set<Lint.Brand> = []
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        self.brandTypes = brandTypes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        for arg in node.arguments {
            guard let label = arg.label, label.text == "bitPattern" else { continue }
            guard let rawValueAccess = Self.findRawValueAccess(arg.expression) else { continue }
            if rawValueBitPatternIsAdmitted(rawValueAccess: rawValueAccess, brandTypes: brandTypes) {
                continue
            }
            let location = converter.location(for: label.positionAfterSkippingLeadingTrivia)
            matches.append(Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "bitpattern rawvalue chain",
                message: bitpatternRawvalueChainMessage
            ))
        }
        return .visitChildren
    }

    /// Returns the first `.rawValue` member-access inside `expr`, if
    /// any. Used by the package-scope admission check so the
    /// admission can inspect the access's base for a type-name.
    static func findRawValueAccess(_ expr: ExprSyntax) -> MemberAccessExprSyntax? {
        let finder = RawValueBitPatternFinder(viewMode: .sourceAccurate)
        finder.walk(expr)
        return finder.match
    }
}

internal final class RawValueBitPatternFinder: SyntaxVisitor {
    var match: MemberAccessExprSyntax? = nil

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if node.declName.baseName.text == "rawValue", match == nil {
            match = node
        }
        return .visitChildren
    }
}

/// Admission gate for the bit-pattern integration overload. Mirrors
/// `rawValueChainIsAdmitted`: name-match when the `.rawValue` base is
/// a type-name in `brandTypes`; package-scope fallback when the base
/// is a variable / chain and `brandTypes` is non-empty.
internal func rawValueBitPatternIsAdmitted(
    rawValueAccess: MemberAccessExprSyntax,
    brandTypes: Swift.Set<Lint.Brand>
) -> Swift.Bool {
    guard !brandTypes.isEmpty else { return false }
    if let baseName = rawValueChainExtractTypeName(base: rawValueAccess.base) {
        return brandTypes.contains(Lint.Brand(baseName))
    }
    return true
}
