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

/// [MEM-COPY-019] — box-replacing overloads split per the [MEM-COPY-017] pinned pair.
///
/// Fires on a function/initializer that (1) assigns a fresh `Shared` box to a
/// stored property (`self.x = Shared(...)` — box replacement or construction),
/// (2) carries a `~Copyable` suppression on its OWN generic parameters (the
/// element/payload bounds; extension-level column suppression `S: ~Copyable`
/// does not count), and (3) has NO same-name twin in the same file whose own
/// generic parameters carry no suppression (the implicitly-Copyable overload —
/// the lawful pair's other half, which resolves `Shared(_:)` to the
/// strategy-CARRYING init).
///
/// Under suppression, overload resolution statically selects the strategy-less
/// init: the replacement box works while unique and TRAPS on the first
/// post-fork mutation. The same-file twin requirement is the rule's recorded
/// heuristic (the pinned pair co-locates).
extension Lint.Rule {
    public static let `clone-less box` = Lint.Rule(
        id: "clone-less box",
        default: .warning,
        findings: { source, severity in
            let visitor = CloneLessBoxVisitor(
                source: source.file,
                severity: severity,
                converter: source.converter
            )
            visitor.walk(source.tree)
            return visitor.finish()
        }
    )
}

private let cloneLessBoxMessage: Swift.String =
    "[clone-less box] [MEM-COPY-019]: this overload replaces a Shared box under "
    + "~Copyable element bounds with no implicitly-Copyable same-name twin in this "
    + "file. Overload resolution statically selects the strategy-less Shared init, so "
    + "the replacement box carries NO clone strategy even for concretely Copyable "
    + "elements — it works while unique and traps on the first post-fork mutation. "
    + "Split per the [MEM-COPY-017] pinned pair: add the Copyable-element twin "
    + "(suppression-free parameters) that rebuilds through the strategy-carrying init."

internal final class CloneLessBoxVisitor: SyntaxVisitor {
    let source: Source.File
    let severity: Diagnostic.Severity
    let converter: SourceLocationConverter

    private struct Candidate {
        let name: Swift.String
        let suppressed: Swift.Bool
        let assignsBox: Swift.Bool
        let token: TokenSyntax
    }
    private var candidates: [Candidate] = []

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

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            name: node.name.text,
            token: node.name,
            genericParameters: node.genericParameterClause,
            whereClause: node.genericWhereClause,
            body: node.body
        )
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        record(
            name: "init",
            token: node.initKeyword,
            genericParameters: node.genericParameterClause,
            whereClause: node.genericWhereClause,
            body: node.body
        )
        return .skipChildren
    }

    func finish() -> [Diagnostic.Record] {
        let twinNames = Swift.Set(candidates.filter { !$0.suppressed }.map(\.name))
        return
            candidates
            .filter { $0.suppressed && $0.assignsBox && !twinNames.contains($0.name) }
            .map { candidate in
                let location = converter.location(
                    for: candidate.token.positionAfterSkippingLeadingTrivia
                )
                return Diagnostic.Record(
                    location: Source.Location(
                        fileID: source.fileID,
                        filePath: source.filePath,
                        line: location.line,
                        column: location.column
                    ),
                    severity: severity,
                    identifier: "clone-less box",
                    message: cloneLessBoxMessage
                )
            }
    }

    private func record(
        name: Swift.String,
        token: TokenSyntax,
        genericParameters: GenericParameterClauseSyntax?,
        whereClause: GenericWhereClauseSyntax?,
        body: CodeBlockSyntax?
    ) {
        guard let body else { return }
        candidates.append(
            Candidate(
                name: name,
                suppressed: suppressesOwnParameter(genericParameters, whereClause),
                assignsBox: assignsSharedBox(body),
                token: token
            )
        )
    }

    /// Whether the decl's OWN generic parameters carry a `~Copyable` suppression —
    /// inline (`<V: ~Copyable>`) or via the decl's where clause (`where V: ~Copyable`
    /// for an own parameter).
    ///
    /// Extension-level suppression does not count.
    private func suppressesOwnParameter(
        _ genericParameters: GenericParameterClauseSyntax?,
        _ whereClause: GenericWhereClauseSyntax?
    ) -> Swift.Bool {
        guard let genericParameters else { return false }
        var ownNames: Swift.Set<Swift.String> = []
        for parameter in genericParameters.parameters {
            ownNames.insert(parameter.name.text)
            if let inherited = parameter.inheritedType, containsSuppressedCopyable(inherited) {
                return true
            }
        }
        guard let whereClause else { return false }
        for requirement in whereClause.requirements {
            guard let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self),
                let subject = conformance.leftType.as(IdentifierTypeSyntax.self),
                ownNames.contains(subject.name.text),
                containsSuppressedCopyable(conformance.rightType)
            else { continue }
            return true
        }
        return false
    }

    /// `~Copyable`, possibly inside a composition (`Hash.Key & ~Copyable`).
    private func containsSuppressedCopyable(_ type: TypeSyntax) -> Swift.Bool {
        if let suppressed = type.as(SuppressedTypeSyntax.self) {
            return suppressed.type.trimmedDescription == "Copyable"
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.contains { element in
                element.type.as(SuppressedTypeSyntax.self)?.type.trimmedDescription == "Copyable"
            }
        }
        return false
    }

    /// Whether the body assigns `self.<property> = Shared(...)` (box replacement
    /// or construction).
    private func assignsSharedBox(_ body: CodeBlockSyntax) -> Swift.Bool {
        let finder = SharedBoxAssignmentFinder(viewMode: .sourceAccurate)
        finder.walk(body)
        return finder.found
    }
}

internal final class SharedBoxAssignmentFinder: SyntaxVisitor {
    var found = false

    /// Folded trees (`SwiftOperators` consumers).
    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.is(AssignmentExprSyntax.self),
            isSelfMember(node.leftOperand), isSharedCall(node.rightOperand)
        {
            found = true
            return .skipChildren
        }
        return .visitChildren
    }

    /// Raw (unfolded) trees: `a = b` parses as a 3-element sequence with an
    /// `AssignmentExprSyntax` in operator position.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Swift.Array(node.elements)
        var index = 1
        while index < elements.count - 1 {
            if elements[index].is(AssignmentExprSyntax.self),
                isSelfMember(elements[index - 1]), isSharedCall(elements[index + 1])
            {
                found = true
                return .skipChildren
            }
            index += 1
        }
        return .visitChildren
    }

    private func isSelfMember(_ expression: ExprSyntax) -> Swift.Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return false }
        return member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
    }

    private func isSharedCall(_ expression: ExprSyntax) -> Swift.Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return false }
        return call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Shared"
    }
}
