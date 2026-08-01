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

internal import SwiftSyntax

/// Finds `self.<property> = Shared(...)` assignments (box replacement or
/// construction) — the shared visitor helper for `Lint.Rule.\`clone-less box\``.
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
        // cardinal_count_minus_one_anti_pattern β-path exemption ([INFRA-025], adjudicated
        // 2026-07-02): stdlib-Int SwiftSyntax-visitor site — `elements` is a Swift.Array of
        // syntax nodes whose `count` is Int; no typed Cardinal surface exists. The rule is
        // repo-disabled by the self-referential exemption in .swiftlint.yml (a directive here
        // would itself trip superfluous_disable_command on SwiftLint 0.63.3); if that
        // exemption is lifted, re-apply a disable-next directive for this rule (with this
        // reason, dash-delimited) at this site.
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
