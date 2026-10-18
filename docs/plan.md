# Build plan

This document gives the build order. Each milestone ends with a demo on a real iPad and a list of acceptance criteria. A milestone is done only with all criteria met and the checklist in [code-of-code.md](code-of-code.md) section 5 passed.

Build the milestones in order. M1 was a test that could change the design. It did: the product owner chose the hybrid of D-33 after M1 (D-02).

## M0: Project skeleton

- Make the Xcode project, the app target, and the empty packages of [architecture.md](architecture.md) section 3.
- Add `.swift-format`, `.swiftlint.yml`, `Scripts/check-layers.swift`, and `Scripts/assertion-density.swift`.
- Add a `Makefile` or `Scripts/ci.sh` with one command per check.
- Fill in the commands and the context map in `AGENTS.md`.

Acceptance:

1. The app launches to a black screen on an iPad.
2. Each check script runs and passes on the empty project.
3. A test import from a feature package into another feature package fails `check-layers`.

## M1: Latency test (go or no-go)

Status: done on 2026-10-17 by a decision of the product owner. The custom input path trailed the pencil, so Pointer uses the hybrid. The product owner compared the prototypes by eye and skipped the camera measurement, so acceptance 1 and 3 have no measured values. See [research.md](research.md) section 3.5.

Build three throwaway prototypes in a `Spikes/` folder. They do not follow the full standard.

1. `PencilKit`: a `PKCanvasView` with a white monoline pen on black.
2. `Custom`: a `CAMetalLayer` view, `UIUpdateLink` with low latency, coalesced and predicted touches, and capsule rendering.
3. `Hybrid`: PencilKit captures the pencil input, and the renderer of `Custom` draws the ink. This is the fallback of D-33. PencilKit gives no samples before pencil lift, so a `PKCanvasView` at zoom 1 draws the live stroke. At pencil lift, the stroke moves to the Metal renderer and leaves the `PKCanvasView`. Set the pen width from the camera zoom. Measure the latency, and make sure that the stroke does not change at the handoff (FEEL-03).

Measure all three on a 120 Hz iPad Pro with a high-speed camera and with the presented-time log (see [research.md](research.md) section 3.4). Also tune the 1€ filter values.

In `Custom`, also measure these points:

1. Latency with `presentsWithTransaction` set to `true` and to `false` (review A-15).
2. The CPU time from the pencil event to the end of command encoding. The budget is 3 ms, because low-latency events get half of the 8.3 ms frame (review A-15).
3. Whether `UITouch.timestamp` and `MTLDrawable.presentedTime` use the same clock. Compare both with `CACurrentMediaTime()` once (review B-3).

Acceptance:

1. A short report in `docs/research.md` with the measured latency of all three, the method, and the device.
2. The custom engine is at most 3 ms slower than PencilKit. If it is more than 3 ms slower, the hybrid is the fallback (D-33), and the product owner decides D-02 again.
3. The report gives the `presentsWithTransaction` setting with the lower latency, the CPU time against the 3 ms budget, and the result of the clock test.

## M2: Ink on one canvas

Status: done on 2026-10-18. The product owner accepted acceptance 1 (D-40), 2, and 10, and the frame-loop tests and the coverage meet their targets. See [m2-plan.md](m2-plan.md) section 4.5.

- `Geometry`: points, rectangles, transforms, `Camera`, `SpatialGrid`, `StrokeCurve` (D-26).
- `Model`: `Stroke`, `InkPoint`, `InkPoints`, `CanvasContent`, `Limits`, IDs as UUID version 7 (D-31), `HybridClock`.
- `InkEngine`: no work in M2. The eraser parts come in M4.
- `Rendering`: point arena with a slab allocator, B-spline capsule shader with vertex pulling, `max` blending and the sRGB layer (D-38), level of detail, committed texture with a margin and chunked redraw, culling, presented handler for the handoff (D-28).
- `CanvasFeature`: canvas view, live `PKCanvasView`, `PencilKitStrokeConverter` with the split at the point limit, handoff, finger pan and pinch, palm guard, camera.

Known issue from M1: in the hybrid spike, the live stroke and the finished stroke differ in style and width. After the engine parts above work, fix this difference before M2 is done. Acceptance 4 and 5 test it. [architecture.md](architecture.md) section 4.2 lists possible causes.

Acceptance:

1. Latency meets FEEL-01 on the device.
2. 20,000 strokes pan and zoom at 120 Hz with zero dropped frames in a 10-second recording.
3. Strokes at canvas position (1,000,000, 1,000,000) look the same as strokes at the origin.
4. The stroke does not change shape at the handoff (FEEL-03): a test compares the PencilKit image with the Metal image of the same stroke at zoom 0.25, 1, and 8.
5. At zoom 0.25 and 8, the PencilKit tool width is not clamped by `validWidthRange`, or the product owner accepts the difference.
6. The center of a stroke is 255 in each channel in the PencilKit image and in the Metal image, or both images have the same value (D-38).
7. A snapshot test of a tight zigzag stroke shows no bright joints and no notches (D-38, review A-06).
8. On the device, a palm that rests on the screen while you write does not pan or zoom the canvas (review A-14).
9. On the device, `StrokeCurve` matches `PKStrokePath.interpolatedLocation(at:)` to within 0.01 canvas points at many parameter values, also at the ends (D-26).
10. 200,000 strokes pan and zoom at 120 Hz with zero dropped frames in a 10-second recording (review A-04, D-28).

## M3: Storage and workspaces

- `Model`: `Workspace`, `Card`, `TextBox`, `EraseRecord`, `RecordMeta`, `FractionalIndex`, `DeviceState`, and the protocol `LibraryRepository`. Cards and text boxes get no UI in M3 (D-50).
- `Persistence`: SQLite wrapper, repository actor, schema with all tables, row codecs, point BLOB codec, migrations, automatic snapshots.
- `WorkspaceFeature`: selector in the top left, create, rename, delete.
- Device state: last workspace and camera.

The tasks are in [m3-plan.md](m3-plan.md).

Status on 2026-10-18: all tasks are in the code, and `make check` passes. Acceptance 1, 3, and 4 pass. Acceptance 2 passes for the file, and the look at the Files app waits for the product owner, as does the manual test of task 3.9. See [m3-plan.md](m3-plan.md) section 4.

Acceptance:

1. A force quit loses at most 2 seconds of ink (STO-06), shown with an automated crash test.
2. A snapshot shows in the Files app under `Backups`. Copied to a Mac, it opens with `sqlite3` and passes `PRAGMA integrity_check` (D-51).
3. A canvas with 10,000 nodes and 20,000 strokes opens in under 300 ms on the device.
4. All corruption tests in [storage.md](storage.md) section 9 pass.

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
4. No app action plays a haptic event in Apple Pencil Pro (PEN-06). Drawing plays no haptic event. A system haptic on squeeze is accepted (D-23).

## M8: PDF export

- `Export`: `PDFExporter`, export button, share sheet.

Acceptance:

1. The exported PDF opens in Preview on a Mac. Ink stays sharp at 6400% zoom. Text can be selected and searched.
2. A snapshot test compares a rendered PDF page with a reference image: a white page, black ink and text, and no cards.

## M9: Backup

- `BackupFeature`: "Back up now" and restore (D-20). No App Intent (D-14).

Acceptance:

1. A snapshot from "Back up now" opens with `sqlite3` on a Mac and passes `PRAGMA integrity_check`.
2. A restore from a snapshot gives a library with the same rows.
3. A snapshot from one iPad restores on a second iPad, and the second iPad shows the same workspaces and canvases (D-51).

## M10: Hardening

- Limits: each limit in [architecture.md](architecture.md) section 10 has a test at the limit and at the limit plus one.
- UI tests for the main flows.
- Performance baselines for all budgets.
- Accessibility: VoiceOver labels for every button, Dynamic Type in the chrome.

Acceptance:

1. All performance tests pass against their baselines on the device.
2. Coverage meets TEST-02.
