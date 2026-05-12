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

/// R3 — chained `.rawValue.X` member access.
///
/// Subsumes the regex pair `chained_rawvalue_access_anti_pattern` +
/// `chained_rawvalue_access_paren_evasion`. The AST predicate is a
/// `MemberAccessExprSyntax` whose base, after peeling parenthesized
/// wrappers, is itself a `MemberAccessExprSyntax` whose member name is
/// `rawValue`.
///
/// Paren-wrap evasion `(x.rawValue).foo()` collapses into the same
/// predicate: `TupleExprSyntax` wrapping a single expression is
/// semantically transparent, so peeling it yields the same
/// `MemberAccessExprSyntax(base: x, name: rawValue)` shape.
///
/// ## Package-scoped admission (numerics rule-recognizer, 2026-05-12)
///
/// Mirrors the admission semantics on
/// `Lint.Rule.\`raw value access\``. When the linted file's owning
/// SwiftPM package declares brand-newtype names via `.swift-linter.json`
/// (`brandTypes`), the rule admits chained-`.rawValue` access for:
///   1. **Direct case**: `Cardinal.rawValue.addingReportingOverflow(...)`
///      where `Cardinal` is in the declared `brandTypes`.
///   2. **Package-scope fallback**: `lhs.rawValue.addingReportingOverflow(...)`
///      inside a file whose owning package declares any brand. This
///      is the "wrapper IS what this site implements" admission the
///      rule prose names but cannot identify from AST alone.
///
/// See
/// `swift-linter-rules/Research/numerics-rule-recognizer-2026-05-12.md`.
///
/// References:
/// - `swift-institute/Research/cardinal-ordinal-vector-enforcement-design.md`
///   §"R3. `.rawValue.` chains"
/// - `swift-institute/Research/swiftsyntax-based-custom-linter-investigation.md`
///   §"Q2 — Evasion-class closure matrix" (paren-wrap row)
extension Lint.Rule {
    public static let `chained rawvalue access` = Lint.Rule(
        id: "chained rawvalue access",
        defaultSeverity: .warning,
        findings: { source, severity in
            let visitor = RawValueChainVisitor(
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
internal let chainedRawvalueAccessMessage: Swift.String =
    "[chained rawvalue access] [CONV-016]: chaining `.rawValue.method()` (or "
    + "paren-wrapped `(x.rawValue).method()`, which is semantically identical) escapes "
    + "the typed system. Prefer `.retag()` (Tier 1) / `.map()` (Tier 2) / `Type.min(a, b)` "
    + "/ a typed accessor exposed by the wrapper, per [INFRA-103]. If the wrapper IS "
    + "what this site implements (typed-system bottom-out), escalate to supervisor and "
    + "apply `// swiftlint:disable:next chained_rawvalue_access  // reason: <citation>`."

internal final class RawValueChainVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    /// See package-scoped admission notes on
    /// ``Lint/Rule/chained rawvalue access``.
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

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base else { return .visitChildren }
        let unwrapped = Self.peelParens(base)
        guard let baseAccess = unwrapped.as(MemberAccessExprSyntax.self),
              baseAccess.declName.baseName.text == "rawValue"
        else { return .visitChildren }
        if rawValueChainIsAdmitted(rawValueAccess: baseAccess, brandTypes: brandTypes) {
            return .visitChildren
        }
        let token = node.declName.baseName
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        matches.append(Diagnostic.Record(
            location: Source.Location(
                fileID: source.fileID,
                filePath: source.filePath,
                line: location.line,
                column: location.column
            ),
            severity: severity,
            identifier: "chained rawvalue access",
            message: chainedRawvalueAccessMessage
        ))
        return .visitChildren
    }

    static func peelParens(_ expr: ExprSyntax) -> ExprSyntax {
        var current = expr
        while let tuple = current.as(TupleExprSyntax.self),
              tuple.elements.count == 1,
              let only = tuple.elements.first?.expression,
              tuple.elements.first?.label == nil {
            current = only
        }
        return current
    }
}

/// Returns `true` when the underlying `.rawValue` access at
/// `rawValueAccess` is admitted by the file's owning-package
/// brand-types set. Mirrors `structureRawValueAccessIsAdmitted` —
/// type-name match when the base is `Brand` or `A.B.Brand`;
/// package-scope fallback when the base is a variable / chain and
/// `brandTypes` is non-empty. Empty `brandTypes` preserves
/// strict-superset.
internal func rawValueChainIsAdmitted(
    rawValueAccess: MemberAccessExprSyntax,
    brandTypes: Swift.Set<Lint.Brand>
) -> Swift.Bool {
    guard !brandTypes.isEmpty else { return false }
    if let baseName = rawValueChainExtractTypeName(base: rawValueAccess.base) {
        return brandTypes.contains(Lint.Brand(baseName))
    }
    return true
}

/// Reassembles a dotted type-name from the leftmost portion of a
/// `MemberAccessExprSyntax` chain when the bottom-most base is an
/// UPPERCASE-leading `DeclReferenceExprSyntax`. See the same shape
/// in `Lint.Rule.Structure.RawValueAccess`. Returns `nil` for
/// lowercase-leading identifiers (variables, functions) — those
/// cases are handled by the package-scope fallback.
internal func rawValueChainExtractTypeName(base: ExprSyntax?) -> Swift.String? {
    guard let base else { return nil }
    if let identifier = base.as(DeclReferenceExprSyntax.self) {
        let text = identifier.baseName.text
        guard rawValueChainLooksLikeType(text) else { return nil }
        return text
    }
    if let memberAccess = base.as(MemberAccessExprSyntax.self) {
        guard let lower = rawValueChainExtractTypeName(base: memberAccess.base) else {
            return nil
        }
        return lower + "." + memberAccess.declName.baseName.text
    }
    return nil
}

internal func rawValueChainLooksLikeType(_ text: Swift.String) -> Swift.Bool {
    guard let first = text.first else { return false }
    return first.isUppercase
}
