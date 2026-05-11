// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import Linter_Primitives
internal import SwiftSyntax

/// Wave 2b finalization (2026-05-10) — extensions on `Tagged` MUST NOT
/// expose public initializers.
///
/// Citation: `[PATTERN-019]` (implementation skill, patterns.md).
///
/// `Tagged<Tag, RawValue>` carries bounded invariants in its `Tag` —
/// brand-newtypes encode "this `String` is a `User.ID`, not a free
/// string". Extending `Tagged` with a `public init` that takes a
/// `RawValue` (or anything else) bypasses the type's bounded
/// construction surface: callers who go through the extension init
/// have not crossed any validation gate the brand owner controls.
///
/// AST shape: `ExtensionDeclSyntax` whose extended type starts with
/// `Tagged` (covers `Tagged<...>`, `Tagged where ...`, etc.) AND whose
/// member block contains an `InitializerDeclSyntax` with a `public`
/// modifier. Each public init in the extension is flagged.
extension Lint.Rule {
    public static let `tagged extension public init` = Lint.Rule(
        id: "tagged extension public init",
        defaultSeverity: .warning,
        findings: { source, severity in
            let visitor = RawValueTaggedExtensionPublicInitVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

@usableFromInline
internal let taggedExtensionPublicInitMessage: Swift.String =
    "[tagged extension public init] [PATTERN-019]: extensions on `Tagged` "
    + "MUST NOT provide `public init` — bypasses the brand's bounded invariants. "
    + "Callers reaching through an extension init never cross the validation gate "
    + "the tag owner controls. Drop the init, or move construction behind a "
    + "validating factory at the brand owner's layer."

/// Stdlib / institute protocols whose `public init(...)` requirement
/// is the protocol contract — the conformer MUST provide the init or
/// the conformance is impossible. The validation gate IS the protocol
/// requirement (each init's body still delegates to the underlying
/// type's literal-protocol witness for actual validation). Exempt
/// these inits from the brand-bypass rule when declared inside an
/// extension conforming to the named protocol.
///
/// Citation discipline: each entry names the specific protocol whose
/// init contract justifies the exemption. Adding an entry without a
/// citation is indefensible at review time.
@usableFromInline
internal let taggedExtensionPublicInitProtocolWitnessCitations: [Swift.String: Swift.String] = [
    "ExpressibleByIntegerLiteral":                 "Swift.ExpressibleByIntegerLiteral — init(integerLiteral:) protocol witness",
    "ExpressibleByFloatLiteral":                   "Swift.ExpressibleByFloatLiteral — init(floatLiteral:) protocol witness",
    "ExpressibleByUnicodeScalarLiteral":           "Swift.ExpressibleByUnicodeScalarLiteral — init(unicodeScalarLiteral:) protocol witness",
    "ExpressibleByExtendedGraphemeClusterLiteral": "Swift.ExpressibleByExtendedGraphemeClusterLiteral — init(extendedGraphemeClusterLiteral:) protocol witness",
    "ExpressibleByStringLiteral":                  "Swift.ExpressibleByStringLiteral — init(stringLiteral:) protocol witness",
    "ExpressibleByBooleanLiteral":                 "Swift.ExpressibleByBooleanLiteral — init(booleanLiteral:) protocol witness",
    "ExpressibleByStringInterpolation":            "Swift.ExpressibleByStringInterpolation — init(stringInterpolation:) protocol witness",
    "ExpressibleByArrayLiteral":                   "Swift.ExpressibleByArrayLiteral — init(arrayLiteral:) protocol witness",
    "ExpressibleByDictionaryLiteral":              "Swift.ExpressibleByDictionaryLiteral — init(dictionaryLiteral:) protocol witness",
    "ExpressibleByNilLiteral":                     "Swift.ExpressibleByNilLiteral — init(nilLiteral:) protocol witness",
    "LosslessStringConvertible":                   "Swift.LosslessStringConvertible — init?(_:) protocol witness",
    "RawRepresentable":                            "Swift.RawRepresentable — init?(rawValue:) protocol witness",
    "Decodable":                                   "Swift.Decodable — init(from:) protocol witness",
    "Codable":                                     "Swift.Codable — Decodable.init(from:) protocol witness",
    "Protocol":                                    "Institute hoisted-protocol witness ([API-IMPL-009] pattern; e.g., Carrier.Protocol)",
    "`Protocol`":                                  "Institute hoisted-protocol witness ([API-IMPL-009] pattern; e.g., Carrier.`Protocol`)",
]

internal final class RawValueTaggedExtensionPublicInitVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    init(source: Source.File, severity: Diagnostic.Severity, converter: SourceLocationConverter) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    private func extendsTagged(_ extendedType: TypeSyntax) -> Bool {
        // Match `Tagged`, `Tagged<...>`, `Tagged_Primitives.Tagged`, or any
        // qualified path ending in `.Tagged`. Use trimmed description as
        // the canonical form; check first identifier or last segment.
        let text = extendedType.trimmedDescription
        if text == "Tagged" || text.hasPrefix("Tagged<") || text.hasPrefix("Tagged ") {
            return true
        }
        // Qualified: `Tagging.Tagged`, `Foo.Bar.Tagged<...>`.
        if let lastSegment = text.split(separator: ".").last {
            let segment = String(lastSegment)
            if segment == "Tagged" || segment.hasPrefix("Tagged<") || segment.hasPrefix("Tagged ") {
                return true
            }
        }
        return false
    }

    private func hasPublicModifier(_ modifiers: DeclModifierListSyntax) -> Bool {
        for modifier in modifiers {
            if modifier.name.tokenKind == .keyword(.public) || modifier.name.tokenKind == .keyword(.open) {
                return true
            }
        }
        return false
    }

    /// Returns the leaf protocol names from the extension's inheritance
    /// clause. Used to gate the protocol-witness exemption.
    private func inheritanceLeafNames(_ clause: InheritanceClauseSyntax?) -> [Swift.String] {
        guard let clause else { return [] }
        var names: [Swift.String] = []
        for inherited in clause.inheritedTypes {
            if let identifier = inherited.type.as(IdentifierTypeSyntax.self) {
                names.append(identifier.name.text)
            } else if let member = inherited.type.as(MemberTypeSyntax.self) {
                names.append(member.name.text)
            }
        }
        return names
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard extendsTagged(node.extendedType) else {
            return .visitChildren
        }
        // Stdlib-protocol-witness exemption: if the extension declares
        // conformance to a protocol whose init contract requires the
        // public init, the protocol IS the validation gate. Skip the
        // entire extension's init checks in that case.
        let conformingProtocols = inheritanceLeafNames(node.inheritanceClause)
        let isProtocolWitnessExtension = conformingProtocols.contains { proto in
            taggedExtensionPublicInitProtocolWitnessCitations[proto] != nil
        }
        if isProtocolWitnessExtension {
            return .visitChildren
        }
        for member in node.memberBlock.members {
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else {
                continue
            }
            guard hasPublicModifier(initDecl.modifiers) else {
                continue
            }
            let location = converter.location(for: initDecl.initKeyword.positionAfterSkippingLeadingTrivia)
            matches.append(Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "tagged extension public init",
                message: taggedExtensionPublicInitMessage
            ))
        }
        return .visitChildren
    }
}
