# M4 fix plan: defects, performance, and memory before M5

This document lists the work that fixes the findings of the M4 review of 2026-10-20. Each task has a measured reason, a fix, and a target that the fix must reach. M5 starts after all tasks of phases 0 to 7 are done or rejected by the product owner. The acceptance criteria of M4 stay in [plan.md](plan.md).

Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03).

## 1. How the numbers were measured

The review ran on 2026-10-20 at commit a59d233 (branch `m4`). Two kinds of measurement were used:

1. The iPad Pro 11-inch (M4) in Release, through `PointerDeviceTests`. This is the only device for acceptance numbers (learned rule 1 of `AGENTS.md`).
2. Release builds on a Mac with an M4 Pro, for the Tier A packages. The `Rendering` numbers come from a copy of the package that builds for Mac Catalyst without `InkView`. The frames had no drawable, so these are CPU times only.

The allocation counts come from the `AllocationCounter` of the tests (the `malloc_logger` hook) or from a malloc counter. In earlier M4 runs, the iPad was about 2.8 times slower than the Mac. A Mac number therefore shows a direction, not a device result.

## 2. What the review found

### 2.1 State of M4 on the iPad

| Check | Result on 2026-10-20 |
|---|---|
| Mac parts of `make check` | pass: build, analyze, format, lint, layers, density, self-test, plist, and 29, 68, 13, and 84 Tier A tests |
| `PointerDeviceTests`, full run | 28 of 29 XCTest cases and 98 of 98 Swift Testing tests pass |
| M4 acceptance 2, full run | fails: undo median 27.31 ms, slowest 33.37 ms |
| M4 acceptance 2, alone, 3 runs | pass, pass, fail: redo median 34.16 ms, slowest 34.54 ms |
| Rendering snapshot tests (`InkImageTests`, `RedrawTests`, `EraserMaskTests`) | not run since 2026-10-19. Commit b6e529f changed the redraw after the last reference images. |
| SwiftUI snapshot tests | not run since 2026-10-19. They skip on the device (D-59). |

Acceptance 2 failed in 2 of 4 runs on this day. In one run, the median of the redo was over the budget. Thus acceptance 2 is not met.

### 2.2 Defects

| ID | Finding | Evidence |
|---|---|---|
| F-01 | `SQLiteLibraryRepository.content(of:)` reads only the database, not the pending rows. A load within the save throttle of 1 s gives old content. | A scratch test saved stroke 1, then sent stroke 2, an erase record of stroke 1, and a text box. The load gave stroke 1 only. |
| F-02 | `AppComposition.openCanvas` makes the new `CanvasViewController` before the old one saves its session in `willMove(toParent:)`. A switch loses the undo steps of the visit. A tap on the current workspace always loses them. | Code order in `PointerApp/AppComposition.swift:151-176`. `HistoryTests.switchKeepsHistory` uses the other order. |
| F-03 | After F-01 and F-02, an undo can fail for good: `History.undo` throws `CommandError` at each try, and the button stays on. In Debug, `assert(skipped == 0)` in `CanvasViewController.swift:77` stops the app. | Scratch test: 3 undo calls threw, and `undoSteps.count` stayed 2. |
| F-04 | `InkEncoder.encodePass` reserves `blockCount` entries for a stroke, but a clipped stroke can give more entries. The precondition of `DrawListRing.append(contentsOf:)` then stops the app. | A 1-block stroke that leaves and enters the area gave 6 entries. With a ring of 4 entries, the redraw trapped. |
| F-05 | `CommittedLayer.redraw` and `addStrokes` loop "a full draw list continues in another pass". `ring.used` resets only in `beginFrame`, so later passes in the same frame draw nothing. In Release, ink is lost. | 40 strokes with a ring of 16 gave the cursors 16, 16, 16, 16, 16. |
| F-06 | `PencilTouchObserver` also gets the pencil touches on the undo and redo buttons, because their host view is inside `canvasView`. With the eraser, a pencil tap on Redo can record a new erase and clear the redo list. | Static: `CanvasViewController+History.swift:111-116`, and `PencilTouchObserver.swift` has no `shouldReceive` filter. Not reproduced on the iPad. |
| F-07 | `EraseStrokes.area` (`InkEngine/Eraser.swift:52-58`) does not cover the whole change of a part. Under D-65 and D-72, the curve also changes 1 to 2 segments past the cut. Old pixels stay outside the redraw. | Largest change outside the area: 0.079 points at a control point spacing of 2, 0.61 at 10, 2.05 at 40. |
| F-08 | A crash during the pre-migration snapshot leaves `Pointer-pre-migration-v1.sqlite.partial`. `VACUUM INTO` then fails at each launch, before `removePartialSnapshots` runs. | 3 of 3 launches failed with `sqlite(code: 1, "output file already exists")` with the v2 test migration. |
| F-09 | A failed `saveNow()` cancels the scheduled save and schedules no new one. | After one failure and 5 s of timer time: 1 row pending, no scheduled save. |
| F-10 | A cancelled save timer can still run and set `scheduledSave = nil` for a newer task. | Static: `SQLiteLibraryRepository+Saving.swift:54-61`. Not reproduced. |
| F-11 | The canvas sends rows with one `Task { await repository.send }` per step. The order of the tasks at the actor has no guarantee. An undo and a redo out of order keep the wrong erase record. | Static. Not reproduced. |
| F-12 | `AppViewController.showMessage` drops a message while a popover is shown. | Static: `PointerApp/AppViewController.swift:99-104`. |
| F-13 | A load that a newer switch replaced still runs to its end. | Static: `AppComposition.swift:138-149`. |
| F-14 | If a tombstone is missing, `EraseStrokes.revert` in Release sends `.stroke(stroke)`. The stored erase record then stays live. | Static: `EraseStrokes.swift:108-109`. |

### 2.3 Performance

| ID | Finding | Evidence |
|---|---|---|
| P-01 | `CommittedLayer.redraw` searches the whole edit area, not the part inside the texture. Each stroke it finds is made resident and encoded. | 200,000 strokes at zoom 2: 20,100 found, 210 touch the texture. Frame CPU 13.7 ms against 0.1 ms on the Mac. |
| P-02 | `SpatialGrid.removeEntry` makes 5 to 6 hash lookups and about 6 allocations per cell. `insert` uses `cells[cell, default: []]`. | One erase of the D-69 content: 14,056 allocations in `FrameRenderer.apply`, 12,048 of them in the grid. In-place access: 0 allocations, 1,000 removals 1.00 ms to 0.39 ms. |
| P-03 | `SpatialGrid.forEachItem` and `report` are not `@inlinable`, so other modules run them as unspecialized generic code. | Query of the D-69 area: 0.057 ms to 0.015 ms. Query of 21,000 items: 0.86 ms to 0.20 ms. |
| P-04 | `Stroke.init` uses `pointwiseMin` and `pointwiseMax` on `SIMD2<Float>`, which do not vectorize. `StrokeSplitter.finish` builds each part with `Stroke.init` again. | 297,000 points: 0.90 ms to 0.21 ms. 2,000 parts: 0.95 ms to 0.36 ms. The D-56 load: 77 ms to 64 ms. |
| P-05 | The hit test makes 46 allocations per stroke: 4 `map` arrays in `nearBounds`, a `bands.filter` per segment, and array growth. `refine` tests all bands. | 46 to 6 allocations per stroke. Serial hit test of 1,000 strokes: 3.70 ms to 2.40 ms. |
| P-06 | `renderDelta` in `CanvasViewController+History.swift:69-89` makes one dictionary lookup per row. The arrays grow without `reserveCapacity`. | A redo of the D-69 erase has 2,000 tombstone rows. One lookup took about 1 µs on the iPad (m4-plan.md section 4.6). |
| P-07 | `EraseStrokes.apply` and `revert` check each stroke with one lookup and then change it with a second one. | 3,000 extra lookups per step of the D-69 content. |
| P-08 | `FrameRenderer` adds a completed handler and a `DispatchQueue.main.async` hop for each handoff frame. The callback only calls `onStepDrawn`, which only tests set. | Static: `FrameRenderer.swift:276`, `CanvasRenderer.swift:50-56`. |
| P-09 | `requestSave()` after `send(rows)` repeats work, because `send` already schedules the save. | Static: `CanvasViewController+Eraser.swift:48-49`, `+History.swift:63-64`. |
| P-10 | The candidates of an erase are filtered by `path.bounds` twice. | Static: `CanvasViewController+Eraser.swift:69` and `Eraser.swift:42`. |
| P-11 | ID and clock values decode through `Data` and `Array`. A clock value adds a second `Data` and `Array`. | Stroke ID and clock decode of the D-56 load: 11.4 ms to 1.0 ms. Load 77 ms to 62 ms. With P-04: 49 ms. |
| P-12 | `adoptSessionRecords` builds its dictionary without `reserveCapacity`. | 500,000 records: 98.7 ms to 54 ms. 90,000 records: 16.6 ms to 12.5 ms. |

### 2.4 Memory

| ID | Finding | Evidence |
|---|---|---|
| M-01 | `History` has a step bound but no memory bound. `CanvasSessions` keeps up to 1,000 sessions. | 500 steps, each an erase of 1,000 whole strokes of 300 points: 2,519 MB of malloc memory. |
| M-02 | The session erase records grow without a bound. Records of steps that `History` dropped stay. | 500,000 records take 96 MB. |
| M-03 | `CanvasSessions` keeps the session of a deleted workspace. The stale session entry of the shown canvas shares the `History` buffers, so the first step after a reopen copies up to 500 steps. | Static: `WorkspaceSelectorModel.delete` does not tell the app. |
| M-04 | `StrokeStore.blockSpacings` and `blockBends` grow without a bound. A reused slot with more blocks appends a new range and never reuses the old one. | 200 strokes over 30 rounds of erase, undo, and new strokes: 1,163 live blocks, list size 3,626 to 58,031, with no plateau. |
| M-05 | `StrokeStore.releaseRemovals` keeps `points[slot]` until a new stroke takes the slot. | The points of a removed 5,000-point stroke were still alive after 20 frames. |
| M-06 | The eraser mask texture always exists. architecture.md section 5.2 does not count it. | Computed: 16.1 MB on the 11-inch iPad, 22.7 MB on the 13-inch iPad. |
| M-07 | The eraser sample lists of `EraserTool` and `EraserMask` reserve 1,024 samples, but `EraserPath.maxSamples` is 16,384. A gesture longer than about 4 s grows them in the per-sample path and on the render thread. | Static: `EraserTool.swift:8`, `EraserMask.swift:16, 47, 61`. |
| M-08 | `SlabAllocator` allocates a free list for each slab assignment and frees it at the release. | Static: `SlabAllocator.swift:135, 142`. |
| M-09 | `CommittedLayer.redraw` allocates the `targets` array in each redraw frame. | Frame allocations 22 to 21 (undo) and 27 to 26 (erase) without it. |

### 2.5 Clean-up

| ID | Finding |
|---|---|
| C-01 | Dead code: `DrawListRing.append(_ entry:)` and `DrawListRing.write(_:at:)` for one entry have no caller. |
| C-02 | Misplaced doc comments: the doc of `runStep` sits on `area(of:)` in `CanvasViewController+History.swift:35-37`. `CanvasRenderer.swift:225-226` has two doc lines for one function. `CanvasRenderer.swift:202-203` and `FrameRenderer+Image.swift:6-7` say that the handoff comparison uses `renderImage`, but only tests call it. |
| C-03 | `CanvasViewController.add(_:)` has `@discardableResult` and no caller uses the value. |
| C-04 | `CanvasFeature` lists `Export` and `Persistence` as dependencies, and `WorkspaceFeature` lists `Persistence`. No source file imports them. |
| C-05 | `keyCommands` builds two `UIKeyCommand` objects at each query. `shouldRecognizeSimultaneouslyWith` builds a `Set` at each call. |
| C-06 | `PencilTouchObserver` fetches `coalescedTouches(for:)` for each move, also with the pen, where only the last location is used. |
| C-07 | `.claude/worktrees/` is not in `.gitignore`. |

### 2.6 Document drift

| ID | Document | Drift |
|---|---|---|
| D-01 | m4-plan.md section 3.8 | Says the test fails at 16 ms. The code uses 33 ms (D-75). |
| D-02 | architecture.md section 4 | Says the eraser reads touches in `touchesBegan` and the other touch methods. The code uses `PencilTouchObserver`. |
| D-03 | data-model.md, architecture.md section 13 | Say the renderer gets the IDs of the changed strokes. `CanvasRenderer.change(removing:adding:area:)` takes `Stroke` values and an area. |
| D-04 | data-model.md | Says the canvas controller holds the `History`. `CanvasSessions` in `PointerApp` holds it. |
| D-05 | architecture.md section 9, storage.md | Say each canvas has one grid with strokes, text boxes, and cards. The only grid is the stroke grid of the renderer. |
| D-06 | architecture.md section 12 | Names an `XCTOSSignpostMetric` test of the frame time while you draw. No such test exists. |
| D-07 | architecture.md section 3 | Says `DesignSystem` holds shared small views. It holds tokens only. |
| D-08 | architecture.md section 10 | `Limits.strokeOverlapPoints`, `Eraser.minimumChunk`, and `Eraser.maxChunks` are not in the table. |
| D-09 | architecture.md section 4 | Says the palm radius is "to be found in M2". The code uses 30 points. |
| D-10 | architecture.md section 5.2 | Two committed textures take "about 45 MB". The mask adds a third texture (M-06). |
| D-11 | `AGENTS.md`, `Makefile` | `make test` and `make snapshots` use a simulator, but learned rule 1 bans the simulator. D-77 decides this. |
| D-12 | `AGENTS.md` context map | `PersistenceCrashHelper/`, the `Resources/` folders of `CanvasFeature` and `WorkspaceFeature`, and `PointerApp/Assets.xcassets/` are missing. The map says each package has `Tests/`, but `Export`, `DesignSystem`, and `BackupFeature` have none. It says `Persistence` holds restore, which comes in M9. |
| D-13 | decisions.md, introduction | Names the deciders only up to D-61. |
| D-14 | plan.md M4 status | Names only the redo step and the manual tests as open. |

The questions of M5 (for example the text box size, the text renderer, and the undo during an edit) are not part of this plan. They wait until this plan is done.

## 3. Decisions for the product owner

The product owner decided four questions on 2026-10-20. [decisions.md](decisions.md) records them.

1. D-76: the undo history has a budget of 4,000,000 points per canvas and 16,000,000 points for all sessions (M-01, M-02).
2. D-77: the snapshot tests move into `PointerDeviceTests` and compare against reference images made on the iPad (section 2.1, D-11).
3. D-78: the eraser mask texture exists only while the eraser is the tool (M-06).
4. D-79: acceptance 2 passes with 5 full device runs in a row, each step under 33 ms (section 2.1).

## 4. Tasks

### Phase 0: measurement base

1. Change `EraseUndoPerformanceTests` so that it logs the median and the slowest time of each of the three steps, not only of the step that fails. Keep the assertion.
2. Run the full `PointerDeviceTests` 3 times on the iPad. Record the three steps of each run in section 5.1 as the baseline of this plan.
3. Add a malloc count of `FrameRenderer.apply` for one erase, one undo, and one redo of the D-69 content to `PointerDeviceTests`. Record the counts in section 5.1. The review measured 14,056 per edit on the Mac.

4. Move the snapshot tests into `PointerDeviceTests` (D-77). This covers `InkImageTests`, `RedrawTests`, `EraserMaskTests`, and the SwiftUI snapshot tests of `CanvasFeature` and `WorkspaceFeature`. Put the reference images into the test bundle. Remove the skip on the device. Make the reference images on the iPad at commit a59d233, before any fix of this plan, and look at each image before you commit it.
5. Change `make snapshots` and `make test` so that they use the iPad, `id=00008132-000018993E8B801C`, through a `DEVICE` variable. Update the commands and the context map of `AGENTS.md`, and the `Makefile` comments that name D-59.

Done when: section 5.1 holds 3 device runs with all three steps, and the allocation counts. All snapshot tests run and pass on the iPad, and none of them skip.

Rules: PERF-03, TEST-07, D-59, D-69, D-74, D-77.

### Phase 1: defects that M5 builds on

Write the failing test of each task first (TEST-03). Commit the test and the fix together.

#### 1.1 The load includes the pending rows (F-01)

- If the pending set is not empty, save its rows at the start of `SQLiteLibraryRepository.content(of:)`, before the read.
- If that save fails, throw `ModelError.storageFailed`. Do not load stale content.
- Add a Tier A test: save stroke 1, send stroke 2, an erase record of stroke 1, and a text box, and then load. The load holds stroke 2 and the text box, and not stroke 1.

Done when: the test passes and all 84 `Persistence` tests pass.

Rules: STO-06, TEST-03, D-30.

#### 1.2 A switch keeps the session of the current visit (F-02, F-03)

- If the shown canvas has the same `CanvasID`, return early from `AppComposition.openCanvas`.
- Make the shown canvas save its session before the new `CanvasViewController` is made. Add a public `endSession()` to `CanvasViewController` and call it before the new init. Keep the call in `willMove(toParent:)` for other paths, and make a second call do nothing.
- Change `HistoryTests.switchKeepsHistory` so that it builds the second controller before the first one leaves, as the app does.
- Add a test: erase, reopen the same canvas in the app order, and undo. The undo button is on, and the undo brings the stroke back.

Done when: both tests pass in `PointerDeviceTests` on the iPad, and the old test order also still passes.

Rules: UNDO-02, D-12, TEST-03.

#### 1.3 The draw list cannot overflow (F-04, F-05)

- In `InkEncoder.encodePass`, stop before an entry that does not fit into `ring.remaining`. Count the clipped entries of a stroke before you append them, or check inside the run closure.
- In `CommittedLayer.redraw`, keep the strokes that did not fit, with the area, for the next frame. Clear the area only once.
- In `CommittedLayer.addStrokes`, keep the slots that did not fit for the next frame. Attach the handoff only to the frame that draws its last stroke, so the live stroke stays until the ink is in the texture.
- Remove the loops that expect room in a second pass of the same frame.
- Add tests with a ring of 4 entries: a clipped stroke with 6 entries, 40 strokes in a redraw, and 40 strokes in a handoff. Each stroke shows in the texture after the next frames, and nothing traps.

Done when: the new tests pass. The snapshot `redraw-remove-middle` on the iPad gives the same image.

Rules: TEST-03, TEST-07, D-28, D-66.

#### 1.4 The pencil observer ignores the buttons (F-06)

- Add `gestureRecognizer(_:shouldReceive:)` to `PencilTouchObserver`. It accepts a touch on `canvasView`, on `inkView`, and on the views inside `liveCanvas`. It refuses all other touches.
- Add a test: with the eraser, a pencil touch on the redo button starts no erase and leaves the redo list as it was.

Done when: the test passes on the iPad.

Rules: TOOL-04, UNDO-01, TEST-03.

#### 1.5 The erase area covers the whole change (F-07)

- In `EraseStrokes.area`, add the bounds of the first 3 and the last 3 control points of each part. Also add the bounds of the matching points of the old stroke. Add half the width.
- Also add the full bounds of each removed stroke that leaves no part, as D-71 drops short parts.
- Add a Tier A test on random content: the curve of each part and of the old stroke differs by at most 0.01 points outside the area.

Done when: the test passes at control point spacings of 2, 5, 10, 20, and 40 points. Phase 3 measures the cost of the larger area on the iPad.

Rules: D-65, D-66, D-71, D-72, TEST-03.

#### 1.6 A revert with a missing tombstone throws (F-14)

- In `EraseStrokes.revert`, check for all needed erase records before the first change. If one is missing, throw a `CommandError`, as `apply` does.
- Add a test that reverts a step with a missing record. The content and the history stay as they were.

Done when: the test passes, and the apply-then-revert tests of TEST-09 pass.

Rules: TEST-09, D-67, D-68.

### Phase 2: save and app robustness

#### 2.1 A partial pre-migration snapshot does not block the launch (F-08)

- Call `LibraryMaintenance.removePartialSnapshots(in:)` at the start of `SQLiteLibraryRepository.open(snapshot:)`, before `openConnection`.
- Add a test: put a `.partial` file of the pre-migration name in place, and open with the v2 test migration. The open passes.

Done when: the test passes 3 times in 3 runs.

Rules: STO-06, GIT-04, TEST-03, storage.md section 9.

#### 2.2 A failed save is tried again (F-09, F-10)

- In `saveNow()`, call `scheduleSave()` before it throws `.storageFailed`.
- If `Task.isCancelled` is true after the sleep, return from the timer task of `scheduleSave()`.
- Add a test: one failed `saveNow()`, then the timer time. The row is saved.

Done when: the test passes.

Rules: STO-06, TEST-03.

#### 2.3 Rows reach the repository in order (F-11)

- Replace the one-task-per-step sends of `CanvasViewController` with one ordered channel per canvas: an `AsyncStream` of row lists and one consumer task that calls `repository.send` in order.
- At the leave of the canvas, end the consumer task.
- Add a test: 100 alternating undo and redo steps. The last stored erase record of each stroke matches the content.

Done when: the test passes, and `testEraseUndoRedoOfOneThousandStrokes` is not slower by more than 10 %.

Rules: STO-06, PERF-02, D-30.

#### 2.4 Messages show while a popover is open (F-12)

- In `AppViewController.showMessage`, present from the top presented controller. If that controller is being dismissed, show the message after the dismissal.
- Add a test: open the palette, then send `rowsSkipped`. The alert shows.

Done when: the test passes on the iPad.

Rules: STO-06, TEST-03, storage.md section 9.

#### 2.5 A newer switch cancels the older load (F-13)

- Keep the task of `openCanvas` in `AppComposition`. Cancel it at the next switch.
- Check `Task.isCancelled` before `content(of:)` and before the renderer is made.

Done when: a test of three quick switches makes one `CanvasRenderer` only.

Rules: WS-02, PERF-02.

### Phase 3: speed of erase, undo, and redo

After each task, run `testEraseUndoRedoOfOneThousandStrokes` alone 3 times on the iPad. Record the three steps in section 5.2. If a change makes a step slower, do not keep it.

#### 3.1 The redraw stays inside the texture (P-01)

- In `CommittedLayer.redraw`, cut the area to `target.canvasRect` plus the margin. If the result is empty, skip the target. Use the cut area for the grid query and the clip.
- Add a test with 200,000 handwriting strokes at zoom 2 and an area of the whole canvas. The redraw finds only the strokes that touch the texture.

Done when: the test passes, and the snapshot `redraw-remove-middle` gives the same image.

Rules: PERF-01, D-66.

#### 3.2 The grid changes cells in place (P-02, P-03)

- In `SpatialGrid.removeEntry` and `insert`, find the cell once with `cells.index(forKey:)` and change `cells.values[index]` in place. Remove an empty cell with `cells.remove(at:)`.
- Mark `forEachItem`, `cell(containing:)`, `report`, and `CellRange.contains` `@inlinable`, as commit aad6475 did for `remove`.

Done when: 1,000 removals make 0 allocations in a Tier A test. The Tier A benchmark of 1,000 removals and of the D-69 query is at least 2 times faster than before. The allocation count of phase 0 task 3 falls by at least 10,000 per edit.

Rules: PERF-01, PERF-03.

#### 3.3 Faster stroke bounds (P-04)

- In `Stroke.init` and `StrokeSpline.hullBounds`, use scalar `min` and `max` per coordinate instead of `pointwiseMin` and `pointwiseMax`.
- Add `Stroke.renamed(id:created:)`, which copies the bounds. Use it in `StrokeSplitter.finish`.
- Add a test of `renamed` (TEST-02). The bounds of a stroke stay equal to the bounds that the old code gives.

Done when: the tests pass. The split of the D-69 content on the Mac is at least 30 % faster.

Rules: TEST-02, PERF-03.

#### 3.4 Fewer allocations in the hit test (P-05)

- Compute `nearBounds` in one loop, without `map`.
- Pass the hull of the segment to `isCovered` and `refine`, and test only the bands whose bounds touch it. Remove the `bands.filter` array.
- Reserve capacity in `EraserPath.bands` and `StrokeSpline.segments(near:)`.
- Compare the covered ranges of the old and the new code on random content. They must be equal.

Done when: the hit test makes at most 6 allocations per stroke, and the covered ranges are equal.

Rules: PERF-01, D-65.

#### 3.5 The renderer change comes from the step (P-06, P-07)

- In `runStep`, take the removed and the added strokes from the command: for an undo of `EraseStrokes`, remove the parts and add the removed strokes. A redo does the reverse. `AddStroke` follows the same pattern. Keep the walk over the rows only for other command types.
- In `EraseStrokes.apply` and `revert`, check and change each stroke with one lookup.

Done when: the tests of the canvas history pass, and the Tier A timing of `apply` and `revert` is not slower.

Rules: UNDO-02, D-68.

#### 3.6 No work for test hooks and no repeated work (P-08, P-09, P-10)

- If the edit asks for a completion, register the completed handler and the main-queue hop. Otherwise, register nothing.
- If a test sets `onStepDrawn`, pass `onCompleted`. Otherwise, pass `nil`.
- Remove `requestSave()` after `send(rows)`.
- Filter the candidates of an erase by the path bounds in one place only.

Done when: all canvas tests pass, and `EraseUndoPerformanceTests` reads the end of a step in the same way as before (D-74).

Rules: AGENT-02, PERF-02.

#### 3.7 Acceptance 2 after phase 3

Run the full `PointerDeviceTests` on the iPad 5 times in a row (D-79). Record each run in section 5.2.

Done when: in each of the 5 runs, the slowest erase, undo, and redo are under 33 ms. If it does not pass, stop and report the times to the product owner.

Rules: D-69, D-74, D-75, D-79.

### Phase 4: memory bounds

#### 4.1 The history has a memory bound (M-01, M-02)

- Add `Limits.maxHistoryPointsPerCanvas` (4,000,000) and `Limits.maxHistoryPointsInSessions` (16,000,000) to `Limits` and to architecture.md section 10 (D-76).
- Let `History` count the points of its steps and drop the oldest steps past its budget. Let `perform` return the dropped steps.
- Let `CanvasSessions` count the points of all sessions. Past its budget, drop the oldest steps of the least recently used session first.
- Remove the session erase records of the strokes in the dropped steps.
- Add parameterized tests at the bound and the bound plus one (TEST-06).

Done when: the tests pass. 500 steps of the M-01 content keep at most 4,000,000 points in one history, and the sessions keep at most 16,000,000 points.

Rules: UNDO-03, TEST-06, D-12, D-76.

#### 4.2 Sessions follow the workspaces (M-03, P-12)

- At the open of a canvas, take its session out of `CanvasSessions`, so the shown canvas is its only owner.
- Remove the session of a deleted workspace.
- Reserve capacity in `adoptSessionRecords`.

Done when: a test deletes a workspace and finds no session for its canvas. A test makes sure that the first step after a reopen does not copy the history.

Rules: D-12, WS-03.

#### 4.3 The block lists of the store stay bounded (M-04, M-05)

- In `StrokeStore`, keep the free block ranges by size and reuse them for new strokes. As an alternative, compact the lists after the dead entries outnumber the live entries. Choose the simpler one that meets the target.
- At the release of a slot, set `points[slot]` to one shared placeholder.
- Add a test of 30 rounds of erase, undo, and new strokes. The list size stays under 2 times the live blocks. A weak reference to the points of a removed stroke is nil after the release frames.

Done when: both tests pass, and the M2 and M3 performance tests are not slower by more than 10 %.

Rules: PERF-01, D-28.

#### 4.4 The eraser mask follows D-78 (M-06)

- When the eraser becomes the tool, make the mask texture. When another tool becomes the tool, drop it (D-78). A tool change takes effect at the next pencil down (D-70), so make the texture at the tool change, not at the touch.
- Update architecture.md section 5.2 with the memory of the textures with and without the mask.

Done when: `CanvasMemoryPerformanceTests` and `EraserFramePerformanceTests` pass, and the first eraser sample is not later than before. A test makes sure that no mask texture exists while the pen is the tool.

Rules: D-66, D-78.

#### 4.5 No growth in the per-sample and per-frame paths (M-07, M-08, M-09)

- Reserve `EraserPath.maxSamples` once in `EraserTool` and `EraserMask`. Clear the lists with `removeAll(keepingCapacity: true)`.
- In `SlabAllocator`, keep the free list storage at the release, and fill it again at the next assignment.
- In `CommittedLayer.redraw`, draw the front texture and the build target without a temporary array.

Done when: a gesture of 16,384 samples makes no allocation in Pointer code after its first sample. `FrameAllocationTests` passes.

Rules: PERF-01.

### Phase 5: the load

#### 5.1 IDs and clock values decode in place (P-11)

- Add `uuid(at:)`, `timestamp(at:)`, `bind(uuid:at:)`, and `bind(timestamp:at:)` to `SQLiteStatement` in its `+Unsafe` file (SAFE-09).
- Use the byte-count constants of `ValueCodec`, not the literals 16 and 28.
- Keep the error texts, so the corruption tests pass as they are.

Done when: all `Persistence` tests pass. The Tier A load of the D-56 content is at least 30 % faster on the Mac with phase 3 task 3. The open of the D-56 canvas on the iPad (D-62) is not slower.

Rules: SAFE-05, SAFE-09, STYLE-03.

### Phase 6: clean-up

Do each item as its own small commit.

1. Remove the dead code of C-01.
2. Fix the doc comments of C-02.
3. If no caller needs the return value of C-03, remove it and its `@discardableResult`.
4. Remove the unused package dependencies of C-04. Run `make layers`.
5. Keep the key commands in a stored property, and compare the gesture recognizers with `===` (C-05).
6. Fetch the coalesced touches only while an erase runs (C-06).
7. Add `.claude/worktrees/` to `.gitignore` (C-07).

Done when: `make check` passes with the iPad.

Rules: AGENT-02, DOC-01, DOC-04, SAFE-03.

### Phase 7: documents and close

1. Fix the document drift of section 2.6. Phase 0 task 5 already fixes item D-11.
2. Run the snapshot tests on the iPad. Update the reference images only for a change that this plan explains, and say which change in the commit.
3. Run the full checklist of [code-of-code.md](code-of-code.md) section 5.
4. Run the M2 and M3 performance tests on the iPad. No test is more than 10 % slower than the values of [m4-plan.md](m4-plan.md) section 4.8.
5. Run acceptance 2 with 5 full runs in a row (D-79). Record the runs in section 5.3.
6. Update the M4 status in [plan.md](plan.md).

Done when: each step passes. The manual tests of [m4-plan.md](m4-plan.md) section 4.8 still wait for the product owner, and this plan does not replace them.

Rules: AGENT-05, DOC-06, TEST-07, PERF-03.

## 5. Results

### 5.1 Baseline

Measured on 2026-10-20 on the iPad Pro 11-inch (M4) in Release, with the source code of a59d233 and the test changes of phase 0. Run 1 built the tests. Runs 2 and 3 used the same build. Each step has 5 rounds. The clock follows D-74.

| Run | Erase median / slowest (ms) | Undo median / slowest (ms) | Redo median / slowest (ms) | Acceptance 2 | Other failures |
|---|---|---|---|---|---|
| 1 | 24.14 / 30.22 | 24.89 / 25.92 | 25.80 / 29.53 | pass | none |
| 2 | 25.10 / 28.11 | 28.08 / 30.25 | 26.78 / 30.73 | pass | `testEvictionWithSixteenMegabyteArena`: slowest 0.551 ms, budget 0.5 ms |
| 3 | 24.74 / 29.24 | 25.17 / 28.50 | 23.40 / 34.22 | fail (redo) | none |

The empty change of each run had a median of 8.05 to 8.39 ms. Its first round took 155 to 167 ms, because it includes the first frames after the load. The main-thread call of an erase took 11.7 to 16.4 ms, and of an undo or a redo 4.1 to 9.0 ms.

Each full run had 30 XCTest cases and 121 Swift Testing tests, against 29 and 98 in the review. Phase 0 added `EditAllocationTests`, the Rendering snapshot tests, and `WorkspaceFeatureTests` to `PointerDeviceTests`.

Allocations of `FrameRenderer.apply` for the D-69 content (`EditAllocationTests`), the same in all 4 runs except the first erase:

| Edit | Allocations |
|---|---|
| Erase | 14,897 (14,903 in the first run) |
| Undo | 14,750 |
| Redo | 14,884 |

The snapshot tests: all 20 ran on the iPad and passed, none skipped. The new reference images came from the iPad. Four of them (`curve-zoom0.25`, `eraser-mask`, `redraw-remove-middle`, `zigzag-zoom2`) were byte-equal to the images of the simulator.

### 5.2 Phase 3

Each row is one run of `testEraseUndoRedoOfOneThousandStrokes` alone on the iPad in Release, 5 rounds per step, median / slowest in ms. The start values come from 3 runs after phases 1 and 2 (commit 0b9ec40, with the fix of the erase area).

| Point | Run | Erase | Undo | Redo |
|---|---|---|---|---|
| Start of phase 3 | 1 | 29.38 / 33.68 | 28.26 / 28.84 | 23.24 / 32.76 |
| Start of phase 3 | 2 | 24.57 / 29.97 | 26.95 / 29.37 | 25.09 / 31.66 |
| Start of phase 3 | 3 | 27.98 / 30.03 | 25.80 / 32.12 | 24.53 / 30.05 |
| After 3.1 | 1 | 24.63 / 31.77 | 27.09 / 28.48 | 26.92 / 32.02 |
| After 3.1 | 2 | 29.87 / 31.52 | 26.48 / 28.75 | 20.12 / 27.71 |
| After 3.1 | 3 | 21.61 / 32.75 | 26.87 / 30.03 | 24.63 / 27.57 |

Notes:

- Task 3.1: the redraw of the whole canvas at zoom 2 with 200,000 handwriting strokes lists 36 strokes, the strokes that touch the texture plus its margin. Before, it listed the strokes of the whole area.
- Phases 1 and 2 had two regressions that the device runs showed. They are fixed before phase 3: the erase area of task 1.5 took the whole stroke for a part end at an old stroke end (about 10 ms per step, commit 0b9ec40), and the observer filter of task 1.4 leaked each closed canvas (open of D-56 305.6 ms, commit 54facdc).

### 5.3 Close

To be filled in by phase 7.
