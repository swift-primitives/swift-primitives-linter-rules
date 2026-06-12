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

/// [API-IMPL-022] — public STORED value types in the storage tower are `@frozen`.
///
/// Fires on a `public struct` that (1) roots in a tower namespace (the
/// data-plane families and substrates — `Storage`, `Store`, `Buffer`, `Shared`,
/// `Array`, `Fixed`, `Column`, `Queue`, `Deque`, `SlotMap`, `Stack`, `Heap`,
/// `Tree`, `Graph`, `Hash`, `Set`, `Dictionary`), (2) declares at least one
/// stored property (data-plane, not a namespace shell), (3) is not `@frozen`,
/// and (4) is not in the ruled exemption class — views/iterators/snapshots
/// (`~Escapable` types, and the principal-curated names `Checkpoint`/`Scalar`/
/// `Segments`/`Walk` plus `Iterator`/`View`-named types), which freeze only on
/// demonstrated cross-module partial-consumption need.
///
/// The namespace allowlist is the rule's tower scope: the bundle reaches every
/// primitives-tier consumer, and non-tower packages declare no types under
/// these roots, so the rule self-scopes (validated against the non-tower
/// ladder at promotion — 0 findings).
extension Lint.Rule {
    public static let `frozen tower type` = Lint.Rule(
        id: "frozen tower type",
        default: .warning,
        findings: { source, severity in
            let visitor = FrozenTowerTypeVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

fileprivate let frozenTowerTypeMessage: Swift.String =
    "[frozen tower type] [API-IMPL-022]: public stored value types in the storage tower "
    + "are @frozen (layout-locked from birth) so cross-module consuming decomposition "
    + "(take()-style unwraps, consuming makeIterator()) stays legal without "
    + "defining-module workarounds. Add @frozen to the declaration. Views/iterators/"
    + "snapshots are exempt until cross-module partial consumption is demonstrated "
    + "(the ruled exemption); if this type is one, name it per the exemption class or "
    + "exclude per the rule-exemptions shapes."

internal final class FrozenTowerTypeVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    /// The tower's data-plane namespace roots ([API-IMPL-022]'s scope).
    private static let towerRoots: Swift.Set<Swift.String> = [
        "Storage", "Store", "Buffer", "Shared", "Array", "Fixed", "Column",
        "Queue", "Deque", "SlotMap", "Stack", "Heap", "Tree", "Graph", "Hash",
        "Set", "Dictionary",
    ]

    /// The ruled exemption class: views/iterators/snapshots stay unfrozen until
    /// cross-module partial consumption is demonstrated (principal-curated names).
    private static let exemptNames: Swift.Set<Swift.String> = [
        "Checkpoint", "Scalar", "Segments", "Walk", "Iterator", "View",
    ]

    init(
        source: Source.File,
        severity: Diagnostic.Severity,
        converter: SourceLocationConverter
    ) {
        self.source = source
        self.severity = severity
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublic(node.modifiers) else { return .visitChildren }
        guard !hasFrozen(node.attributes) else { return .visitChildren }
        let name = node.name.text
        guard !Self.exemptNames.contains(name),
              !name.hasSuffix("Iterator"),
              !name.hasSuffix("View")
        else { return .visitChildren }
        guard !suppressesEscapable(node.inheritanceClause) else { return .visitChildren }
        guard hasStoredProperty(node.memberBlock) else { return .visitChildren }
        guard let root = rootNamespace(of: node), Self.towerRoots.contains(root) else {
            return .visitChildren
        }

        let token = node.name
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        matches.append(Diagnostic.Record(
            location: Source.Location(
                fileID: source.fileID,
                filePath: source.filePath,
                line: location.line,
                column: location.column
            ),
            severity: severity,
            identifier: "frozen tower type",
            message: frozenTowerTypeMessage
        ))
        return .visitChildren
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Swift.Bool {
        modifiers.contains { $0.name.text == "public" }
    }

    private func hasFrozen(_ attributes: AttributeListSyntax) -> Swift.Bool {
        attributes.contains { element in
            guard case .attribute(let attribute) = element else { return false }
            return attribute.attributeName.trimmedDescription == "frozen"
        }
    }

    /// Whether the inheritance clause suppresses `Escapable` (`~Escapable`) —
    /// the mechanical marker of the view/span exemption class.
    private func suppressesEscapable(_ clause: InheritanceClauseSyntax?) -> Swift.Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            guard let suppressed = inherited.type.as(SuppressedTypeSyntax.self) else { return false }
            return suppressed.type.trimmedDescription == "Escapable"
        }
    }

    /// Whether the member block declares at least one stored property
    /// (an accessor-less, non-static `let`/`var` binding) — the data-plane marker.
    private func hasStoredProperty(_ memberBlock: MemberBlockSyntax) -> Swift.Bool {
        memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            guard !variable.modifiers.contains(where: { $0.name.text == "static" }) else { return false }
            return variable.bindings.contains { $0.accessorBlock == nil }
        }
    }

    /// The OUTERMOST namespace component the struct lives under: the extended
    /// type's base identifier for extension-declared nests, the outermost
    /// nominal's name for lexically-nested decls, or the struct's own name at
    /// top level.
    private func rootNamespace(of node: StructDeclSyntax) -> Swift.String? {
        var outermost: Swift.String? = node.name.text
        var current: Syntax? = node.parent
        while let ancestor = current {
            if let ext = ancestor.as(ExtensionDeclSyntax.self) {
                outermost = baseIdentifier(of: ext.extendedType)
            } else if let nominal = ancestor.asProtocol(NamedDeclSyntax.self),
                      ancestor.is(StructDeclSyntax.self) || ancestor.is(EnumDeclSyntax.self)
                        || ancestor.is(ClassDeclSyntax.self) || ancestor.is(ActorDeclSyntax.self) {
                outermost = nominal.name.text
            }
            current = ancestor.parent
        }
        return outermost
    }

    /// The first identifier component of a (possibly member/generic) type:
    /// `Storage.Generational` → `Storage`; `Tree<E>.N` → `Tree`.
    private func baseIdentifier(of type: TypeSyntax) -> Swift.String? {
        if let member = type.as(MemberTypeSyntax.self) {
            return baseIdentifier(of: member.baseType)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        return nil
    }
}
