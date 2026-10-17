# AGENTS.md

This file is the entry point for AI agents that work on Pointer. Read it before each task.

## Project summary

Pointer is a native iPad app for developer notes and data-structure sketches. It has a black canvas with no edges, a white pen, text boxes, and an eraser. Cards on a canvas open into their own canvas, so the canvases form a tree. All data stays on the device.

## Required reading

Read these documents before you write code:

1. [docs/code-of-code.md](docs/code-of-code.md): the coding standard. Every rule is mandatory.
2. [docs/product-spec.md](docs/product-spec.md): what the app does. Do not build features that it does not list.
3. The document for the area that you change:
   - [docs/architecture.md](docs/architecture.md) for modules, input, rendering, navigation, and export.
   - [docs/data-model.md](docs/data-model.md) for types, IDs, clocks, and commands.
   - [docs/storage.md](docs/storage.md) for the SQLite schema, saving, and backup.
4. [docs/decisions.md](docs/decisions.md): open questions. Do not decide an open question yourself.
5. [docs/plan.md](docs/plan.md): the current milestone and its acceptance criteria.

## Context map

This map shows the planned layout. Add each new folder to it (rule AGENT-07).

```
pointer/
  AGENTS.md                this file
  README.md                project overview
  docs/                    design documents and the coding standard
  Makefile                 one target per check, `make check` runs all
  .swift-format            formatter configuration (STYLE-04)
  .swiftlint.yml           lint rules, one custom rule per invariant
  Pointer.xcodeproj/       Xcode project with the app target and the PointerApp scheme
  PointerApp/              app target: scene setup and composition only
  Packages/                one local Swift package per folder
    Geometry/              Layer 0: Double geometry, camera math, spatial grid
    Model/                 Layer 0: value types, IDs, clock, commands, history, limits
    InkEngine/             Layer 0: filters, stroke building, eraser
    Persistence/           Layer 1: SQLite repository, migrations, snapshots, restore
    Rendering/             Layer 1: Metal renderer and shaders
    Export/                Layer 1: PDF export
    DesignSystem/          Layer 1: tokens and shared small views
    CanvasFeature/         Layer 2: canvas screen
    WorkspaceFeature/      Layer 2: workspace selector
    BackupFeature/         Layer 2: backup command and restore
  Scripts/                 check-layers.swift, assertion-density.swift, self-test.sh
    Fixtures/              small trees that the self-test runs the check scripts on
  Spikes/                  throwaway prototypes for M1 only               (planned, M1)
```

## Commands

Run the commands from the repository root. They need Xcode 27 and SwiftLint 0.65.1 (`brew install swiftlint`).

```
make build       # build the app for iOS, warnings are errors
make analyze     # xcodebuild analyze, zero findings
make test        # package tests: Tier A on the Mac, the others on an iPad simulator
make format      # swift format lint
make lint        # swiftlint --strict
make layers      # Scripts/check-layers.swift
make density     # Scripts/assertion-density.swift
make self-test   # runs the check scripts on Scripts/Fixtures
make check       # all of the above, the full check
```

`make test` uses the simulator "iPad Pro 13-inch (M5)". To use another simulator, set `SIMULATOR`, for example `make test SIMULATOR='platform=iOS Simulator,name=iPad Air 11-inch (M4)'`.

## Working rules

- Do the smallest change that completes the task (AGENT-02).
- Never add a dependency to the app (BUILD-03, AGENT-03). Development tools follow decision D-04.
- Stop and ask the product owner about an unclear or conflicting document (AGENT-04).
- Run the full pull request checklist before you report a task as done. Report each failure with its output (AGENT-05).
- Name the requirement IDs and the rule IDs in each pull request (GIT-03).

## Learned rules

Corrections from the product owner go here as numbered rules (AGENT-06).

None yet.
