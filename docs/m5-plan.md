# M5 work plan: text boxes

This document breaks milestone M5 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on D-15, D-16, D-19, D-29, D-34, D-50, D-57, D-59, D-63, D-64, D-66, D-70, D-76, and D-77.

The M5 plan raised D-81 to D-91 on 2026-10-20. The product owner decided each of them with the recommendation and approved this plan on the same day.

Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03).

## 1. Facts from the code at the start of M5

Checked on 2026-10-20 at commit d2378c2, the newest commit of branch `m4-fix`. Branch `m5` starts there.

1. `Model` has `TextBox` (data-model.md section 7.3). Its initializer checks the origin, the length of 1 to `Limits.maxTextLength` code points, and U+0000 (D-57). It stores no width and no height.
2. `CanvasContent` can add a text box, but it cannot change, move, or remove one. No command handles text boxes. `CommandError` names strokes only.
3. `History` bounds its steps by control points (`heldPointCount`, D-76). A step that holds text holds no points, so the budget does not count text.
4. `LibraryChange.textBox` exists. `Persistence` saves a text box with an upsert of all columns, `is_deleted` included. The load reads the live text boxes into `CanvasContent`. Schema version 1 holds the `text_box` table (D-50), so the recommendations of section 2 need no migration.
5. `Rendering` has no text code. It imports Metal, `Geometry`, `InkEngine`, and `Model`. The committed textures and the eraser mask use `.r8Unorm`. The shader `compositeMaskedFragment` multiplies the committed coverage by `1 - mask`. Thus the eraser hides all content of the committed texture, text included (D-66, effect 3).
6. The only `SpatialGrid` of the renderer holds strokes (architecture.md section 5.6).
7. `CanvasFeature`: `Tool` has the cases `pen` and `eraser`. `ToolPalette` shows each case of `Tool.allCases`. The canvas has a pan, a pinch, and `PencilTouchObserver`. It has no tap and no long-press recognizer. `renderDelta` skips the `.card` and `.textBox` rows. The loaded text boxes are in the content, but nothing shows them.
8. The D-56 content of the open and memory tests holds 5,000 text boxes of 200 characters each, at y 5,000 and below. Nothing draws text yet. Thus the open time and the memory of [m4-fix-plan.md](m4-fix-plan.md) section 5.3 hold no text work. They are 236.3 to 242.7 ms and 235 to 253 MB.
9. `DesignSystem` has no text tool icon. `Limits` has no text width. architecture.md section 7 gives 640 canvas points.
10. `make snapshots` names each snapshot test class. A new snapshot class must join the list.
11. Three document conflicts exist. plan.md M5 says "Core Text texture cache", and architecture.md section 3 lists a "text texture cache". D-29 and architecture.md section 5.4 say glyph atlas (D-81). Architecture.md section 8 lists `ResizeTextBox`, and UNDO-03 lists "resize", but data-model.md section 7.3 stores no size (D-83). Architecture.md section 4.7 has a delete in the long-press menu of a text box, but product-spec.md has no requirement for it (D-89).

## 2. Decisions

[decisions.md](decisions.md) gives the options and the reasons of each question. The product owner chose the recommendation of each on 2026-10-20.

| ID | Question | Decision | Tasks |
|---|---|---|---|
| D-81 | Text renderer: plan.md says "Core Text texture cache", D-29 says glyph atlas | Glyph atlas. plan.md and architecture.md section 3 change their words. | 2.2 |
| D-82 | Text and the eraser mask | A second channel: the committed textures become `.rg8Unorm`, ink in red, text in green | 2.3, 2.4 |
| D-83 | Size of a text box | Width from the longest line, up to 640 canvas points, then wrap. Nothing stored. `ResizeTextBox` leaves architecture.md. | 1.1, 2.1, 3.2 |
| D-84 | Who lays out the text, and characters that SF Mono lacks | Core Text in `Rendering`, with the attributes of the edit view. Fallback glyphs go into the atlas. | 1.1, 2.1, 2.2, 4.2 |
| D-85 | Scale of the edit view | Font size 17 times the zoom, no scale transform. A scale transform only during a pinch. | 3.2, 4.2 |
| D-86 | Undo and redo during an edit | One step per edit. During the edit, undo and redo go to the text view. | 1.2, 3.3 |
| D-87 | The text tool in the palette, and the tool change of D-70 | A third tool in the palette and the button. A tool change ends an edit at once. | 3.1, 3.3 |
| D-88 | Memory bound of text in the undo history | Count each held code point as one point of the D-76 budgets | 1.3 |
| D-89 | Delete of a text box through a long-press menu | Add the menu with "Delete", and add a requirement to product-spec.md | 3.4 |
| D-90 | The test of acceptance 1 (Scribble) | A device test of the conditions that Scribble needs, and a manual test with the pencil as the pass | 4.1 |
| D-91 | The pass rule of acceptance 2 | Lit-pixel bounds and profiles of each line match within 1 pixel | 4.2 |

## 3. How to measure

1. Run each device test on the connected iPad Pro 11-inch (M4), UDID `00008132-000018993E8B801C`, in Release. Never use a simulator (learned rule 1 of `AGENTS.md`).
2. Before each device run, make sure that the iPad is unlocked. `xcrun devicectl device info lockState --device 00008132-000018993E8B801C` must print `passcodeRequired: false`. If it is locked, stop and ask the product owner.
3. Run the Tier A tests on the Mac with `swift test`. Run all of `PointerDeviceTests` on the iPad.
4. A device run varies by several milliseconds. To compare a change, run the build before it and the build after it in alternation, as section 5.2 of [m4-fix-plan.md](m4-fix-plan.md) does. Keep a change that makes a measure slower only with a written reason.
5. An allocation test of a main-thread path uses `AllocationCounter.countMainThread`, because other tests run at the same time.
6. Record each number in section 5. Do not state a result that no run measured.

## 4. Tasks

### Phase 0: decisions and measurement base

#### 0.1 Record the decisions

1. Record the decisions of the product owner in [decisions.md](decisions.md).
2. Change this plan, architecture.md, data-model.md, product-spec.md, and plan.md to match them.

Done when: no document conflicts with a decision, and section 1, item 11 has no open conflict.

Rules: AGENT-04, DOC-06.

#### 0.2 Baseline of the performance tests

1. Run the full `PointerDeviceTests` 3 times in a row on the iPad at the start commit of M5.
2. Record the results in section 5.1. Record the open and the memory of the D-56 canvas, and the three content passes. Record the frame loop tests, the eraser frame, the frame allocations, and the steps of M4 acceptance 2.

Done when: section 5.1 holds 3 runs. Later tasks compare against these runs and against section 5.3 of [m4-fix-plan.md](m4-fix-plan.md).

Rules: PERF-03, D-79.

Status: done. Section 5.1 holds the 3 runs.

### Phase 1: model (Tier A)

#### 1.1 Text style and text box changes

1. Add `TextStyle` to `Model` with named constants: the font size of 17 points at zoom 1 (D-15), and the largest width of 640 canvas points (D-83). Rendering, the canvas, and the export of M8 use them.
2. Add to `CanvasContent`: `replace(_:)` for a changed text box, and `removeTextBox(_:)`. `textBoxes` holds the live text boxes only, as `strokes` does (D-68).
3. A restore uses `add(_:)`, which checks `Limits.maxNodesPerCanvas`.
4. Add to `TextBox` the copies `editing(text:at:)`, `moving(to:at:)`, and `marking(deleted:at:)`, with the checks of the initializer.

Done when: parameterized tests cover 0, 1, `Limits.maxNodesPerCanvas`, and the limit plus one (TEST-06). Each new function that is not private has a test (TEST-02).

Rules: TEST-02, TEST-06, ARCH-06, D-19, D-57, D-83.

Status: done. 9 new tests pass, 83 `Model` tests in total.

#### 1.2 Text box commands

1. Add `AddTextBox`. Its apply adds the box and returns its row. Its revert removes the box and returns the row with `isDeleted = true` and a new `modified`. A redo returns the row with `isDeleted = false`.
2. Add `EditText` with the old and the new `TextBox` values. Each apply and revert sets a new `modified`.
3. Add `MoveNode` for text boxes, with the old and the new origin. M6 extends it to cards.
4. Add `DeleteNode` for text boxes. Its apply sets the tombstone, and its revert clears it.
5. Add `CommandError` cases for a text box that is not live, a text box that is already live, and the node limit.
6. A command checks the content before it changes it. A thrown error leaves the content and the history as they were.

Done when: each command passes the apply-then-revert test of TEST-09 with the live content (D-67). A test of each command makes sure that the returned rows match the content after apply, revert, and a redo. The line coverage of `Model` stays at least 90 %, and its assertion density at least 2.0.

Rules: UNDO-03, TEST-02, TEST-09, CONTRACT-02, D-19, D-67, D-86.

Status: done. 9 new tests pass, 92 `Model` tests in total. The density of `Model` is 2.16. Each command counts the code points of its texts as its held cost (D-88), so task 1.3 adds only the budget tests.

#### 1.3 Text in the memory bound of the history

1. Give each text command a held cost: the code points of the `TextBox` values that it holds (D-88).
2. `History` and `CanvasSessions` count the cost against the budgets of D-76.

Done when: parameterized tests at the budget and the budget plus one pass for text steps (TEST-06). A history of 500 `EditText` steps of 10,000 code points each keeps at most `Limits.maxHistoryPointsPerCanvas` units.

Rules: TEST-06, D-76, D-88.

Status: done. `CanvasSessions` sums `History.pointCount`, so the sessions count text without a change. 2 new tests pass, 94 `Model` tests in total, and the line coverage of `Model` is 91.15 %.

### Phase 2: rendering (Tier B)

#### 2.1 Text layout

1. Add `TextLayout` to `Rendering`. It lays out one text box with Core Text (`CTTypesetter`): SF Mono at the size of `TextStyle`, a fixed line height, and word wrap at `TextStyle.maxWidth` (D-83, D-84).
2. It returns the glyphs of each line with their font, glyph ID, and position in canvas points, and the size of the box.
3. `CanvasRenderer` gives the size of a box to the canvas, for hit tests and the edit view.
4. Add an `OSSignposter` interval around the layout.

Done when: tests cover these cases: a short line, a line past 640 points that wraps at a space, and a word longer than 640 points. Other tests cover an empty line, a trailing new line, and a character that SF Mono lacks. The layout of the 5,000 text boxes of D-56 is timed on the Mac and on the iPad, and section 5.3 holds the times.

Rules: PERF-03, TEST-02, D-15, D-83, D-84.

Status: done. `TextLayout` keeps 9 bytes per glyph: an x, a glyph ID, a line, and a font index. With 25 bytes per glyph, the D-56 open held 29 MB more. The layout of the 5,000 boxes of D-56 takes 59.5 to 61.9 ms on one thread of the iPad. Since D-92 it runs off the render thread at a load, in up to 8 chunks.

#### 2.2 Glyph atlas

1. Add a glyph atlas per scale (D-29, D-81). The scale is the zoom times the display scale, rounded up to the next power of two.
2. Core Text draws each glyph into the atlas once. A glyph has the key: font, glyph ID, and scale.
3. The atlas cache has a byte budget, `RendererConfiguration.glyphAtlasByteBudget`, with a start value of 16 MB. Past the budget, the scale that was used least recently goes first.
4. Add the text pipeline: one quad per glyph, with the glyph offsets in `Float` from the box origin in `Double`, as the strokes do (architecture.md section 5.3).

Done when: tests cover a glyph at two scales, a fallback glyph, and the budget plus one atlas. A frame that uses only cached glyphs makes no allocation in Pointer code (PERF-01, measured as `FrameAllocationTests` does).

Rules: PERF-01, TEST-02, D-29, D-81.

Status: done. A text pass with cached glyphs makes 2 allocations, as many as a bare render pass with one draw. The atlas numbers its fonts, and a table holds the places of the SF Mono glyphs per scale, because a string key per glyph made late frames (task 2.4).

#### 2.3 Text in the committed layer

1. Change the committed textures to `.rg8Unorm`: ink in red, text in green (D-82). The ink pipeline writes red only, and the text pipeline writes green only.
2. The composite takes the larger of `red * (1 - mask)` and `green`. Thus the eraser mask hides ink only, and text stays on top (D-16, D-66).
3. Add a `SpatialGrid` of the text boxes to the renderer.
4. A build draws the strokes and the text boxes in its chunks. Glyph quads count against `instanceBudgetPerFrame`.
5. Add `CanvasRenderer.changeTextBoxes(removing:adding:)`. A text change clears the old and the new bounds in green only and draws the text boxes there again.
6. Add `CanvasRenderer.hideTextBox(_:)`. The canvas hides the box under the edit view (architecture.md section 5.4).
7. The redraw of an erase clears red only.
8. Update architecture.md section 5.2 with the memory of the textures.

Done when:

- Snapshot tests on the iPad (TEST-07, D-77): `text-zoom0.5`, `text-zoom1`, `text-zoom4`, `text-under-eraser-mask` (the text stays under the mask), and `text-move-redraw`.
- The snapshot tests of M2 and M4 give the same images.
- `CanvasMemoryPerformanceTests` stays under 380 MB (D-93).
- `EraserFramePerformanceTests` stays under 3 ms CPU and 4 ms GPU.
- `FrameAllocationTests` stays at the count of a bare Metal frame.

Rules: PERF-01, TEST-07, D-16, D-38, D-66, D-78, D-82.

Status: done. The canvas hides a box under the edit view with `changeTextBoxes(removing:adding:)`, so the renderer needs no `hideTextBox(_:)`. The memory target changed to 380 MB with D-93, after the research of D-92 and D-93. The snapshot names end in `zoom0.5`, `zoom1.0`, and `zoom4.0`.

#### 2.4 Text in the frame budget

1. Add a frame loop test that pans and zooms over the text boxes of the D-56 content.
2. Run the open test of the D-56 canvas, which now draws its text.

Done when: the frame loop test gives 120 fps and 0 late frames. The open of the D-56 canvas stays under 300 ms and is at most 10 % slower than section 5.1. The other frame loop tests are not slower by more than 10 %.

Rules: CAN-05, PERF-03, D-56, D-62.

Status: done. The text part of a build first had no time limit and made late frames (97 and 106 fps). It now uses the build time budget of 2 ms per frame. The pan of the D-56 text still shows uncovered screen in 166 to 179 of 480 frames, a measure that the target does not hold (section 5.3).

### Phase 3: canvas (Tier C)

#### 3.1 Text tool

1. Add `Tool.text` with a new icon token in `DesignSystem` (D-87). The palette and the current-tool button show it.
2. `ToolState` keeps the drawing gesture of PencilKit off for the text tool (D-34).
3. A tool change ends an edit at once (D-87). A tool change during a pencil touch takes effect at the next pencil down (D-70).

Done when: tests of the tool state cover the text tool, and snapshot tests cover the palette and the button with the text tool (TEST-07).

Rules: TOOL-01, TOOL-07, PEN-03, TEST-07, D-34, D-63, D-64, D-70, D-87.

Status: done. The palette shows pen, eraser, text, undo, and redo. The references of the pen and eraser palettes changed, because the palette holds a third tool. The new references come from the iPad.

#### 3.2 Edit view

1. Add the edit view: a `UITextView` (TextKit 2) at the place of the box, above the ink view and below the chrome.
2. Use SF Mono at 17 points times the zoom, the line height of `TextLayout`, zero insets, and zero line fragment padding (D-85).
3. The text is white on a clear background. Allow plain text only: no rich text, no links, no data detectors.
4. The width follows D-83.
5. The edit view follows the camera. During a pinch, it uses a scale transform, and at the end of the pinch it lays out again at the new size (D-85).
6. The edit view refuses text past `Limits.maxTextLength` code points, and a U+0000. It shows the limit message of architecture.md section 10.
7. `PencilTouchObserver` refuses the touches on the edit view.

Done when: a test makes sure that the frame of the edit view equals the box of `TextLayout` at zoom 0.5, 1, and 4. Other tests make sure that pasted rich text becomes plain text, and that the edit view refuses text past the limit with a message.

Rules: TOOL-05, STYLE-03, STYLE-05, D-15, D-57, D-83, D-85.

Status: done. The edit view is as wide as `TextStyle.maxWidth` times the zoom, so that it wraps where the layout wraps. It takes touches only on the box. The first device run found that the style was set only at a zoom change, so at zoom 1 the edit view kept the system font. The style now comes at the first layout of each text.

#### 3.3 Start and end of an edit

1. With the text tool, a pencil tap on empty canvas makes a new box at the tap and starts the edit (TOOL-05). The keyboard opens.
2. With the text tool, a pencil tap on a box starts its edit (D-87).
3. With any tool, a finger tap on a box starts its edit (TOOL-06).
4. A tap outside the box, a tool change, a workspace switch, or the move to the background ends the edit.
5. At the end, the canvas records one step (D-86): `AddTextBox` for a new box with text, `EditText` for a changed box, and `DeleteNode` for a box that ends empty. A new box that ends empty and an unchanged box record no step.
6. During the edit, the undo and redo buttons, the palette, and Command-Z act on the undo manager of the text view (architecture.md section 8).
7. At `Limits.maxNodesPerCanvas`, a tap makes no box and shows the limit message.

Done when: tests cover each start and each end, each kind of step, the node limit, and an undo and a redo of each step. On the iPad, a new box keeps its text after a force quit and a new launch.

Rules: TOOL-05, TOOL-06, UNDO-01, UNDO-02, UNDO-03, STO-06, D-86, D-87.

Status: done in code and in the tests of `TextEditTests`. The check that a new box keeps its text after a force quit is a manual test of section 5.6. The app ends an edit at the move to the background, and the canvas shows the messages through `CanvasDependencies.onMessage`.

#### 3.4 Move and delete

1. A finger long press on a box, then a drag, moves it (CARD-07, D-10). The drag records one `MoveNode` step.
2. A long press without a drag opens a menu with "Delete" (D-89). It records one `DeleteNode` step.
3. A long press on empty canvas does nothing in M5. "New card" comes in M6 (D-08).

Done when: tests cover a move, a delete, and an undo of each. The finger pan of the canvas still works on empty canvas.

Rules: CARD-07, UNDO-03, D-10, D-89.

Status: done. The menu is a `UIEditMenuInteraction` with one destructive action.

### Phase 4: acceptance tests

#### 4.1 Acceptance 1: Scribble writes into a text box

1. Add a device test in `PointerDeviceTests` of the conditions that Scribble needs (D-90). With the text tool, the edit view is an editable `UITextView` and the first responder. The drawing gesture of PencilKit is off. `PencilTouchObserver` refuses touches on the edit view. No delegate of the edit view refuses Scribble.
2. The test inserts text through `UITextInput`, the protocol that Scribble uses for its result. At the end of the edit, the text is in the content, in the rows of the library, and on the canvas.
3. The product owner writes with the pencil into a text box on the iPad. This manual test is the pass of acceptance 1 (D-90).

Done when: the test passes on the iPad, and the product owner reports a pass of the manual test.

Rules: TOOL-05, D-77, D-90.

#### 4.2 Acceptance 2: text lines up with the edit view

1. Add a snapshot test in `CanvasFeatureSnapshotTests` (D-77). It shows a text box of 3 lines, one of them wrapped, at zoom 0.5, 1, and 4.
2. For each zoom, it renders the canvas image without the edit view and the image of the edit view at the same camera.
3. It compares the two images with the rule of D-91.
4. A second case uses a line with characters that SF Mono lacks (D-84).
5. Make the reference images on the iPad, and look at each image before you commit it (TEST-07).
6. Add the test class to `make snapshots`.

Done when: the test passes on the iPad at each zoom, and no snapshot test skips.

Rules: TEST-07, D-77, D-84, D-85, D-91.

### Phase 5: close of M5

1. The line coverage of each Tier A package is at least 90 % (TEST-02). The assertion density of each package is at least 2.00 (CONTRACT-02).
2. The documents in `docs/` match the code (DOC-06). Each new folder is in the context map of `AGENTS.md` (AGENT-07).
3. Run the full checklist of [code-of-code.md](code-of-code.md) section 5, with `make check` on the iPad (AGENT-05).
4. Run all snapshot tests on the iPad. Each snapshot test must run, with no skip.
5. Run the full `PointerDeviceTests` 5 times in a row (D-79). Record the M2, M3, and M4 performance tests and M4 acceptance 2. Each test must be at most 10 % slower than section 5.3 of [m4-fix-plan.md](m4-fix-plan.md).
6. Fill in section 5, and update the M5 status in [plan.md](plan.md).
7. List the manual tests for the product owner in section 5.6.

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, TEST-02, TEST-07, PERF-03, D-79.

## 5. Results

### 5.1 Baseline

Measured on 2026-10-20 on the iPad Pro 11-inch (M4) in Release, at commit beb3608 in a separate worktree. Run 1 built the tests, and runs 2 and 3 used the same build. Each run passed 172 tests with 0 failures and 0 skips.

| Run | Open of D-56, median / slowest | Memory of the open, held / peak | Content pass 20,000 / 200,000 / 200,000 handwriting | Eraser frame CPU / GPU median | Erase / undo / redo, slowest |
|---|---|---|---|---|---|
| 1 | 237.9 / 243.6 ms | 253 / 284 MB | 36 / 115 / 170 ms | 0.11 / 0.30 ms | 25.50 / 28.05 / 29.65 ms |
| 2 | 238.9 / 246.3 ms | 252 / 284 MB | 36 / 113 / 171 ms | 0.11 / 0.27 ms | 25.52 / 29.07 / 27.18 ms |
| 3 | 241.5 / 250.2 ms | 254 / 254 MB | 36 / 112 / 171 ms | 0.11 / 0.29 ms | 27.41 / 28.95 / 27.72 ms |

The memory and the open of D-56 in these runs hold the error of the test that D-93 found: the canvas of the test host changes the memory of the process by up to about 50 MB. With the corrected test, M4 takes 312 to 315 MB and 251.3 to 256.1 ms (D-93).

In each run, the 6 frame loop tests ran at 120 fps with 0 late frames and 0 uncovered frames. The frame allocations were 15 against 15 of a bare Metal frame. `FrameRenderer.apply` made 16, 2, and 1 allocations for the erase, the undo, and the redo of the D-69 content.

### 5.2 Model

| Item | Target | Result |
|---|---|---|
| Node limit tests of `CanvasContent` and `AddTextBox` (TEST-06) | pass | passes at 0, 1, the limit minus one, and the limit |
| Apply-then-revert of `AddTextBox`, `EditText`, `MoveNode`, `DeleteNode` (TEST-09) | live content equal | passes |
| History budget with text steps (D-88) | at most the budget | passes: at the budget and the budget plus one, and 500 edits of 10,000 code points keep 200 steps |
| Line coverage of `Model` (TEST-02) | at least 90 % | 91.15 % after task 1.3 |
| Assertion density of `Model` (CONTRACT-02) | at least 2.00 | 2.16 after task 1.2 |

### 5.3 Rendering

| Item | Target | Result |
|---|---|---|
| Layout of the 5,000 text boxes of D-56, iPad, one thread | none set, recorded | median 59.5 to 61.9 ms |
| Snapshots `text-zoom0.5`, `text-zoom1.0`, `text-zoom4.0`, `text-under-eraser-mask`, `text-move-redraw` | match | pass with the new references from the iPad |
| Frame allocations against a bare Metal frame | equal | 15 and 15. A text pass with cached glyphs: 2 and 2 of a bare pass. |
| Memory of the open of D-56 | under 380 MB (D-93) | 347 to 350 MB in 3 runs with the corrected test (M4: 312 to 315 MB). Before D-92 and the corrected test: held 282 MB, peak 314 MB. |
| Eraser frame, CPU / GPU median | under 3 ms / 4 ms | 0.11 / 0.28 ms |
| Frame loop over text, pan and zoom from zoom 0.25 | 120 fps, 0 late frames | pass: 120.0 fps and 0 late frames in the pan, 119.7 to 120.0 fps and 0 to 1 late frames in the zoom. Known gap: the pan shows uncovered screen in 166 to 179 of 480 frames. |
| Open of D-56 with text | under 300 ms, at most 10 % over section 5.1 | pass: median 246.1 to 257.3 ms with the corrected test, against 251.3 to 256.1 ms at M4 (D-93). Before D-92: 273.6 ms. |

### 5.4 Canvas

| Item | Target | Result |
|---|---|---|
| Tool state and snapshots with the text tool | pass | pass |
| Edit view frame at zoom 0.5, 1, and 4 | equal to the layout box | pass, within 0.001 points |
| Start, end, steps, and limits of an edit | pass | pass |
| Move and delete | pass | pass |

### 5.5 Acceptance

| Item | Target | Result |
|---|---|---|
| Acceptance 1, device test of the Scribble conditions (D-90) | pass | not run |
| Acceptance 1, manual test with the pencil | a pass, reported by the product owner | not run |
| Acceptance 2 at zoom 0.5, 1, and 4 (D-91) | within 1 pixel | not run |

### 5.6 Close

Not run yet.
