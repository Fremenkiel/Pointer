# Pointer

> AI disclaimer: AI coding agents wrote parts of the code and the documents in this repository. The content can contain errors.

Pointer is an iPad app for software developers. You use it to draw data structures and to write technical notes with Apple Pencil.

The app has one dark gray canvas per workspace. The canvas has no edges. You can put cards on a canvas. Each card is a canvas of its own, so the workspaces form a tree of canvases.

The app has three tools only: a white pen, text boxes, and an eraser. It stores all data on the device. It has no accounts.

## Status

All eleven milestones are done, M0 to M11: ink, storage and workspaces, the eraser and undo, text boxes, cards and navigation, the Apple Pencil interactions, PDF export, backup and restore, hardening, and the fixes of the review of 2026-10-28. PencilKit draws the live stroke, and a Metal renderer draws the finished ink (decisions D-02 and D-33). The performance baseline of the iPad Pro 11-inch (M4) is in `Performance/Baselines/`. No next milestone is planned. See [docs/plan.md](docs/plan.md) for the state of each milestone and the work that waits for the product owner.

## Build

Install Xcode 27 and SwiftLint (`brew install swiftlint`). Then run all checks from the repository root:

```
make check
```

Open `Pointer.xcodeproj` in Xcode to run the app. Set your signing team on the `PointerApp` target before you run it on an iPad.

## Documents

Read the documents in this order:

1. [docs/product-spec.md](docs/product-spec.md) gives the product requirements and the interaction rules.
2. [docs/research.md](docs/research.md) gives the research results and the sources.
3. [docs/architecture.md](docs/architecture.md) gives the implementation design: modules, input, rendering, navigation, and export.
4. [docs/data-model.md](docs/data-model.md) gives the data types and their rules.
5. [docs/storage.md](docs/storage.md) gives the SQLite schema, the save strategy, and the backup strategy.
6. [docs/code-of-code.md](docs/code-of-code.md) gives the coding standard. All contributors must obey it, people and agents.
7. [docs/plan.md](docs/plan.md) gives the build order, the state of each milestone, and the open work.
8. [docs/decisions.md](docs/decisions.md) lists each design decision of the product owner.
9. The reviews, newest first: [docs/review-2026-10-28.md](docs/review-2026-10-28.md) after M10, [docs/review-2026-10-24-m9.md](docs/review-2026-10-24-m9.md) after M9, [docs/review-2026-10-24.md](docs/review-2026-10-24.md) after M8, and [docs/review-2026-10-17.md](docs/review-2026-10-17.md), the design review.

[AGENTS.md](AGENTS.md) is the entry point for AI coding agents.

## Platform

- Language: Swift 6 language mode, Swift 6.4 toolchain, Xcode 27.
- Target: iPad only. The minimum version is iPadOS 26 (see [docs/decisions.md](docs/decisions.md), D-01).
- Dependencies: Apple frameworks only. The app links no third-party code. Development tools such as linters and formatters can come from third parties (D-04).
