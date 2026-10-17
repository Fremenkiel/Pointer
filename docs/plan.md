# Build plan

This document gives the build order. Each milestone ends with a demo on a real iPad and a list of acceptance criteria. A milestone is done only with all criteria met and the checklist in [code-of-code.md](code-of-code.md) section 5 passed.

Build the milestones in order. M1 is a test that can change the design. Do not start M2 before the product owner decides D-02.

## M0: Project skeleton

- Make the Xcode project, the app target, and the empty packages of [architecture.md](architecture.md) section 3.
- Add `.swift-format`, `Scripts/lint.swift`, `Scripts/check-layers.swift`, `Scripts/assertion-density.swift`, and `Scripts/metrics.swift`.
- Add a `Makefile` or `Scripts/ci.sh` with one command per check.
- Fill in the commands and the context map in `AGENTS.md`.

Acceptance:

1. The app launches to a black screen on an iPad.
2. Each check script runs and passes on the empty project.
3. A test import from a feature package into another feature package fails `check-layers`.

## M1: Latency test (go or no-go)

Build two throwaway prototypes in a `Spikes/` folder. They do not follow the full standard.

1. `PencilKit`: a `PKCanvasView` with a white monoline pen on black.
2. `Custom`: a `CAMetalLayer` view, `UIUpdateLink` with low latency, coalesced and predicted touches, and capsule rendering.

Measure both on a 120 Hz iPad Pro with a high-speed camera and with the presented-time log (see [research.md](research.md) section 3.4). Also tune the 1€ filter values.

Acceptance:

1. A short report in `docs/research.md` with the measured latency of both, the method, and the device.
2. The product owner decides D-02.

## M2: Ink on one canvas

- `Geometry`: points, rectangles, transforms, `SpatialGrid`.
- `Model`: `Stroke`, `InkPoint`, `CanvasContent`, `Limits`, IDs, `HybridClock`.
- `InkEngine`: `OneEuroFilter`, `StrokeBuilder`, Catmull-Rom subdivision.
- `Rendering`: committed layer, live stroke, capsule shader, culling.
- `CanvasFeature`: canvas view, pencil input, finger pan and pinch, camera.

Acceptance:

1. Latency meets FEEL-01 on the device.
2. 20,000 strokes pan and zoom at 120 Hz with zero dropped frames in a 10-second recording.
3. Strokes at canvas position (1,000,000, 1,000,000) look the same as strokes at the origin.
4. The stroke does not change shape at pencil lift (snapshot test of the live and the finished stroke).

## M3: Storage and workspaces

- `Persistence`: repository actor, JSON records, ink chunks, index, compaction, migrations.
- `WorkspaceFeature`: selector in the top left, create, rename, delete.
- Device state: last workspace and camera.

Acceptance:

1. A force quit loses at most 2 seconds of ink (STO-06), shown with an automated crash test.
2. The library shows in the Files app, and a copy of it opens on a second iPad.
3. All corruption tests in [storage.md](storage.md) section 9 pass.

## M4: Eraser and undo

- `InkEngine`: eraser hit test and `StrokeSplitter` (or whole-stroke, per D-06).
- `Model`: `History` and all ink commands.
- Undo and redo buttons in the top right corner. Command-Z on a hardware keyboard.

Acceptance:

1. Each command passes the apply-then-revert test (TEST-09).
2. Erase, undo, and redo of 1,000 strokes in one gesture takes under 16 ms per step.

## M5: Text boxes

- Text tool, `UITextView` overlay, Core Text texture cache, move with long press and drag.

Acceptance:

1. Scribble writes into a text box.
2. Text on the canvas and text in edit mode line up to within one pixel at zoom 0.5, 1, and 4 (snapshot test).

## M6: Cards and navigation

- Card creation (D-08), card previews, open (D-09), up button, pinch-out exit with the minimize animation, navigation path.

Acceptance:

1. Open and leave a card with no visible jump (screen recording, frame by frame).
2. A tree of 32 levels works. Level 33 is refused with a message.
3. A finger lift above the threshold cancels the pinch-out exit.

## M7: Apple Pencil interactions

- Double tap, squeeze palette, hover dot.

Acceptance:

1. Double tap follows D-07 for each value of `preferredTapAction`.
2. Squeeze opens the palette at the pencil tip on Apple Pencil Pro.
3. With an Apple Pencil (USB-C), every feature that does not need tap or squeeze works.

## M8: PDF export

- `Export`: `PDFExporter`, export button, share sheet.

Acceptance:

1. The exported PDF opens in Preview on a Mac. Ink stays sharp at 6400% zoom. Text can be selected and searched.
2. A snapshot test compares a rendered PDF page with the screen render of the same canvas.

## M9: Backup

- `BackupFeature`: "Back up now", the App Intent (D-14).

Acceptance:

1. The zip opens on a Mac, and its tree equals the library folder.
2. A Shortcuts automation saves a backup to iCloud Drive at a fixed time. Record the result with the iPad locked and unlocked (D-14).

## M10: Hardening

- Limits: each limit in [architecture.md](architecture.md) section 10 has a test at the limit and at the limit plus one.
- UI tests for the main flows.
- Performance baselines for all budgets.
- Accessibility: VoiceOver labels for every button, Dynamic Type in the chrome.

Acceptance:

1. All performance tests pass against their baselines on the device.
2. Coverage meets TEST-02.
