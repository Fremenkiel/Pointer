# AGENTS.md

This file is the entry point for AI agents that work on Pointer. Read it before each task.

## Project summary

Pointer is a native iPad app for developer notes and data-structure sketches. It has a dark gray canvas (RGB 24, 24, 24) with no edges, a white pen, text boxes, and an eraser. Cards on a canvas open into their own canvas, so the canvases form a tree. All data stays on the device.

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
    Assets.xcassets/       app icon and launch background
  PointerAppTests/         tests of the app target, part of PointerDeviceTests only
  Packages/                one local Swift package per folder, each with Sources/, most with Tests/
    Geometry/              Layer 0: Double geometry, camera math, spatial grid
    Model/                 Layer 0: value types, IDs, clock, commands, history, limits
    InkEngine/             Layer 0: eraser hit test and stroke split
    Persistence/           Layer 1: SQLite repository, migrations, snapshots (restore comes in M9)
      Sources/PersistenceCrashHelper/   helper process that the crash test stops (D-54)
      Tests/PersistenceTests/Fixtures/  fixture database and its SQL per schema version (TEST-08)
      Tests/PersistenceDeviceTests/     device performance tests, part of PointerDeviceTests only
    Rendering/             Layer 1: Metal renderer and shaders
      Tests/RenderingTests/             part of PointerDeviceTests only (D-77)
        References/        reference PNGs of the snapshot tests, made on the iPad (TEST-07)
    Export/                Layer 1: PDF export
      Tests/ExportTests/   part of PointerDeviceTests only (D-77, D-140)
        References/        reference PNGs of the snapshot tests, made on the iPad (TEST-07)
    DesignSystem/          Layer 1: tokens, no Tests/ yet
    CanvasFeature/         Layer 2: canvas screen
      Sources/CanvasFeature/Resources/      String Catalog of the canvas
      Tests/CanvasFeatureTests/             part of PointerDeviceTests only (D-77)
      Tests/CanvasFeatureSnapshotTests/     view snapshots, part of PointerDeviceTests only (D-77)
        References/        reference PNGs of the snapshot tests, made on the iPad (TEST-07)
    WorkspaceFeature/      Layer 2: workspace selector
      Sources/WorkspaceFeature/Resources/   String Catalog of the selector
      Tests/WorkspaceFeatureTests/          part of PointerDeviceTests only (D-77)
      Tests/WorkspaceFeatureSnapshotTests/  view snapshots, part of PointerDeviceTests only (D-77)
        References/        reference PNGs of the snapshot tests, made on the iPad (TEST-07)
    BackupFeature/         Layer 2: backup commands and restore flow
      Sources/BackupFeature/Resources/      String Catalog of the backup commands and messages
      Tests/BackupFeatureTests/             part of PointerDeviceTests only (D-77)
      Tests/BackupFeatureSnapshotTests/     view snapshots, part of PointerDeviceTests only (D-77)
  Scripts/                 check-layers.swift, assertion-density.swift, coverage.swift, self-test.sh
    Fixtures/              small trees that the self-test runs the check scripts on
```

## Commands

Run the commands from the repository root. They need Xcode 27 and SwiftLint 0.65.1 (`brew install swiftlint`).

```
make build       # build the app for iOS, warnings are errors
make analyze     # xcodebuild analyze, zero findings
make test        # Tier A tests on the Mac, then PointerDeviceTests on the iPad
make snapshots   # the snapshot tests in PointerDeviceTests on the iPad (D-77)
make format      # swift format lint
make lint        # swiftlint --strict
make layers      # Scripts/check-layers.swift
make density     # Scripts/assertion-density.swift
make self-test   # runs the check scripts on Scripts/Fixtures
make plist       # the Files app keys of PointerApp/Info.plist are true
make check       # all of the above, the full check
make coverage    # line coverage of TEST-02, a separate device run (D-120)
```

`make test` and `make snapshots` use the connected iPad Pro 11-inch (M4) in Release. To use another iPad, set `DEVICE` to its UDID, for example `make test DEVICE=00008132-000018993E8B801C`. Before a device run, make sure that the iPad is unlocked: `xcrun devicectl device info lockState --device <UDID>` must print `passcodeRequired: false`.

## Working rules

- Do the smallest change that completes the task (AGENT-02).
- Never add a dependency to the app (BUILD-03, AGENT-03). Development tools follow decision D-04.
- Stop and ask the product owner about an unclear or conflicting document (AGENT-04).
- Run the full pull request checklist before you report a task as done. Report each failure with its output (AGENT-05).
- Name the requirement IDs and the rule IDs in each pull request (GIT-03).

## Learned rules

Corrections from the product owner go here as numbered rules (AGENT-06).

1. Run the tests on the connected iPad, never on a simulator, and do not make a simulator (product owner, 2026-10-20). Package tests cannot run on a device, so run the Mac parts of `make check` and all of `PointerDeviceTests` on the iPad. Keep the iPad unlocked during a device run.
2. Do not ask the product owner to accept a failed test, also one older than the task (product owner, 2026-10-24). Define the behavior that the test expects and the way it fails. Research the cause in reliable sources, benchmark the possible solutions on the iPad, and fix the cause.
