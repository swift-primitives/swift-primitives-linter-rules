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

import Testing
import SwiftSyntax
import SwiftParser
import Linter_Primitives
import Linter_Rules_Test_Support
@testable import Linter_Rule_RawValue

extension Lint.Rule {
    @Suite
    struct `tagged extension public init Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

extension Lint.Rule.`tagged extension public init Tests` {
    static func findings(in source: Swift.String, file: Swift.String = "Sources/X/Test.swift") -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: file)
        return Lint.Rule.`tagged extension public init`.findings(parsed, .warning)
    }
}

extension Lint.Rule.`tagged extension public init Tests`.Unit {
    @Test
    func `extension on bare Tagged with public init is flagged`() {
        let source = """
        extension Tagged {
            public init(rawValue: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 1)
        if findings.count == 1 {
            #expect(findings[0].identifier == "tagged extension public init")
        }
    }

    @Test
    func `extension on Tagged generic specialization with public init is flagged`() {
        let source = """
        extension Tagged<UserTag, String> {
            public init(_ s: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `extension on Tagged with internal init is permitted`() {
        let source = """
        extension Tagged {
            init(rawValue: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `extension on non-Tagged type with public init is permitted`() {
        let source = """
        extension MyType {
            public init(rawValue: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `extension on Tagged with multiple public inits flags each`() {
        let source = """
        extension Tagged {
            public init(_ s: String) { fatalError() }
            public init(value: Int) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 2)
    }

    @Test
    func `extension on Tagged with public method but no public init is permitted`() {
        let source = """
        extension Tagged {
            public func foo() {}
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }
}

extension Lint.Rule.`tagged extension public init Tests`.`Edge Case` {
    @Test
    func `extension on qualified Tagging Tagged is flagged`() {
        let source = """
        extension Tagging.Tagged {
            public init(_ s: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `extension on Tagged with where clause is flagged`() {
        let source = """
        extension Tagged where RawValue == String {
            public init(_ s: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 1)
    }

    @Test
    func `extension on TaggedFoo (compound name) is not flagged`() {
        let source = """
        extension TaggedFoo {
            public init(_ s: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    // Exemption shape: [RULE-EXEMPT-2] (protocol-witness-citation-dict).
    // Extensions on `Tagged` that conform to a stdlib literal protocol
    // are exempt — the protocol's `init(...)` requirement IS the
    // validation gate; the conformer cannot drop the public init and
    // still satisfy the contract. The dict pairs each witness key with
    // its specific protocol.

    @Test
    func `extension on Tagged conforming to ExpressibleByIntegerLiteral is exempt per RULE-EXEMPT-2`() {
        let source = """
        extension Tagged: ExpressibleByIntegerLiteral {
            public init(integerLiteral value: Int) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `extension on Tagged conforming to Decodable is exempt per RULE-EXEMPT-2`() {
        let source = """
        extension Tagged: Decodable {
            public init(from decoder: any Decoder) throws { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `extension on Tagged conforming to RawRepresentable is exempt per RULE-EXEMPT-2`() {
        let source = """
        extension Tagged: RawRepresentable {
            public init?(rawValue: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    // Exemption shape: [RULE-EXEMPT-5] (Protocol-sentinel) composed
    // with [RULE-EXEMPT-2]. The `` `Protocol` `` key in the dict
    // encodes the institute hoisted-protocol pattern per [API-IMPL-009]
    // / [PKG-NAME-001]: `extension Tagged: Carrier.\`Protocol\`` —
    // the conformer satisfies the nested-namespace protocol witness
    // and inherits its init contract. The backtick-escaped form is
    // load-bearing: bare `Carrier.Protocol` parses as a
    // `MetatypeTypeSyntax` (Swift's `.Protocol` metatype keyword),
    // so the institute pattern always uses the escaped spelling.
    // Inheritance-leaf walking captures the trailing identifier as
    // `` `Protocol` ``, which matches the dict entry.

    @Test
    func `extension on Tagged conforming to backtick-escaped Protocol sentinel is exempt per RULE-EXEMPT-5`() {
        let source = """
        extension Tagged: Carrier.`Protocol` {
            public init(value: Int) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.isEmpty)
    }

    @Test
    func `extension on Tagged conforming to non-witness protocol is still flagged`() {
        let source = """
        extension Tagged: CustomStringConvertible {
            public init(_ s: String) { fatalError() }
        }
        """
        let findings = Lint.Rule.`tagged extension public init Tests`.findings(in: source)
        #expect(findings.count == 1)
    }
}
