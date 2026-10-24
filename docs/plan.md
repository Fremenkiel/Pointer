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

Status: done on 2026-10-19. All four acceptance criteria pass, and `make check` passes. The open on the screen has the baseline 274.8 ms (D-62). See [m3-plan.md](m3-plan.md) section 4.

Acceptance:

1. A force quit loses at most 2 seconds of ink (STO-06), shown with an automated crash test.
2. A snapshot shows in the Files app under `Backups`. Copied to a Mac, it opens with `sqlite3` and passes `PRAGMA integrity_check` (D-51).
3. A canvas with 10,000 nodes and 20,000 strokes opens in under 300 ms on the device.
4. All corruption tests in [storage.md](storage.md) section 9 pass.

## M4: Eraser and undo

- `InkEngine`: eraser hit test and `StrokeSplitter`, partial (D-06), with the cut rule of D-65.
- `Model`: `History` and all ink commands. Commands hold `Stroke` values (D-68).
- `Rendering`: the eraser mask and the redraw of a changed area (D-66).
- Undo and redo buttons in the top right corner. Command-Z on a hardware keyboard.
- `CanvasFeature`: the squeeze palette with pen, eraser, undo, and redo (D-63). The current-tool button in the top left opens the same palette (D-64). A tool change takes effect at the next pencil down (D-70).

The tasks are in [m4-plan.md](m4-plan.md).

Status: the code is done on 2026-10-20, and the checks pass except one redo step that took 33.53 ms in one of three device runs. The manual tests with the pencil wait for the product owner. See [m4-plan.md](m4-plan.md) sections 4.7 and 4.8.

The review of 2026-10-20 found acceptance 2 not met (it failed in 2 of 4 device runs) and four defects that M5 builds on. [m4-fix-plan.md](m4-fix-plan.md) lists the fixes.

Status after the fix plan, 2026-10-20: phases 0 to 7 of [m4-fix-plan.md](m4-fix-plan.md) are done on branch `m4-fix`. Acceptance 1 passes. Acceptance 2 passes under D-79: 5 full runs of `PointerDeviceTests` in a row passed, and the slowest erase, undo, and redo of all runs took 30.54 ms (section 5.3 of the fix plan). `make check` passes with the iPad, and all 20 snapshot tests run there without a skip. The product owner ran the manual tests with the pencil of [m4-plan.md](m4-plan.md) section 4.8 on 2026-10-20, and all of them pass. The product owner decided D-80 on the same day. M4 is done, and M5 can start.

Acceptance:

1. Each command passes the apply-then-revert test (TEST-09, D-67).
2. Erase, undo, and redo of 1,000 strokes in one gesture takes under 33 ms per step (D-69, D-75). The goal of 16 ms moves to a later milestone. A Tier A test times `apply` and `revert` of the command. A device test on the iPad Pro 11-inch (M4) in Release times each step. The clock runs from the pencil lift or the button tap until the GPU completes the first frame that holds the result (D-74). The canvas holds the 20,000 strokes of D-56 and 1,000 parallel strokes of 300 points. One eraser line cuts each of the 1,000 strokes in two.

## M5: Text boxes

- Text tool, `UITextView` overlay, glyph atlas (D-29, D-81), move with long press and drag, and delete through a long-press menu (D-89).

The tasks are in [m5-plan.md](m5-plan.md). The product owner decided D-81 to D-91 on 2026-10-20.

Status: done on 2026-10-21 on branch `m5`, and `make check` passes with the iPad. Acceptance 1 passes its device test and the manual test with the pencil (D-90). Acceptance 2 passes: each line lines up within 1 pixel at zoom 0.5, 1, and 4 (D-91). The product owner ran the 10 manual tests of [m5-plan.md](m5-plan.md) section 5.6, and all pass after two fixes. The memory target of the open is 380 MB (D-93). Under D-94, the zoom over the D-56 text can have up to 2 late frames in a full device run. Glyph buffers on the GPU move to a later milestone. M5 is done.

Acceptance:

1. Scribble writes into a text box.
2. Text on the canvas and text in edit mode line up to within one pixel at zoom 0.5, 1, and 4 (snapshot test).

## M6: Cards and navigation

- Card creation (D-08), card previews, open (D-09), up button, pinch-out exit with the minimize animation, navigation path.

The tasks are in [m6-plan.md](m6-plan.md). The product owner decided D-95 to D-106 and D-107 to D-113 on 2026-10-21, and D-115 to D-117 on 2026-10-22.

Acceptance:

1. Open and leave a card with no visible jump (screen recording, frame by frame).
2. A tree of 32 levels below the root canvas works. A card on a canvas of level 32 is refused with a message (D-95).
3. A finger lift above the threshold cancels the pinch-out exit.

Status on 2026-10-22: the three acceptance tests pass on the iPad, and the product owner reported a pass of acceptance 1 and 3 by hand. The product owner decided D-118 and D-119 on the same day. `make check` passes with the iPad. Three items of phase 6 wait for the product owner: the coverage of Rendering cannot be measured, the open of an empty card had 1 late frame in 2 of 5 close runs, and the slowest redo is 13 % above the baseline (m6-plan.md section 6.3.1). D-114 stays open.

Status after the fix plan, 2026-10-22: [m6-fix-plan.md](m6-fix-plan.md) is done on branch `m6-fix`, with the decisions D-120, D-121, and D-122. `make coverage` passes, with Rendering at 86.78 %. A blocked main thread no longer stops the flight of a card. The open of an empty card can still have 1 late frame at the start of its flight, an open item that the product owner accepted. It came in 1 of 5 close runs. The slowest erase, undo, and redo of 5 full runs took 27.15, 21.69, and 24.80 ms. The snapshot of the card menu runs as an XCTest class and passes in full runs (D-124). A pending card joins the canvas at a leave (D-123). The product owner ran the manual tests of section 6.5 of the fix plan on 2026-10-22, and all pass. The late frame of the empty card in full runs stays an accepted open item. The M6 fix plan is done.

Review before M7, 2026-10-22: new device tests prove that each canvas screen and its renderer go away after a leave, and that the steady memory does not grow over 12 opens and leaves (`CanvasLifetimeTests`). The review fixed a workspace switch during an open or a leave, which kept a hidden screen with its renderer and refused every later open (`NavigationCancelTests`). It also fixed a late wake of the render thread that kept the thread and its engine (`RenderThreadLifetimeTests`), and a retain cycle in four test helpers that kept a whole composition per test. In the last two full runs of `PointerDeviceTests`, the only failure was the accepted late frame at place 0 of the open of the empty card. The last run passed 309 of 310 tests, and its slowest erase, undo, and redo took 27.68, 19.48, and 23.38 ms.

## M7: Apple Pencil interactions

- Double tap and hover dot. The squeeze palette comes in M4 (D-63).

The tasks are in [m7-plan.md](m7-plan.md). The product owner decided D-125 to D-131 on 2026-10-22.

Status of phase 0 on 2026-10-22: tasks 0.2, 0.3, 0.4, and 0.5 are done on branch `m7`. A failed open keeps the undo history of the parent. An open or a leave that cannot load its screen ends with a message. A preview render ends when its render thread stops. Each fix has a device test that failed before it. The baseline of task 0.5 is in section 6.2 of the M7 plan: all 314 tests of `PointerDeviceTests` passed. `make check` with the iPad and `make coverage` pass. A build warning in `Rendering`, older than M7, is fixed after a benchmark of three solutions, and D-132 asks how the build can stop such warnings. Task 0.1 is done: PencilKit shows its hover indicator for all three tools (D-127).

Status of phases 1 and 2 on 2026-10-22: tasks 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, and 2.4 are done on branch `m7`. A double tap follows D-130, and a double tap and a squeeze do nothing during a card flight. The hover dot shows above the live canvas, a gray dot for the pen and the text tool and a gray outline circle for the eraser (D-133). A hover sample allocates nothing. `make check` with the iPad passed 345 of 345 tests of `PointerDeviceTests`, and `make coverage` passes. A fix on 2026-10-23 lets the hover recognizer receive the pencil, and the product owner saw the dot work on the iPad. The dot also works inside a card and hides while "Show Hover Preview" is off. The product owner accepted the size and the gray of the dot, so task 2.5 and phase 2 are done. Section 6.8 and 6.9 of the M7 plan hold the results.

Status of phase 3 on 2026-10-23: task 3.1 is done. The live canvas gets a new pen tool only at a pencil down and at rest, so a zoom frame makes 0 allocations instead of 139 (D-131). The product owner decided D-134: the frames of the canvas screen decide this task, because `FrameLoopTests` does not run the canvas code. `make check` with the iPad passed 350 of 350 tests, and `make coverage` passes. Phase 4 passed on 2026-10-23: the product owner reported a pass for acceptance 1 to 4, and the check of the pen width after a zoom found two faults, which commits 436fe7b and 194959c fix (D-135). Phase 5 passed on 2026-10-23: no measure is more than 10 % slower than the baseline, and `make check` with the iPad (356 of 356 tests) and `make coverage` pass. The late frames at the start of a leave are older than M7. The product owner decided D-136 and D-137: a trace now, then expected failures that are not strict, and the rest of the trace in M10. M7 is done. Section 6 of the M7 plan holds the results.

Review after M7, 2026-10-23: a glide frame with an open text edit laid out the whole text again and made up to 218 allocations. It now makes none in Pointer code (`TextEditFrameAllocationTests`). Each `PreviewRenderer` no longer makes the shared readback buffer that only the offscreen preview used, which saves 256 KB of Metal memory for each canvas with a leave. `make check` with the iPad passed 358 of 358 tests, and five alternating pairs showed no change of erase, undo, or redo. Section 6.10 of the M7 plan holds the measures.

Acceptance:

1. Double tap follows D-130 for each value of `preferredTapAction`.
2. Squeeze opens the palette at the pencil tip on Apple Pencil Pro.
3. With an Apple Pencil (USB-C), every feature that does not need tap or squeeze works. The test uses an Apple Pencil Pro with double tap and squeeze set to "Ignore" (D-129).
4. No app action plays a haptic event in Apple Pencil Pro (PEN-06). Drawing plays no haptic event. A system haptic on squeeze is accepted (D-23).

## M8: PDF export

- `Export`: `PDFExporter`, export button, share sheet.

The tasks are in [m8-plan.md](m8-plan.md). The product owner decided D-138 to D-144 on 2026-10-23 and D-145 on 2026-10-24.

Status on 2026-10-24: done on branch `m8`. The export button, the share sheet without a file, the snapshot of a PDF page, and the budgets of D-144 and D-145 are in place. The product owner reported a pass of all 5 manual tests on 2026-10-23, acceptance 1 among them. Acceptance 2 passes with `PDFSnapshotTests`. The [M8 fix plan](m8-fix-plan.md) fixed the causes of three flaky device tests and of the slow save at the end of a snapshot (D-146, D-147). `make check` and `make coverage` pass, and five full runs of `PointerDeviceTests` passed. Section 6 of the M8 plan and of the fix plan hold the results.

Acceptance:

1. The exported PDF opens in Preview on a Mac. Ink stays sharp at 6400% zoom. Text can be selected and searched.
2. A snapshot test compares a rendered PDF page with a reference image: a white page, black ink and text, and no cards.

## M9: Backup

- `BackupFeature`: "Back up now" and restore (D-20). No App Intent (D-14).

The tasks are in [m9-plan.md](m9-plan.md). The product owner decided D-148 to D-165 on 2026-10-24. D-159 moves to M10.

Acceptance:

1. A snapshot from "Back up now" opens with `sqlite3` on a Mac and passes `PRAGMA integrity_check`.
2. A restore from a snapshot gives a library with the same rows.
3. A snapshot restores after the app is deleted and installed again, with a new device ID, and the app shows the same workspaces and canvases (D-51, D-161).

Status on 2026-10-24: done on branch `m9`. All three acceptance criteria pass. The product owner reported a pass of acceptance 1 and acceptance 3 on the iPad, and of the other manual tests of task 5.1. `D56RestoreTests` restores the D-56 library with 0 rows that differ (acceptance 2). "Back up now" and a restore of D-56 stay under the budgets of D-165. `make check` and `make coverage` pass, and five full runs of `PointerDeviceTests` passed, each measure within 10 % of the baseline. Section 6 of [m9-plan.md](m9-plan.md) holds the results.

## M10: Hardening

- Limits: each limit in [architecture.md](architecture.md) section 10 has a test at the limit and at the limit plus one.
- UI tests for the main flows.
- Performance baselines for all budgets.
- Glyph quads of each text box in a GPU buffer that a build reuses (option (b) of D-94, D-105).
- Accessibility: VoiceOver labels for every button, Dynamic Type in the chrome.
- From the review before M7 (D-125, D-131):
  - Trace the late frame at place 0 of the open of an empty card on the render thread with Instruments. Fix it, and remove the expected failure of D-125.
  - Trace the GPU wait of frames 0 to 2 of each leave in Instruments, with the thread states and the display queue (D-137). Fix it, and remove the expected failures of D-137 and the one of D-125 in `FlightStallTests`.
  - Delete the preview file of each canvas that the 30-day purge removes. `PreviewStore.remove(_:)` has no caller.
  - Measure the sets that the release preconditions of `Eraser.command` and `EraseStrokes.init` build at each erase, and move them to `assert` if the cost shows.
  - Read `isLoadingText`, `isLoadingCards`, and `isLoadingPreviews` of `RenderEngine` under one lock, or count the items in transit, so that no wait ends early.
  - Call the completions of a card load and a preview render after their lock, not under it, so that a completion cannot deadlock.
  - From the review after M7: a text-box drag and a card drag make 1 to 2 allocations at each sample, from the array of the moved item and from `RenderInbox.reset()`, which drops the capacity of the edit lists. Keep the lists, and post one item without an array (PERF-01).
  - `CanvasRenderer.deliver(upTo:)` and `deliverCompletions(upTo:time:)` copy their arrays at each handoff, because a slice of the array lives during `removeFirst`.
  - Add allocation tests that drive `PencilTouchObserver`, `handlePan`, and `handlePinch` through UIKit events.
  - The undo of an erase accepts up to `Limits.maxStrokesAfterErase` (D-159).
  - From the review after M8: the open items of sections 3.2 to 3.4 of [review-2026-10-24.md](review-2026-10-24.md) that M9 does not take.
  - Read the contract checks of each Tier A and Tier B package by hand. Each package has an average of exactly 2.00 (CONTRACT-02), so remove checks that test nothing.

Acceptance:

1. All performance tests pass against their baselines on the device.
2. Coverage meets TEST-02.
