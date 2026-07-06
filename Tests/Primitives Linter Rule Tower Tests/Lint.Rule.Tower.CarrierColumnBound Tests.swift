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

import Linter_Primitives
import Linter_Rules_Test_Support
import SwiftParser
import SwiftSyntax
import Testing

@testable import Primitives_Linter_Rule_Tower

extension Lint.Rule {
    @Suite
    struct `carrier column bound Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.`carrier column bound Tests` {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: file)
        return Lint.Rule.`carrier column bound`.findings(parsed, .warning)
    }
}

// MARK: - Unit (the rule fires — FAIL fixtures)

extension Lint.Rule.`carrier column bound Tests`.Unit {
    @Test
    func `hoisted carrier with an inline composition bound is flagged`() {
        // The real pre-reshape shape from git history (swift-array-primitives 98ed3fb).
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Array<S: Store.`Protocol` & Buffer.`Protocol` & ~Copyable>: ~Copyable {
                    var storage: S
                }
                """
        )
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "carrier column bound")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `non-hoisted ADT-family carrier with an inline bound is flagged`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct Array<S: Store.`Protocol` & ~Copyable>: ~Copyable {
                    var storage: S
                }
                """
        )
        #expect(findings.count == 1)
    }

    @Test
    func `where-clause bound on the column axis is flagged`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Queue<S> where S: Buffer.`Protocol` {
                    var storage: S
                }
                """
        )
        #expect(findings.count == 1)
    }

    @Test
    func `single Storage-Protocol member bound is flagged`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Stack<S: Storage.`Protocol`> {
                    var storage: S
                }
                """
        )
        #expect(findings.count == 1)
    }
}

// MARK: - Edge Case (boundary shapes; the rule stays silent)

extension Lint.Rule.`carrier column bound Tests`.`Edge Case` {
    @Test
    func `capability bound on a capability EXTENSION is the lawful form`() {
        // The [DS-025] correct shape: the bound lives on the extension, not the type.
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                extension __Array where S: Store.`Protocol` & Buffer.`Protocol` {
                    public func first() -> S.Element? { nil }
                }
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `bound on a NON-column axis is out of scope`() {
        // The capability bound is on `Element`, not the storage axis `S`.
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Fixed<Element: Store.`Protocol`> {
                    var storage: Element
                }
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `where-clause requirement on a non-column axis does not fire`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Heap<S: ~Copyable, E> where E: Comparable {
                    var storage: S
                }
                """
        )
        #expect(findings.isEmpty)
    }
}

// MARK: - Negative (out of scope / compliant; the rule stays silent — PASS fixtures)

extension Lint.Rule.`carrier column bound Tests`.Negative {
    @Test
    func `compliant reshaped carrier is silent`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct __Set<S: ~Copyable>: ~Copyable {
                    var storage: S
                }
                public struct __Dictionary<S: ~Copyable>: ~Copyable {
                    var storage: S
                }
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `non-tower struct with an S bound is out of scope`() {
        // `Widget` is neither a hoisted `__X` carrier nor an ADT-family root.
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                public struct Widget<S: Store.`Protocol`> {
                    var storage: S
                }
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `storage substrate keyed on Element is out of scope`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                extension Storage {
                    public struct Contiguous<Element: ~Copyable>: ~Copyable {
                        var base: UnsafeMutableBufferPointer<Element>
                    }
                }
                """
        )
        #expect(findings.isEmpty)
    }

    @Test
    func `non-public carrier is out of scope`() {
        let findings = Lint.Rule.`carrier column bound Tests`.findings(
            in: """
                struct __Array<S: Store.`Protocol`> {
                    var storage: S
                }
                """
        )
        #expect(findings.isEmpty)
    }
}
