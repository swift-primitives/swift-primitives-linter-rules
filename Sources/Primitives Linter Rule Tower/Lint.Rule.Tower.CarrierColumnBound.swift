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

/// [DS-026](a) — a tower carrier's column parameter `S` carries no
/// capability-protocol bound ON THE TYPE (direct bound only; the per-file slice).
///
/// Fires on a `public struct` that (1) is a tower CARRIER — a hoisted `__X`
/// carrier, or a struct rooted in an ADT-family namespace (`Array`, `Queue`,
/// `Set`, `Dictionary`, `Stack`, `Heap`, `Tree`, `SlotMap`, `Fixed`, `Slab`,
/// `List`, `Deque`, `Hash`, `Bitset`) — and (2) declares a generic parameter
/// named `S` (the storage/column axis) whose bound, inline (`<S: …>`) or in the
/// type's own `where` clause, references a capability protocol
/// (`Store.\`Protocol\``, `Buffer.\`Protocol\``, `Storage.\`Protocol\``).
///
/// This is [DS-026] predicate part (a) — the load-bearing axis that separates
/// `legacy` (bound-on-type) from the reshaped states. Per [DS-025] the carrier
/// is ALWAYS `__X<S: ~Copyable>`; capability bounds belong on the capability
/// EXTENSIONS (`extension __X where S: Store.\`Protocol\` & Buffer.\`Protocol\``),
/// never on the type — that is composition, not refinement.
///
/// MECHANIZATION SCOPE (the honest boundary): only the DIRECT bound on the
/// carrier's own declaration is decidable per-file / per-AST. The INHERITED
/// bound — a sibling nested in `extension Parent where S: Capability { … }`,
/// whose bound lives in a DIFFERENT package (`Queue.DoubleEnded`,
/// `Dictionary.Ordered`) — needs cross-package resolution an AST rule cannot
/// reach; it stays enforced by `Scripts/adt-decoupling-classify.py`. Parts
/// (b)/(c)/(d)/(e) of [DS-026] also remain script/text-enforced (see the
/// PROMOTE record). Capability bounds on EXTENSIONS are the LAWFUL [DS-025]
/// form and are never visited (this rule inspects primary type decls only).
extension Lint.Rule {
    /// Flags a tower carrier whose column parameter `S` carries a capability-protocol bound on the type ([DS-026](a)).
    ///
    /// The carrier must be `__X<S: ~Copyable>`; the capability bound belongs on
    /// the capability extensions, never on the type. Inherited (cross-package)
    /// bounds are out of AST scope — the classifier script covers them.
    public static let `carrier column bound` = Lint.Rule(
        id: "carrier column bound",
        default: .warning,
        findings: { source, severity in
            let visitor = CarrierColumnBoundVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.matches
        }
    )
}

private let carrierColumnBoundMessage: Swift.String =
    "[carrier column bound] [DS-026]: this tower carrier binds its column "
    + "parameter S to a capability protocol (Store/Buffer/Storage.Protocol) ON "
    + "THE TYPE. Per [DS-025] the carrier is always __X<S: ~Copyable>; capability "
    + "bounds belong on the capability EXTENSIONS (extension __X where S: "
    + "Store.`Protocol` & Buffer.`Protocol`), never on the carrier — that is "
    + "composition, not refinement. Move the bound off the type declaration onto "
    + "the conditional extensions that need the seam. (Inherited cross-package "
    + "bounds and predicate parts (b)-(e) stay enforced by "
    + "Scripts/adt-decoupling-classify.py.)"

internal final class CarrierColumnBoundVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter
    var matches: [Diagnostic.Record] = []

    /// The storage/column axis parameter name. The whole tower uses `S` for the
    /// column; `Element`, `Key`, `n`, `N` are NOT storage axes.
    private static let storageAxis: Swift.String = "S"

    /// The ADT-family namespace roots ([DS-026]'s CARRIER scope). Deliberately
    /// EXCLUDES the storage substrates (`Storage`, `Store`, `Buffer`, `Shared`,
    /// `Column`): a substrate legitimately carries capability bounds; only the
    /// ADT CARRIERS are subject to the bound-off-the-type predicate. Hoisted
    /// carriers (`__X`) are matched by the `__` prefix, independent of this set.
    private static let carrierFamilyRoots: Swift.Set<Swift.String> = [
        "Array", "Fixed", "Queue", "Deque", "SlotMap", "Stack", "Heap",
        "Tree", "Hash", "Set", "Dictionary", "Slab", "List", "Bitset",
    ]

    /// The capability-protocol base leaves whose `.Protocol` member is a storage
    /// seam bound (the [DS-026] STORAGE_PROTOCOL_TOKENS).
    private static let capabilityBases: Swift.Set<Swift.String> = [
        "Store", "Buffer", "Storage",
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
        guard isTowerCarrier(node) else { return .visitChildren }
        guard columnHasCapabilityBound(node) else { return .visitChildren }

        let token = node.name
        let location = converter.location(for: token.positionAfterSkippingLeadingTrivia)
        matches.append(
            Diagnostic.Record(
                location: Source.Location(
                    fileID: source.fileID,
                    filePath: source.filePath,
                    line: location.line,
                    column: location.column
                ),
                severity: severity,
                identifier: "carrier column bound",
                message: carrierColumnBoundMessage
            )
        )
        return .visitChildren
    }

    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Swift.Bool {
        modifiers.contains { $0.name.text == "public" }
    }

    /// Whether the struct is a tower carrier: a hoisted `__X` carrier, or a
    /// struct whose OUTERMOST namespace root is an ADT family.
    private func isTowerCarrier(_ node: StructDeclSyntax) -> Swift.Bool {
        if node.name.text.hasPrefix("__") { return true }
        guard let root = rootNamespace(of: node) else { return false }
        return Self.carrierFamilyRoots.contains(root)
    }

    /// Whether the carrier's column parameter `S` carries a capability-protocol
    /// bound — inline (`<S: Store.\`Protocol\` & …>`) or in the type's own
    /// `where` clause (`where S: Store.\`Protocol\``).
    private func columnHasCapabilityBound(_ node: StructDeclSyntax) -> Swift.Bool {
        if let parameters = node.genericParameterClause?.parameters {
            for parameter in parameters
            where stripBackticks(parameter.name.text) == Self.storageAxis {
                if let inherited = parameter.inheritedType,
                    typeReferencesCapabilityProtocol(inherited)
                {
                    return true
                }
            }
        }
        if let requirements = node.genericWhereClause?.requirements {
            for requirement in requirements {
                guard case .conformanceRequirement(let conformance) = requirement.requirement
                else { continue }
                guard leafName(of: conformance.leftType) == Self.storageAxis else { continue }
                if typeReferencesCapabilityProtocol(conformance.rightType) {
                    return true
                }
            }
        }
        return false
    }

    /// Whether a type (single member type or a `&`-composition) references any
    /// capability protocol `Base.\`Protocol\`` with `Base` in `capabilityBases`.
    private func typeReferencesCapabilityProtocol(_ type: TypeSyntax) -> Swift.Bool {
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.contains {
                typeReferencesCapabilityProtocol($0.type)
            }
        }
        if let member = type.as(MemberTypeSyntax.self) {
            let memberLeaf = stripBackticks(member.name.text)
            if memberLeaf == "Protocol",
                let base = baseIdentifier(of: member.baseType),
                Self.capabilityBases.contains(base)
            {
                return true
            }
            return false
        }
        return false
    }

    /// The OUTERMOST namespace component the struct lives under: the extended
    /// type's base identifier for extension-declared nests, the outermost
    /// nominal's name for lexically-nested decls, or the struct's own name at
    /// top level. (Mirrors `FrozenTowerTypeVisitor.rootNamespace`.)
    private func rootNamespace(of node: StructDeclSyntax) -> Swift.String? {
        var outermost: Swift.String? = node.name.text
        var current: Syntax? = node.parent
        while let ancestor = current {
            if let ext = ancestor.as(ExtensionDeclSyntax.self) {
                outermost = baseIdentifier(of: ext.extendedType)
            } else if let nominal = ancestor.asProtocol(NamedDeclSyntax.self),
                ancestor.is(StructDeclSyntax.self) || ancestor.is(EnumDeclSyntax.self)
                    || ancestor.is(ClassDeclSyntax.self) || ancestor.is(ActorDeclSyntax.self)
            {
                outermost = nominal.name.text
            }
            current = ancestor.parent
        }
        return outermost.map(stripBackticks)
    }

    /// The first identifier component of a (possibly member/generic) type:
    /// `Storage.Generational` → `Storage`; `Tree<E>.N` → `Tree`.
    private func baseIdentifier(of type: TypeSyntax) -> Swift.String? {
        if let member = type.as(MemberTypeSyntax.self) {
            return baseIdentifier(of: member.baseType)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return stripBackticks(identifier.name.text)
        }
        return nil
    }

    /// The leaf identifier of a simple type reference (`S` → `S`), or "" if not
    /// a bare identifier.
    private func leafName(of type: TypeSyntax) -> Swift.String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return stripBackticks(identifier.name.text)
        }
        return ""
    }

    private func stripBackticks(_ text: Swift.String) -> Swift.String {
        var result = text
        if result.hasPrefix("`") { result.removeFirst() }
        if result.hasSuffix("`") { result.removeLast() }
        return result
    }
}
