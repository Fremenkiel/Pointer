# M4 work plan: eraser and undo

This document breaks milestone M4 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on D-06, D-12, D-30, D-34, and D-63 to D-71. The product owner decided D-63 to D-71 on 2026-10-19. Do the tasks in the order of section 3.

## 1. Facts from the code at the start of M4

1. `InkEngine` is empty. `Model` has no commands and no `History`. `Limits.maxHistoryDepth` exists.
2. `Persistence` already saves erase records. `EraseRow.upsert` updates `modified` and `is_deleted` of an existing record. A save writes strokes before erase records, because of the foreign key. The pending set keeps one row per ID, so a burst of undo and redo steps writes each row once.
3. `CanvasRenderer` can only load and add strokes. `StrokeStore.remove(_:frame:)` exists but has no public caller. `CommittedLayer` draws new strokes into the front texture, or runs a full build in chunks.
4. `CanvasViewController.isEditingEnabled` uses `drawingGestureRecognizer.isEnabled` to mean "the library can save" (D-70).
5. `PointerApp` makes a new `CanvasViewController` at each workspace switch. A history that lives in the controller dies at the switch, but D-12 keeps the history of each canvas while the app runs.
6. `AppClock` holds the `StrokeFactory` with the one `HybridClock` of the app and the ID source.

## 2. Decisions

All questions of M4 have a decision. No task waits for the product owner.

| ID | Decision | Task |
|---|---|---|
| D-63 | A squeeze of the pencil opens the tool palette | 3.7 |
| D-64 | A button in the top left shows the current tool and opens the same palette | 3.7 |
| D-65 | A part keeps the control points between its cuts and gets the curve point at each cut as its new end | 3.2 |
| D-66 | A mask texture while the eraser moves, a redraw of the changed area at the lift and at each undo and redo | 3.3, 3.4 |
| D-67 | The apply-then-revert test compares the live content | 3.1 |
| D-68 | Commands hold `Stroke` values, and `strokes` holds the live strokes only | 3.1 |
| D-69 | Acceptance 2 is a Tier A test of the command and a device test from the lift to the first frame | 3.2, 3.8 |
| D-70 | A tool change takes effect at the next pencil down. `isEditingEnabled` gets its own value. | 3.5 |
| D-71 | Drop parts shorter than the pen width. An erase can go past the stroke limit. | 3.2, 3.5 |

## 3. Tasks

### 3.1 Commands and history (Tier A)

1. Add the protocol `CanvasCommand` and the typed error `CommandError` of [data-model.md](data-model.md) section 9. `apply` and `revert` also return the changed rows as `[LibraryChange]`, so the canvas sends them to the repository without a second pass.
2. Add `remove(_:)` and `restore(_:)` for strokes to `CanvasContent`, and the session erase records that go with them. A restore can go past `Limits.maxStrokesPerCanvas` only for the parts of an erase (D-71).
3. Add `AddStroke`. Its revert removes the stroke and writes an erase record. A redo sets `isDeleted = true` on that record (D-68).
4. Add `EraseStrokes` with the removed strokes and the new parts as `Stroke` values. Its revert follows [data-model.md](data-model.md) section 7.5.
5. Add `History`: an undo list and a redo list, at most `Limits.maxHistoryDepth` steps, the oldest step dropped first. A new command clears the redo list (architecture.md section 8).
6. Add a test helper that compares the live content of two `CanvasContent` values (D-67).

Done when: each command passes the apply-then-revert test of TEST-09. A second test makes sure that each erase record after a revert is a tombstone. A parameterized test covers a history of 0, 1, 500, and 501 steps (TEST-06). Line coverage of `Model` stays at least 90 %.

Requirement and rules: UNDO-02, UNDO-03, TEST-02, TEST-06, TEST-09, D-12, D-30, D-67, D-68.

Status: done on 2026-10-19 in commit 652326a. 66 `Model` tests pass, and the line coverage of `Model` is 91.92 %. The task made these choices inside the decisions:

- `AddStroke` holds all strokes of one pen path, so a path that the converter splits gives one step.
- A command checks the content before it changes it. A thrown `CommandError` leaves the content and the history as they were.
- A first apply returns the new stroke rows. A redo returns only the changed erase records, because the stroke rows exist.
- A second erase of a stroke keeps the time of its first erase, because the stored row keeps it too (`EraseRow.upsert`).
- The undo of an erase fails at the stroke limit only if it adds more strokes than it removes. An undo that shrinks the canvas never fails.
- After the undo of an erase, the records of the removed strokes are tombstones, and the parts have live records. The test of D-67 makes sure that a stroke is live exactly when its record is a tombstone.

### 3.2 Hit test and stroke split (Tier A)

1. Add the hit test to `InkEngine`. It takes the eraser path in canvas space, the radius in canvas units, and a stroke. It returns the curve parameters where the curve enters and leaves the circles. The test of a segment includes the half width of the stroke.
2. Add `StrokeSplitter`. It makes one part for each range of the curve outside the circles, with the cut rule of D-65. The new end point gets the force and the time of the curve at the cut.
3. Drop a part whose curve is shorter than the pen width (D-71).
4. Each part gets a new `StrokeID` and the `created` value of the clock. The width and the canvas stay the same as in the old stroke.
5. Add a Tier A test that times `apply` and `revert` of an `EraseStrokes` with 1,000 strokes cut in two (D-69).

Done when: these tests pass. A cut in the middle of a stroke leaves two parts. A cut at an end leaves one part. A path that misses the stroke leaves it as it is. A path over the whole stroke leaves no part. A stroke of one sample, which stores the point twice, goes away whole. A test measures the largest distance between a part and the old curve. It is at most half the distance from the new end point to the dropped control point (D-72). A part shorter than the pen width is dropped. The timing test records its result in section 4. Line coverage of `InkEngine` is at least 90 %, and its assertion density is at least 2.0.

Requirement and rules: TOOL-04, TEST-02, TEST-05, CONTRACT-02, D-06, D-26, D-65, D-69, D-71.

Status: done on 2026-10-19 in commits 40c0cba and 07c8562, and `make check` passes. The first test found that the bound of one sixth of D-65 fails near a control point, by up to 2.4 times. The product owner decided D-72: the cut rule stays, and the bound is half the distance. Each target now passes. The task made these choices inside the decisions:

- The eraser covers a circle at each sample and the band between neighbor samples, so a fast pencil leaves no gap.
- A curve point is covered if its distance to the eraser path is less than the radius plus half the stroke width.
- The hit test finds the segments near the path with one pass of outcodes over the points. It samples only those segments and refines each cut with 14 bisection steps.
- The size of an eraser gesture has the bound `EraserPath.maxSamples`, equal to `Limits.maxPointsPerStroke`.

### 3.3 Remove strokes and redraw an area (Tier B)

1. Add a public call to `CanvasRenderer` that removes strokes and adds strokes in one change, with an `onPresented` callback. The renderer uses it for an erase, an undo, and a redo.
2. In `CommittedLayer`, clear the changed rectangle of the front texture with a scissor rectangle. Then draw the strokes that the `SpatialGrid` finds there (architecture.md section 5.2, D-66). A build that runs takes the change too.
3. Add an `OSSignposter` interval around the redraw.

Done when: a snapshot test draws three crossing strokes, removes the middle one, and compares the image with a reference (TEST-07). The other two strokes keep every pixel in the cleared rectangle. A test removes a stroke during a build, and the finished build does not show it.

Requirement and rules: UNDO-02, TEST-07, D-38, D-66.

Status: done on 2026-10-19 in commit 113d4c1, and `make check` passes. The snapshot test `redraw-remove-middle` passes. Its comparison with a fresh build of the two other strokes gives a largest difference of at most 1 in each pixel of the texture. A stroke removed after the first chunk of a build is not in the finished build, for each of the three strokes. The task made these choices inside the decisions:

- The inbox holds one ordered list of edits for handoffs, erases, undo steps, and redo steps. Thus an add and its undo in the same frame keep their order.
- The clear of the area is a triangle with a clear pipeline and a scissor rectangle, because the load action of Metal clears the whole texture.
- The scissor rectangle has a margin of 3 pixels for the anti-aliased edge.
- `RedrawTests.swift` uses `Snapshot.swift`, so it stays out of `PointerDeviceTests`, as `InkImageTests.swift` does.

While this task ran, it raised D-73: D-71 lets an erase pass the stroke limit, but the load, the canvas, and the renderer stop at it. Task 3.5 waits for D-73.

### 3.4 Eraser mask (Tier B)

1. Add a mask texture of the format `.r8Unorm` and the size of the committed texture.
2. Add the eraser samples to the inbox of the renderer. Each frame, the render thread stamps a circle of the eraser radius for each new sample into the mask.
3. The composite pass hides the ink under the mask (architecture.md section 5.2).
4. The change of task 3.3 clears the mask at the lift.

Done when: a snapshot test stamps an eraser path across a stroke and compares the image with a reference. A frame with 4 new samples stays inside the frame budget of architecture.md section 12. The display link pauses again after the gesture.

Requirement and rules: TOOL-04, FEEL-04, TEST-07, D-42, D-66.

Status: done on 2026-10-19 in commit b19fa13, and `make check` passes. The snapshot test `eraser-mask` passes: the ink under the path is hidden, and the ink beside it stays. A frame with 4 new samples takes 0.12 ms CPU and 0.41 ms GPU (medians) on the iPad, against 3 ms and 4 ms (section 4.4). After the end of the gesture, the renderer needs no frame, and the frame loop can sleep. The task made these choices inside the decisions:

- The renderer converts each sample from view space to canvas space with the camera of the frame. The mask uses the mapping of the front texture. If the front texture changes during a gesture, the next frame clears the mask and stamps all samples again.
- Each stamp is a capsule from the sample before, the same shape as the band of the hit test of task 3.2.
- The composite pass uses a second pipeline with the mask only while the gesture has stamps, so a frame without an eraser reads no mask.
- `CanvasRenderer.endErase()` ends the mask. The eraser tool calls it together with the change of task 3.3, so one frame shows the result and drops the mask.
- The sample lists go back and forth between the inbox and the frame, so a frame allocates no list (PERF-01).
- The budget test is an XCTest in `PointerDeviceTests`, because the simulator gives no device drawables and no real GPU times. `EraserMaskTests.swift` uses `Snapshot.swift`, so it stays out of `PointerDeviceTests`.

### 3.5 Eraser tool (Tier C)

1. Add the tool state of the canvas: pen or eraser. The text tool comes in M5.
2. Give `isEditingEnabled` its own stored value. The drawing gesture recognizer is on only while the tool is the pen and editing is allowed. The eraser also stops while editing is not allowed (D-70).
3. A tool change takes effect at the next pencil down (D-70).
4. With the eraser, read the `.pencil` touches directly (D-34). Send each sample to the renderer for the mask.
5. At the lift, run the split of task 3.2 and apply one `EraseStrokes`. Send the change to the renderer and the rows to the repository, and ask for a save (D-30).

Done when: unit tests of the tool state cover the change at the next pencil down and the editing flag. On the iPad, an erase across handwriting cuts the strokes, and the parts stay after a new launch.

Requirement and rules: TOOL-01, TOOL-04, STO-06, D-30, D-34, D-70, D-71.

Status: the code is done in commit eeb2a5e, and `make check` passes. Three tests of the tool state cover a change while the pencil is up, a change during a touch, and the editing flag for each tool. Four tests of the canvas cover an erase that cuts a stroke in two, the first sample after a tool change, a cancelled gesture, a pen touch, a library that cannot save, and the drawing gesture of PencilKit. The erase sends 2 stroke rows and 1 erase record and asks for one save. The check with the pencil on the iPad waits for the product owner (task 3.9). D-73 is still open: an erase at the stroke limit still stops the renderer. The task made these choices inside the decisions:

- `PencilTouchObserver` gives each pencil sample, the coalesced samples included, to the canvas. It already sees every pencil touch next to the drawing gesture of PencilKit.
- A cancelled touch ends the mask and changes nothing.
- The candidates of the split come from one pass over the bounds of the live strokes, not from a grid. The renderer holds the only grid on its render thread, and a second grid in the canvas would add time to the open of D-56.
- The split runs inside the signpost interval `EraseSplit`.
- The steps go through a `History` of the canvas controller. Task 3.6 moves it to the app.

### 3.6 Undo and redo (Tier C)

1. Keep one `History` for each canvas while the app runs (D-12). `PointerApp` holds the histories by `CanvasID`, so a workspace switch keeps them.
2. Each handoff of a pen stroke adds one `AddStroke` step. A stroke that the converter splits at `Limits.maxPointsPerStroke` gives one step.
3. Add undo and redo buttons in the top right corner (UNDO-01), with tokens from `DesignSystem`. A button is off while its list is empty.
4. Add Command-Z and Shift-Command-Z through `UIKeyCommand`.
5. An undo or a redo sends its change to the renderer and its rows to the repository, and asks for a save.

Done when: a snapshot test covers the buttons on and off (TEST-07). On the iPad, a stroke, an erase, two undo steps, and two redo steps give the expected canvas. The history of a workspace stays after a switch to another workspace and back.

Requirement and rules: UNDO-01, UNDO-02, UNDO-04, TEST-07, D-12.

Status: the code is done in commit 881b061, and `make check` passes. Three snapshot tests cover the buttons with both on, both off, and undo on with redo off. Four tests of the canvas cover a stroke, an erase, two undo steps, and two redo steps, the history after a switch to a new screen of the same canvas, the key commands, and the bound of the sessions. The device run of these tests is part of task 3.9. The task made these choices inside the decisions:

- `PointerApp` holds `CanvasSessions`. A `CanvasSession` keeps the `History` and the erase records of the session of one canvas. A new load reads no erase record, so without them an undo after a switch would put a stroke back on the screen while its stored erase record stays live. `CanvasContent.adoptSessionRecords(_:)` takes them back at the open of a canvas.
- The sessions have the bound `Limits.maxWorkspaces`, because each canvas of M4 belongs to a workspace. Past the bound, the least recently used session goes.
- An undo or a redo finds its renderer change from its rows: a new stroke row or a tombstone adds a stroke, and a live erase record removes one.
- The buttons use the new tokens `Icon.undo`, `Icon.redo`, and `Color.chromeDisabled`. Their snapshots are in the new folder `Tests/CanvasFeatureSnapshotTests` of `PointerDeviceTests`, as the selector snapshots are (D-59). `make snapshots` runs them.

### 3.7 Squeeze palette and current-tool button (Tier C)

1. Add the tool palette with pen, eraser, undo, and redo (PEN-03, D-63). A tap on a tool selects it and closes the palette.
2. Install one `UIPencilInteraction`. A squeeze opens the palette with the rules of architecture.md section 4.5.
3. Add the current-tool button in the top left corner, next to the workspace selector. A finger tap opens the same palette under the button (D-64).
4. Use tokens from `DesignSystem`. The app plays no haptic event (PEN-06).

Done when: snapshot tests cover the palette and the button for each tool (TEST-07). On the iPad, a squeeze opens the palette at the pencil tip, and a tap on the button opens it under the button.

Requirement and rules: TOOL-07, PEN-03, PEN-05, PEN-06, TEST-07, D-23, D-63, D-64.

Status: the code is done in commit c0553fa, and `make check` passes. Four snapshot tests cover the palette and the button for the pen and for the eraser. Four tests cover the squeeze settings "Ignore" and "Run Shortcut", the anchor at the tip and at the last pencil location, the phase of the squeeze, and a pick in the palette. The squeeze and the button on the iPad wait for the product owner (task 3.9). The task made these choices inside the decisions:

- The palette is a popover with an arrow. At a squeeze, it points at the tip. At a tap on the button, it opens under the button. A tap outside closes it.
- Undo and redo in the palette keep it open, so that several steps need one squeeze.
- The canvas gives the button as `toolButton`, and `AppViewController` places it to the right of the workspace selector. A switch of the workspace swaps the button with the canvas.
- The pencil interaction handles the squeeze only. The double tap of PEN-01 stays in M7.
- The new tokens are `Icon.pen` (`pencil.tip`) and `Icon.eraser` (`eraser`).

### 3.8 Acceptance tests

1. Acceptance 1: the tests of task 3.1 for `AddStroke` and `EraseStrokes`.
2. Acceptance 2: a performance test in `PointerDeviceTests` on the iPad Pro 11-inch (M4) in Release (D-69). The canvas holds the 20,000 strokes of D-56 and 1,000 parallel strokes of 300 points. One eraser line cuts each of the 1,000 strokes in two. The clock runs from the lift, or from the undo or redo call, to the end of the first frame that shows the result. Each step must take under 16 ms. Record the baseline in section 4 (PERF-03).
3. A device test changes the tool to the eraser and erases at once. The first sample cuts the stroke under it (D-34, D-70).

Done when: both acceptance criteria pass, and the results are in section 4.

Status: blocked, because the iPad is locked. The test of acceptance 2 is in commit 59ba4cc, and `make check` passes. On 2026-10-19, `xcodebuild` stopped with "Unlock Kevin's iPad to Continue". Acceptance 1 passes with the tests of task 3.1. Item 3 is the test `EraserToolTests.firstSample`, which runs on the simulator and in `PointerDeviceTests`. The test of acceptance 2 makes these choices inside D-69:

- The canvas holds the content in memory without a library, because the save runs off the main actor with its own budget of 50 ms.
- The camera has zoom 0.5, so the 1,000 strokes, 1.5 points apart, fit on the screen. The eraser line has 261 samples.
- The end of a step is the presented callback of its first frame on the main actor. The test runs 5 rounds and fails if the slowest step of a kind takes 16 ms or more.

### 3.9 Close of M4

1. The line coverage of `Model` and `InkEngine` is at least 90 % (TEST-02).
2. The documents in `docs/` match the code.
3. Run the full checklist of [code-of-code.md](code-of-code.md) section 5.
4. Run the M2 and M3 performance tests again on the iPad. No test is more than 10 % slower.
5. The product owner tests the eraser, the undo, the redo, the squeeze, and the button with the pencil on the iPad.

## 4. Results

### 4.1 Commands and history

| Item | Target | Result |
|---|---|---|
| Apply-then-revert test of `AddStroke`, 1 and 3 strokes (TEST-09) | live content equal | passes |
| Apply-then-revert test of `EraseStrokes`, 0 and 2 parts (TEST-09) | live content equal | passes |
| Erase records after the revert (D-67) | tombstones of live strokes | passes |
| History of 0, 1, 500, and 501 steps (TEST-06) | at most 500 steps | passes |
| Line coverage of `Model` (TEST-02) | at least 90 % | 91.92 % |
| Assertion density of `Model` (CONTRACT-02) | at least 2.0 | 2.24 |

### 4.2 Hit test and stroke split

| Item | Target | Result |
|---|---|---|
| A cut in the middle, a cut at an end, a miss, a whole stroke, a dot | 2, 1, 0 changes, 0, 0 parts | passes |
| A part shorter than the pen width | dropped | passes |
| Largest change of a part against the old curve (D-72) | at most 1/2 of the distance to the dropped point | passes. The first measurement against 1/6 failed by up to 2.4 times. |
| Largest change of a part in absolute terms, control points 1.7 to 3 points apart | none set | 0.012 to 0.043 canvas points |
| Line coverage of `InkEngine` (TEST-02) | at least 90 % | 91.40 % |
| Assertion density of `InkEngine` (CONTRACT-02) | at least 2.0 | 2.05 |

Timing of the D-69 content: 1,000 parallel strokes of 300 points, one eraser line of 2,001 samples that cuts each stroke in two. On the Mac, the release values are the median of 3 runs, and the debug values come from 1 run:

| Step | Debug build | Release build |
|---|---|---|
| Split: hit test and parts of 1,000 strokes | 215 ms | 6.0 ms |
| `apply` of `EraseStrokes` | 2.2 ms | 0.83 ms |
| `revert` of `EraseStrokes` | 2.4 ms | 0.88 ms |
| `apply` again (redo) | 2.2 ms | 0.69 ms |

The Tier A test fails if `apply`, `revert`, or the redo takes 16 ms or more. The split runs at the lift, so the device test of task 3.8 counts it in the step of the erase.

### 4.3 Remove strokes and redraw an area

| Item | Target | Result |
|---|---|---|
| Snapshot `redraw-remove-middle` (TEST-07) | matches | passes |
| The two other strokes after the redraw, against a fresh build of them | every pixel kept | largest difference at most 1 of 255 |
| A stroke removed during a build, for each of the 3 strokes | not in the finished build | passes |

### 4.4 Eraser mask

| Item | Target | Result |
|---|---|---|
| Snapshot `eraser-mask` (TEST-07) | matches | passes |
| A frame with 4 new samples, iPad Pro 11-inch (M4), Release, 20,000 strokes of the M2 content, 60 frames | under 3 ms CPU, under 4 ms GPU | CPU median 0.12 ms, largest 0.24 ms. GPU median 0.41 ms, largest 3.01 ms. |
| The frame loop after the gesture | can sleep | passes |

New baselines (PERF-03): the eraser frame, CPU median 0.12 ms and GPU median 0.41 ms.

