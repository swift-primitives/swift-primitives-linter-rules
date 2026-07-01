# Primitives Linter Rules

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-primitives-linter-rules/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-primitives-linter-rules/actions/workflows/ci.yml)

The primitives-tier rule pack for [swift-linter](https://github.com/swift-foundations/swift-linter): SwiftSyntax AST rules that catch anti-patterns a regex cannot — evasion-resistant detection of untyped index arithmetic, `rawValue` chaining, and unlocked storage-tower layouts — aggregated into a single bundle, `Lint.Rule.Bundle.primitives`.

Each rule is an AST predicate, not a text match. `seq.count - 1` is caught whether it is written directly, paren-wrapped (`(seq.count) - 1`), cast-wrapped (`Double(seq.count) - 1`), operand-reordered (`seq.count - i - 1`), or algebraically flipped through a comparison (`i + 1 < seq.count`) — after operator folding these collapse to two syntax-tree shapes, so the rewrites that defeat a regex all land on the same predicate. Comments and string literals are trivia at the AST level, so they can never false-positive.

---

## Rules

| Pack | Rule | Fires on |
|------|------|----------|
| Cardinal | `count minus one` | `<expr>.count - 1` and its algebraic rewrites — the untyped off-by-one idiom that a typed cardinal/ordinal system exists to eliminate |
| Cardinal | `zero or one literal` | `Cardinal(0)` / `Cardinal(1)` constructor calls that bypass the canonical `.zero` / `.one` accessors |
| RawValue | `chained rawvalue access` | `.rawValue.<member>` chains (including paren-wrap evasion) that tunnel through a typed wrapper instead of using its typed surface |
| RawValue | `bitpattern rawvalue chain` | `init(bitPattern:)` calls whose argument chains through `.rawValue` — the callee is unconstrained, so typename-swap rewrites (`Int(bitPattern:)`, `UInt(bitPattern:)`, `self.init(bitPattern:)`, …) all hit |
| RawValue | `tagged extension public init` | Public initializers declared in extensions of `Tagged`, which bypass the brand's bounded construction surface |
| Tower | `frozen tower type` | Public stored value types in the storage-tower namespaces (`Buffer`, `Array`, `Column`, …) that are not `@frozen`, which would block cross-module consuming decomposition |
| Tower | `clone-less box` | A `Shared`-box replacement in a function whose own generics suppress copyability, with no same-file Copyable twin overload — the shape that statically resolves to the strategy-less box initializer and traps on the first post-fork mutation |

`Lint.Rule.Bundle.primitives` composes the institute-tier bundle (which transitively includes the universal bundle) plus all seven rules above, so a primitives-tier consumer activates the full applicable rule set with one declaration.

---

## Quick Start

Activate the bundle by name in a lint configuration:

```swift
import Linter_Primitives_Rules

let configuration = Lint.Configuration {
    Lint.Rule.Bundle.primitives
}
```

Adding a rule to this package extends the bundle; consumers pick up the new rule automatically on their next dependency resolution — no per-consumer configuration edit.

Every diagnostic carries a remediation message naming the canonical replacement, and each rule can be suppressed per-site with `// swift-linter:disable:next <rule id>` plus a `// REASON:` continuation, so escapes are deliberate and documented rather than silent.

This repository lints itself with the same bundle — see [`Lint.swift`](Lint.swift).

---

## Installation

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-primitives-linter-rules.git", branch: "main")
]
```

Add a product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Linter Primitives Rules", package: "swift-primitives-linter-rules")
    ]
)
```

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26.

---

## Architecture

| Product | Contents | When to import |
|---------|----------|----------------|
| `Linter Primitives Rules` | The aggregate — `Lint.Rule.Bundle.primitives`, re-exporting all packs plus the institute-tier bundle | Most consumers |
| `Primitives Linter Rule Cardinal` | The two cardinal-arithmetic rules | Composing a custom configuration from individual packs |
| `Primitives Linter Rule RawValue` | The three `rawValue`-discipline rules | Composing a custom configuration from individual packs |
| `Primitives Linter Rule Tower` | The two storage-tower structural rules | Composing a custom configuration from individual packs |

---

## Related Packages

- [`swift-linter-primitives`](https://github.com/swift-primitives/swift-linter-primitives) — the `Lint.Rule` / `Lint.Rule.Configuration` vocabulary these rules are written against.
- [`swift-institute-linter-rules`](https://github.com/swift-foundations/swift-institute-linter-rules) — the institute-tier bundle this package's bundle composes.
- [`swift-linter-rules`](https://github.com/swift-foundations/swift-linter-rules) — the universal rule packs and the rule test support used by this package's tests.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
