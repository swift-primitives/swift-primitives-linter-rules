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
    struct `clone-less box Tests` {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
        @Suite struct Negative {}
    }
}

extension Lint.Rule.`clone-less box Tests` {
    static func findings(in source: Swift.String, file: Swift.String = "test.swift") -> [Diagnostic.Record] {
        let parsed = Lint.Source.parsed(from: source, file: file)
        return Lint.Rule.`clone-less box`.findings(parsed, .warning)
    }
}

// MARK: - Unit (the rule fires)

extension Lint.Rule.`clone-less box Tests`.Unit {
    @Test
    func `suppressed-only box replacement without a twin is flagged`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Dictionary where S: ~Copyable {
                public mutating func removeAll<K: Hash.Key & ~Copyable, V: ~Copyable>()
                where S == Shared<Hash.Entry<K, V>, Engine<K, V>> {
                    self.store = Shared(Engine<K, V>())
                }
            }
            """)
        let count = findings.count
        #expect(count == 1)
        if count == 1 {
            #expect(findings[0].identifier == "clone-less box")
            #expect(findings[0].severity == .warning)
        }
    }

    @Test
    func `suppressed initializer constructing the box without a twin is flagged`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Stack {
                public init<Element: ~Copyable>(building: Element) {
                    self.store = Shared(Column.Heap<Element>())
                }
            }
            """)
        #expect(findings.count == 1)
    }

    @Test
    func `where-clause suppression on an own parameter counts`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Queue {
                public mutating func reset<E>() where E: ~Copyable, S == Shared<E, Ring<E>> {
                    self.store = Shared(Ring<E>())
                }
            }
            """)
        #expect(findings.count == 1)
    }
}

// MARK: - Edge Case (boundary shapes; the rule stays silent)

extension Lint.Rule.`clone-less box Tests`.`Edge Case` {
    @Test
    func `extension-level column suppression alone does not count`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Deque where S: ~Copyable {
                public mutating func reset() {
                    self.store = Shared(Ring())
                }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `suppressed overload without a box assignment is silent`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Dictionary {
                public mutating func removeAll<K: ~Copyable, V: ~Copyable>() {
                    store.removeAll()
                }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `local Shared construction without self assignment is silent`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension SlotMap {
                public func snapshot<E: ~Copyable>() -> Shared<E, Slots<E>> {
                    let fresh = Shared(Slots<E>())
                    return fresh
                }
            }
            """)
        #expect(findings.isEmpty)
    }
}

// MARK: - Negative (the lawful pair; the rule stays silent)

extension Lint.Rule.`clone-less box Tests`.Negative {
    @Test
    func `the pinned pair is lawful — suppressed overload with an implicitly-Copyable twin`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Dictionary where S: ~Copyable {
                public mutating func removeAll<K: Hash.Key, V>()
                where S == Shared<Hash.Entry<K, V>, Engine<K, V>> {
                    self.store = Shared(Engine<K, V>())
                }

                public mutating func removeAll<K: Hash.Key & ~Copyable, V: ~Copyable>()
                where S == Shared<Hash.Entry<K, V>, Engine<K, V>> {
                    self.store = Shared(Engine<K, V>())
                }
            }
            """)
        #expect(findings.isEmpty)
    }

    @Test
    func `suppression-free box replacement is lawful alone`() {
        let findings = Lint.Rule.`clone-less box Tests`.findings(in: """
            extension Array {
                public mutating func reset<E>() where S == Shared<E, Linear<E>> {
                    self.store = Shared(Linear<E>())
                }
            }
            """)
        #expect(findings.isEmpty)
    }
}
