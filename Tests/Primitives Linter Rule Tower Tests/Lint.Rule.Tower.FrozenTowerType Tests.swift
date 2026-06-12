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

import Testing
import SwiftSyntax
import SwiftParser
import Linter_Primitives
import Linter_Rules_Test_Support
@testable import Primitives_Linter_Rule_Tower

extension Lint.Rule {
    @Suite
    struct `frozen tower type Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.`frozen tower type Tests` {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: file)
        return Lint.Rule.`frozen tower type`.findings(parsed, .warning)
    }
}

// MARK: - Unit (the rule fires)

extension Lint.Rule.`frozen tower type Tests`.Unit {
    @Test
    func `unfrozen public stored struct under a tower root is flagged`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Storage {
                public struct Generational {
                    public var count: Int
                }
            }
            """)
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "frozen tower type")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `unfrozen top-level tower family struct is flagged`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            public struct Shared<Element> {
                internal var box: AnyObject
            }
            """)
        #expect(findings.count == 1)
    }

    @Test
    func `deep member-type extension roots at the outermost tower namespace`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Tree.N.Nested {
                public struct Header {
                    var highWater: Int
                }
            }
            """)
        #expect(findings.count == 1)
    }
}

// MARK: - Edge Case (boundary shapes; the rule stays silent)

extension Lint.Rule.`frozen tower type Tests`.`Edge Case` {
    @Test
    func `escapable-suppressed view type is exempt`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Buffer {
                public struct Span: ~Escapable {
                    var base: UnsafeRawPointer
                }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `curated exemption names stay unfrozen`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Buffer {
                public struct Checkpoint { var mark: Int }
                public struct Walk { var cursor: Int }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `Iterator- and View-suffixed types are exempt`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Queue {
                public struct ChunkIterator { var position: Int }
                public struct SliceView { var range: Range<Int> }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `static-only members are not stored data-plane state`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Stack {
                public struct Limits {
                    static var max: Int { 1024 }
                    public static let floor = 1
                }
            }
            """)
        #expect(findings.isEmpty)
    }
}

// MARK: - Negative (out of scope; the rule stays silent)

extension Lint.Rule.`frozen tower type Tests`.Negative {
    @Test
    func `frozen tower struct is compliant`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Storage {
                @frozen
                public struct Generational {
                    public var count: Int
                }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `non-tower namespaces are out of scope`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Cardinal {
                public struct Counter { var n: Int }
            }
            public struct Affine { var slope: Int }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `non-public and computed-only structs are out of scope`() {
        let findings = Lint.Rule.`frozen tower type Tests`.findings(in: """
            extension Storage {
                struct Ledger { var bits: Int }
                public struct Stats {
                    public var isEmpty: Bool { true }
                }
            }
            """)
        #expect(findings.isEmpty)
    }
}
