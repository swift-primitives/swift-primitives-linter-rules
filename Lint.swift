// swift-linter-tools-version: 0.1
// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives-linter-rules open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-primitives-linter-rules project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

// Foundation-up dogfeed continuation (Thread B). swift-primitives-linter-rules
// is the primitives-rules pack — its own Bundle.primitives composes the
// institute bundle plus primitives-tier rules (RawValue.*, etc.). Self-lint
// catches the full institute + primitives surface against this pack's source.

import Linter
import Linter_Primitives_Rules

Lint.run(dependencies: [
    .package(
        path: ".",
        products: ["Linter Primitives Rules"]
    ),
]) {
    Lint.Rule.Bundle.primitives
}
