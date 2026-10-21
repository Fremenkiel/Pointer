# M6 work plan: cards and navigation

This document breaks milestone M6 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on D-08, D-09, D-10, D-12, D-16, D-18, D-53, D-66, D-82, D-88, D-92, D-93, D-94, and D-95 to D-106.

This plan raised D-107 to D-113 on 2026-10-21 (section 2.2). The product owner decided each of them with the recommendation on the same day.

Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03).

## 1. Facts from the code at the start of M6

Read on 2026-10-21 at commit 7284f4e, the newest commit of `main`. Branch `m6` starts there. Paths are under `Packages/` unless they start with `PointerApp/`.

### 1.1 Model and Persistence

1. `Card` (`Model/Sources/Model/Card.swift`) holds `id`, `meta`, `canvasID` (the parent), `frame`, `title`, and `sortKey`. The initializer refuses a card that is its own canvas, a frame under 64 by 48, a title over 120 code points, and U+0000. `childCanvasID` gives `CanvasID(id)`.
2. `Card` has no copies. `TextBox` has `editing(text:at:)`, `moving(to:at:)`, and `marking(deleted:at:)` (`TextBox.swift`, lines 49 to 95).
3. `CanvasContent` holds `cards` and counts cards and text boxes against `Limits.maxNodesPerCanvas`. For cards it has only `add(_:)`. For text boxes it also has `replace`, `removeTextBox`, `change(to:at:)`, `revive`, and `bury`.
4. `MoveNode` and `DeleteNode` hold a `TextBox` only. Their comments say "Cards join in M6". No `AddCard` and no `RenameCard` exist. `CommandError` has no card cases.
5. `LibraryChange.card` exists. The repository saves card rows with an upsert and loads the live cards of a canvas. Schema version 1 holds the `card` table, so M6 needs no migration. No `canvas` table exists: the ID of a child canvas is the ID of its card.
6. `LibraryRepository` has no function for one card, for the parents of a card, or for a depth.
7. `DeviceState.navigationPath` holds at most 32 card IDs (`DeviceState.swift`, line 20). `DeviceStateStore.save(lastWorkspace:navigationPath:)` stores it. The app writes `[]` and never reads it (`PointerApp/AppComposition.swift`, line 156, and `AppComposition+Lifecycle.swift`, line 62).
8. The 30-day purge walks 32 card levels below a deleted workspace or card (`LibraryMaintenance.swift`, lines 104 to 113).
9. The D-56 content (`CanvasFeature/Tests/CanvasFeatureTests/D56Library.swift`) holds 5,000 cards of 100 by 70 points with the titles "Card N", all with the sort key "V". The renderer draws none of them, so the open time and the memory of D-93 hold no card work.

### 1.2 Rendering

1. Rendering has no card code. The canvas loads strokes and text boxes into the renderer and never loads `content.cards`.
2. The committed textures are `.rg8Unorm`: ink in red, text in green (`InkResources.swift`, line 8). They have twice the drawable size (D-47).
3. `compositeFragment` gives `mix(background, 1, max(r, g))`. `compositeMaskedFragment` gives `max(r * (1 - mask), g)` (`Shaders.metal`, lines 200 to 259). `CompositeUniforms` has no fade weight.
4. A text change clears green only in its scissor rectangle and draws the text boxes there again (`CommittedLayer+Text.swift`, lines 62 to 110). After M6, green also holds cards. A green clear must then draw cards and text again, and the order of the two does not matter, because both blend with `max`.
5. The glyph pipeline blends with `max` and writes green only. A fragment that returns `coverage * gray` with the same pipeline state writes a gray border.
6. `TextStore` lays out the text after the first frame, in up to 8 chunks on a global queue (D-92). The render thread merges the result.
7. `renderImage(of:textBoxes:camera:viewSize:displayScale:)` is the only image capture. It is for tests only, blocks its thread, and makes a new store, arena, and atlas for each call. No code writes or reads a PNG.
8. No source file imports ImageIO. BUILD-03 needs a decision for a new framework, also from Apple (D-107).
9. The main actor only posts to the inbox of `RenderEngine`. The render thread runs a `CAMetalDisplayLink`. Off-main work posts its result back to the inbox, as the text load does.
10. A new `CanvasRenderer` takes 0.34 to 0.37 ms (m5-plan.md section 5.7).

### 1.3 CanvasFeature and PointerApp

1. `AppComposition.openCanvas(of:)` (`PointerApp/AppComposition.swift`, line 166) opens the root canvas of a workspace. The app has no other canvas: no path, no parent, no child.
2. Each canvas screen has its own `CanvasRenderer` and Metal view. `show` removes the old screen and inserts the new one (`PointerApp/AppViewController.swift`, line 22).
3. The canvas has a pan, a pinch, and `PencilTouchObserver`. The text recognizers are `pencilTap`, `fingerTap`, and `longPress` (`TextEditing.swift`, lines 45 to 49). No double-tap recognizer exists. No code calls `require(toFail:)`.
4. The long press begins only on a text box (`CanvasViewController+TextMove.swift`, line 32). The menu of a text box is a `UIEditMenuInteraction` with one "Delete".
5. `CameraController` is a struct with the rubber band `minZoom * (raw / minZoom)^0.35`, the spring back, and the deceleration. It has no animation to a given camera, and `endPinch` always springs back.
6. `renderDelta(of:)` skips `.card` rows (`CanvasViewController+History.swift`, lines 106 to 126).
7. `CanvasSessions.capacity` is `Limits.maxWorkspaces`, with the comment "In M4 each canvas belongs to a workspace" (`CanvasSessions.swift`, line 22). A workspace delete drops only the session of the root canvas.
8. `DesignSystem` has no up icon, no card icon, and no `Color.cardBorder`. The String Catalog of the canvas has no "New card", "Rename", or "Up".
9. The workspace rename is a SwiftUI `.alert` with a `TextField` (`WorkspaceSelectorView.swift`, lines 40 to 44).
10. `make snapshots` names 8 snapshot classes (`Makefile`, lines 48 to 58). A new snapshot class must join the list.

## 2. Decisions

### 2.1 Decided before this plan

The product owner decided D-95 to D-106 on 2026-10-21 with the recommendations. The documents already match them.

| ID | Decision | Tasks |
|---|---|---|
| D-95 | The root canvas is level 0. A path holds at most 32 cards. "New card" on a canvas of level 32 is refused with a message. | 1.3, 4.1, 5.2 |
| D-96 | Cards go into the green channel with the text: a gray border, title glyphs from the atlas, and a sampled preview | 3.1, 3.2 |
| D-97 | A gray 8-bit PNG per child in `Caches/Pointer/previews/`, written at the leave. The renderer reads it off the main actor after the first frame. Decoded cache of 8 MB, sizes 128, 256, and 512. | 2.1, 3.3, 3.4, 4.8 |
| D-98 | The card covers the screen, the parent ink and text fade, the child loads during the animation, then a crossfade of 0.1 s | 3.5, 4.5, 4.6 |
| D-99 | An open by double tap, up button, or pinch-out uses the cameras of CARD-03 and CARD-04. The stored camera is for launch and workspace switch only. | 4.4 |
| D-100 | The double tap begins only on a card that no text box covers. The finger tap waits for it only there. | 4.3 |
| D-101 | A new card is a quarter of the screen width at the current zoom. It has the aspect of the screen, its center at the press, and no title. | 1.4, 4.1 |
| D-102 | No card resize in version 1 | none |
| D-103 | `AddCard` and `RenameCard` are new. `MoveNode` and `DeleteNode` hold a node: a text box or a card. | 1.2 |
| D-104 | The pinch-out threshold tests the raw zoom of the fingers, start value 0.6 times `minZoom` | 4.7, 5.3 |
| D-105 | The GPU glyph buffers wait for M10 | none |
| D-106 | Canvas RGB(24, 24, 24) | 3.2 (the composite keeps it) |

### 2.2 Raised by this plan

[decisions.md](decisions.md) gives the facts, the options, and the reasons of each question. The product owner chose the recommendation of each on 2026-10-21.

| ID | Question | Decision | Tasks |
|---|---|---|---|
| D-107 | PNG code and the owner of the preview files | ImageIO in `Rendering` encodes and decodes the PNG bytes. `PreviewStore` in `Persistence` reads and writes the files as `Data`. | 2.1, 3.3, 3.4 |
| D-108 | The fade of the parent during the open | The whole parent composite fades: ink, text, and the other cards. A card pass draws the opened card on top at full weight. | 3.5, 4.5 |
| D-109 | The image of the parent during a leave | A frozen `.r8Unorm` copy of the last frame of the direct parent. Without it, the pinch below `minZoom` or the up button loads the parent. The canvas color shows until its first frame. | 3.5, 4.6, 4.7 |
| D-110 | The memory peak of a transition | At the start of the animation, the parent copies its frame and frees its committed textures and the eraser mask. Task 3.6 measures the peak and sets the budget. | 3.5, 3.6 |
| D-111 | The events that write a preview | The up button, the pinch-out, a workspace switch, and the move to the background | 4.8 |
| D-112 | A path that names a deleted card | Cut the path before the first card that is not live or that has another parent | 2.2, 4.4 |
| D-113 | What "an empty part of the canvas" is | No card and no text box under the finger. Ink does not count. | 4.1 |

### 2.3 Held cost of the card commands

D-88 counts the code points of the texts that a command holds. A card title is a text, so `AddCard`, `RenameCard`, `MoveNode`, and `DeleteNode` count the code points of the titles that they hold. This follows D-88 and needs no new decision.

## 3. How to measure

1. Run each device test on the connected iPad Pro 11-inch (M4), UDID `00008132-000018993E8B801C`, in Release. Never use a simulator (learned rule 1 of `AGENTS.md`).
2. Before each device run, make sure that the iPad is unlocked. `xcrun devicectl device info lockState --device 00008132-000018993E8B801C` must print `passcodeRequired: false`. If it is locked, stop and ask the product owner.
3. Run the Tier A tests on the Mac with `swift test`. Run all of `PointerDeviceTests` on the iPad.
4. To compare a change, run the build before it and the build after it in alternation, as section 5.2 of [m4-fix-plan.md](m4-fix-plan.md) does. Keep a change that makes a measure slower only with a written reason.
5. An allocation test of a main-thread path uses `AllocationCounter.countMainThread`, because other tests run at the same time.
6. A memory test uses the corrected method of D-93: the views of the test host leave the window, and the measure starts after 1.5 s of steady memory.
7. A test that loads a canvas waits until `isLoadingText` and the new card load are false before it ends. Background work of one test must not run into the next test (m5-plan.md section 5.6, the failure of run 1).
8. Record each number in section 5. Do not state a result that no run measured.

## 4. Rules for performance and allocations in M6

These rules turn PERF-01 to PERF-03 into rules for the new code. If the code of a task breaks one of them, the task is not done.

1. The frame path makes no allocation. The card pass, the transition pass, and the preview upload reuse buffers that the renderer reserves once. A frame of a pan over cards makes as many allocations as a bare Metal frame (`FrameAllocationTests`).
2. The renderer makes one preview atlas: one `.r8Unorm` texture of 8 MB (`RendererConfiguration.previewAtlasByteBudget`), made at the first card load. Slots come in three sizes, 512, 256, and 128 pixels square. A 512 slot splits into four 256 slots, and a 256 slot splits into four 128 slots. The slot that was used least recently goes first. No preview makes its own `MTLTexture`.
3. The renderer reserves the card store and its `SpatialGrid` once per load from the count of the loaded cards. The title layouts run with the text layouts, after the first frame, in the same chunks (D-92).
4. A card draws at most 3 kinds of quads: one border quad with a rounded-rectangle coverage in the fragment, one preview quad, and the title glyphs. The card quads count against `instanceBudgetPerFrame` and `buildTimeBudget`, as the glyph quads do.
5. The decode of previews runs on one serial queue off the main actor. At most `RendererConfiguration.previewRequestLimit` requests wait (start value 16). A request for a card that left the texture area is dropped before its decode. The decode writes into one reused buffer of 512 by 512 bytes.
6. The preview render at a leave reuses one `.rg8Unorm` target of 512 by 512 pixels per renderer, made at the first leave. It runs in chunks inside the instance budget, so no frame drops. The readback goes into one shared `MTLBuffer` of 256 KB.
7. Camera animations step in the frame callback with closed-form spring math in `CameraController`. They make no closure and no `Task` per frame (PERF-02).
8. The main actor never waits for a load, a decode, a PNG encode, or a file write.
9. Each new hot path has an `OSSignposter` interval: the card pass, the preview decode, the preview render, the PNG encode and write, the open animation, and the leave (PERF-03).

## 5. Tasks

### Phase 0: decisions and measurement base

#### 0.1 Record the decisions

1. Give D-107 to D-113 to the product owner. Wait for the decisions.
2. Record them in [decisions.md](decisions.md), with the summary rows.
3. Change this plan, architecture.md, data-model.md, storage.md, product-spec.md, and plan.md to match them.

Done when: no document conflicts with a decision.

Rules: AGENT-04, DOC-06.

Status: done on 2026-10-21. decisions.md, architecture.md, data-model.md, storage.md, product-spec.md, and plan.md match D-107 to D-113.

#### 0.2 Baseline of the performance tests

1. Run the full `PointerDeviceTests` 3 times in a row on the iPad at commit 7284f4e.
2. Record the results in section 6.1. Record the open and the memory of the D-56 canvas, and the content passes. Record the frame loop tests, the eraser frame, the frame allocations, and the steps of M4 acceptance 2.

Done when: section 6.1 holds 3 runs. Later tasks compare against them.

Rules: PERF-03, D-79.

Status: done on 2026-10-21. Section 6.1 holds the 3 runs. The worktree of runs 2 and 3 stays in `.build/M6Baseline/tree` for the alternating runs of later tasks.

### Phase 1: model (Tier A)

#### 1.1 Card copies and card changes in the content

1. Add to `Card` the copies `moving(to:at:)`, `retitling(_:at:)`, and `marking(deleted:at:)`, with the checks of the initializer. Follow the pattern of `TextBox`.
2. Add to `CanvasContent` the card versions of `change(to:at:)`, `revive`, and `bury`, and the public `replace(_:)` and `removeCard(_:)`. `cards` holds the live cards only.

Done when: parameterized tests cover 0, 1, `Limits.maxNodesPerCanvas`, and the limit plus one, with a mix of cards and text boxes (TEST-06). Each new function that is not private has a test (TEST-02).

Rules: TEST-02, TEST-06, ARCH-06, D-18, D-57, D-103.

Status: done on 2026-10-21 in commit 8f1a097. The card changes of `CanvasContent` live in `CanvasContent+Cards.swift`, because `CanvasContent.swift` has 345 lines (SIZE-03). Thus `cards` has an internal setter. The helpers throw `CommandError.cardNotLive` and `cardAlreadyLive`, so these cases came with this task. The node limit tests cover 0, 1, the limit minus one, and the limit of existing nodes, with a mix of cards and text boxes, so the last case asks for the limit plus one.

#### 1.2 Card commands and node commands

1. Add `CanvasNode`, an enum with the cases `textBox(TextBox)` and `card(Card)`.
2. Change `MoveNode` and `DeleteNode` to hold a `CanvasNode` (D-103). The text box behavior of M5 does not change.
3. Add `AddCard`. Its apply adds the card and returns its row. Its revert buries the card. A redo revives it.
4. Add `RenameCard` with the old and the new `Card` values. A title of 0 code points stores `nil`.
5. Add the `CommandError` cases `cardNotLive` and `cardAlreadyLive`.
6. Each command counts the code points of the titles that it holds (section 2.3).
7. A delete of a card marks the card only. The child content stays (D-18).

Done when: each command passes the apply-then-revert test of TEST-09 with the live content (D-67). A test of each command makes sure that the returned rows match the content after apply, revert, and a redo. All M5 text tests pass without a change. The line coverage of `Model` stays at least 90 %, and its density at least 2.0.

Rules: UNDO-03, TEST-02, TEST-09, CONTRACT-02, D-67, D-88, D-103.

Status: done on 2026-10-21. `MoveNode` and `DeleteNode` hold a `CanvasNode` and keep their text box initializers, so the M5 tests and the canvas code need no change. `Card.retitling(_:at:)` turns a title of 0 code points into `nil`, and `RenameCard` has the precondition that the new title is not empty. 114 Model tests pass on the Mac. Line coverage of `Model` 91.11 %, density 2.08.

#### 1.3 Navigation path

1. Add `NavigationPath` to `Model` (architecture.md section 6.4). It holds the workspace and at most `Limits.maxDepth` card IDs, root first.
2. `level` is the count of cards: the root canvas is level 0 (D-95). `currentCanvas` is the canvas of the last card, or the root canvas.
3. `pushing(_:)` throws `ModelError.depthLimitReached` at level 32. `popping()` gives the path without its last card, and has the precondition that the path is not empty.
4. `canAddCard` is false at level 32.

Done when: parameterized tests cover levels 0, 1, 31, 32, and 33 (TEST-06).

Rules: CARD-09, TEST-06, FLOW-01, D-95.

Status: done on 2026-10-21. `NavigationPath` also gives `parentCanvas`, for the leave of tasks 4.4 and 4.6. `ModelError.depthLimitReached` is new. architecture.md section 6.4 named the type `NavigationState` and now names it `NavigationPath`. 118 Model tests pass. Density of `Model` 2.08.

#### 1.4 Frame of a new card

1. Add `Card.defaultFrame(at:camera:viewSize:)` in `Model`, or a small type next to it. It gives the frame of D-101: a quarter of the screen width at the current zoom, the aspect of the screen, centered on the press point.
2. If the size is under `Limits.minCardWidth` by `Limits.minCardHeight`, the minimum sets the size. Keep the aspect while the frame is larger than the minimum in both directions.

Done when: tests cover zoom 0.25, 1, and 8, a tall and a wide view, and a press point far from the origin, for example (1,000,000, 1,000,000).

Rules: CARD-01, TEST-02, D-101.

Status: done on 2026-10-21. `Card.defaultFrame(at:camera:viewSize:)` raises each side to its minimum on its own. Thus at zoom 8 on the 11-inch iPad, the frame is 64 by 48 in landscape and in portrait, as D-101 says. In landscape at zoom 1, the frame is 298.5 by 208.5 points. 122 Model tests pass. Density of `Model` 2.10.

### Phase 2: persistence (Tier A)

#### 2.1 Preview store

1. Add `PreviewStore` to `Persistence` (D-107). It reads, writes, and removes `Caches/Pointer/previews/<canvas-id>.png` as `Data`. It does not decode.
2. A write is atomic: write to a temporary file in the same folder, then rename.
3. A read of a missing file returns `nil`. A file larger than `PreviewStore.maxFileSize` (start value 64 KB) counts as damaged, so the store removes it and returns `nil` with a log entry.
4. `removeAll()` clears the folder, for the restore of M9.
5. The store runs off the main actor, on its own serial executor, as `DeviceStateStore` does.

Done when: tests use a temporary folder per test (TEST-04). They cover a write and a read, a missing file, and a damaged file. They also cover a file at the size limit, the limit plus one, and `removeAll()` (TEST-06).

Rules: ARCH-04, TEST-04, TEST-06, SAFE-04, D-97, D-107.

Status: done on 2026-10-21. A write of 0 bytes or of more than `maxFileSize` throws `PersistenceError.fileFailed`, because a read removes a file above the limit as damaged. A file that does not read, for example a folder with the name of a preview, also counts as damaged. 95 Persistence tests pass. Line coverage of `Persistence` 91.51 %, density 2.01.

#### 2.2 Validation of the stored path

1. Add `LibraryRepository.validPath(_:in:)`. It reads the cards of the path in one query and returns the longest valid start of the path (D-112).
2. A valid card is live, and its `canvasID` is the canvas above it.
3. The loop is bounded by `Limits.maxDepth` (FLOW-03).

Done when: tests cover an empty path, a valid path of 32 cards, and a deleted card in the middle. Other tests cover a card under a different parent, and a path of 33 cards from a damaged file.

Rules: WS-04, FLOW-01, FLOW-03, D-112.

Status: done on 2026-10-21. `validPath(_:in:)` is part of the protocol `LibraryRepository`, so the fakes of the feature tests have it too. One prepared statement reads the live cards of the path with 32 parameters, and the unused ones take NULL. The rows that wait for a save are saved first, as a load does. A path of 33 cards keeps its first 32 valid cards. 101 Persistence tests pass. Line coverage of `Persistence` 91.25 %, density 2.00. The device tests build.

### Phase 3: rendering (Tier B)

#### 3.1 Card store

1. Add `CardStore` to `Rendering`: the cards of the loaded canvas, their `SpatialGrid` with the cell size of the strokes, and the layout of each title (architecture.md section 5.6).
2. Add `CanvasRenderer.load(_ cards:)` and `changeCards(removing:adding:)`. The load lays out the titles off the render thread, after the first frame, in the chunks of the text load (D-92).
3. The bounds of a card in the grid hold the frame and the title above it.
4. `renderDelta(of:)` in the canvas sends `.card` rows to `changeCards`.

Done when: tests cover a load, a change, a title of 120 code points, and a card without a title. A move of a card keeps its title layout, as `TextStore.add(_:)` keeps the layout of a moved box.

Rules: PERF-01, TEST-02, D-92, D-96.

Status: done on 2026-10-21 in commit 1c85e4b. A title uses the text layout of D-84: SF Mono at 17 points with the wrap at 640 points, so a title of 120 code points takes 2 lines. The last line of the title sits on the top edge of the card. No document gives the form of a long title, so the product owner can still change it. The canvas loads the cards, and the open helper of the device tests waits for the text and card loads before it closes a canvas (section 4, rule 8). `SpatialGrid` got `reserveCapacity(_:)`. A full run of `PointerDeviceTests` on the iPad passed 226 tests: the open of D-56 took 248.9 ms (median) and held 346 MB, inside the range of section 6.1. The zoom over the D-56 text had 1 late frame of 478, which D-94 accepts in a full run.

#### 3.2 Cards in the committed layer

1. Add `DesignSystem.Color.cardBorder` as a coverage value below 1. Pass it through `RendererConfiguration.cardBorderCoverage`, as D-106 passes the background, so `Rendering` needs no `DesignSystem` import.
2. Add the card border pipeline: one quad per card, a rounded rectangle of 1 point in the fragment, green write mask, `max` blend.
3. Draw the title glyphs with the glyph pipeline, above the top-left corner.
4. A build draws the cards in its chunks, with the text. A green clear of a text change or a card change draws the cards and the text in the rectangle again (section 1.2, item 4).
5. The eraser never hides a card (D-82). The redraw of an erase clears red only, as before.

Done when:

- Snapshot tests on the iPad (TEST-07, D-77): `card-zoom0.25`, `card-zoom1.0`, and `card-zoom4.0`.
- Snapshot tests of the layers: `card-under-ink` (ink over a card), `card-under-eraser-mask`, and `card-move-redraw`.
- The snapshot test `text-over-card-redraw`: a text change over a card keeps the card.
- The snapshot tests of M2, M4, and M5 give the same images.

Rules: TEST-07, CARD-02, D-16, D-82, D-96, D-106.

#### 3.3 Preview atlas and decode

1. Add the preview atlas of section 4, rule 2.
2. After the first frame, the renderer asks for the previews of the cards in the texture area. The size step comes from the size of the card on the screen: 128, 256, or 512 pixels.
3. The decode runs off the main actor (section 4, rule 5). It uses ImageIO (D-107). The result goes into the inbox. The render thread copies it into its slot with a blit.
4. A card without a preview shows its border and its title only.
5. The preview quad samples its slot and writes green with `max`, cut to the frame of the card.
6. A missing file starts one load of that child canvas alone, off the main actor. It renders the preview with the offscreen path of task 3.4, writes the file, and frees the child content. Only one such load runs at a time.

Done when:

- Tests cover the budget plus one slot, the split of a 512 slot, and a damaged PNG.
- A test covers a request for a card that left the area.
- A snapshot test `card-preview` compares a card with its preview at zoom 1.
- A frame that uses cached previews only makes no allocation in Pointer code (PERF-01).

Rules: PERF-01, PERF-02, TEST-07, D-97, D-107.

#### 3.4 Preview render at a leave

1. Add `CanvasRenderer.renderPreview(camera:cardAspect:size:completion:)`. It draws the child region of the open camera, cut to the aspect of the card (D-98), into the target of section 4, rule 6. Cards of the child show as frames and titles without their previews (architecture.md section 5.5).
2. A resolve pass writes `max(r, g)` into one channel. A blit copies it into the shared buffer.
3. The completion runs off the main actor. It encodes the PNG and gives the `Data` to `PreviewStore`. It also gives the decoded bytes to the parent renderer, so the parent shows the new preview without a read of the file.

Done when: a test renders the preview of a known canvas and compares it with a reference PNG (TEST-07). The preview of the D-56 content takes a recorded time on the iPad, and no frame of the child drops during it.

Rules: PERF-01, PERF-03, TEST-07, D-97, D-98.

#### 3.5 Transition pass

1. Add the frozen copy of the parent frame (D-109) and the release of the committed textures at the start of the animation (D-110).
2. Add a transition pass: the frozen copy with a fade weight, and the opened card on top at full weight (D-108).
3. Add the crossfade of 0.1 s from the preview to the first frame of the child, and the reverse for a leave.
4. The weights are uniforms, set from the camera animation each frame (section 4, rule 7).

Done when: snapshot tests cover the start, the middle, and the end of an open and of a leave. A frame of the transition makes no allocation in Pointer code.

Rules: PERF-01, TEST-07, CARD-03, CARD-04, CARD-05, D-98, D-108, D-109, D-110.

#### 3.6 Cards in the frame and memory budgets

1. The open test and the memory test of the D-56 canvas now draw the 5,000 cards.
2. Add a frame loop test that pans and zooms over the D-56 cards at zoom 0.25 and 1.
3. Add a device test of the memory peak of an open from the D-56 canvas into a D-56 child, and of the leave back.

Done when: the open of D-56 stays under 300 ms and at most 10 % over section 6.1. The memory of the open stays under 380 MB (D-93). The frame loop over cards gives 120 fps and 0 late frames in a run of `FrameLoopTests` alone. Section 6 holds the transition peak against the budget of D-110.

Rules: CAN-05, PERF-03, D-56, D-93, D-94, D-110.

### Phase 4: canvas and app (Tier C)

#### 4.1 New card

1. A finger long press on an empty part of the canvas (D-113) opens a `UIEditMenuInteraction` menu with "New card" (CARD-01). A long press during a text edit ends the edit first.
2. "New card" records one `AddCard` step with the frame of task 1.4 and a new sort key at the end of the card list.
3. At level 32, "New card" is refused with a message (CARD-09, D-95). At `Limits.maxNodesPerCanvas`, it is refused with the node limit message.
4. Add the strings to the String Catalog of the canvas (STYLE-05).

Done when: tests cover a new card, its undo and redo, the refusal at level 32, and the node limit. The pan of the canvas still works on empty canvas.

Rules: CARD-01, CARD-09, UNDO-03, STYLE-05, D-08, D-95, D-101, D-113.

#### 4.2 Card menu and move

1. A long press on a card without a drag opens a menu with "Rename" and "Delete" (CARD-08).
2. "Rename" opens an alert with a text field, as the workspace rename does (D-101). It records one `RenameCard` step. If the title did not change, it records no step.
3. "Delete" records one `DeleteNode` step.
4. A long press on a card, then a drag, moves it (CARD-07). The drag records one `MoveNode` step.
5. A text box above a card wins the long press, because text lies on top (D-16).

Done when: tests cover a rename, an empty title, and a title of 120 and 121 code points. Other tests cover a delete, a move, and the undo and redo of each. Snapshot tests cover the menu and the alert.

Rules: CARD-07, CARD-08, UNDO-03, TEST-07, D-10, D-16, D-101.

#### 4.3 Double tap on a card

1. Add a finger double-tap recognizer. It begins only on a card that no text box covers (D-100).
2. Only for a touch on such a card, `fingerTap` waits for it through `gestureRecognizer(_:shouldRequireFailureOf:)`.
3. A single tap on a card ends an edit and does nothing else. A pencil tap with the text tool on a card makes a text box on the parent canvas (D-100).
4. The PencilKit finger rule of `shouldBeRequiredToFailBy` (`CanvasViewController+Gestures.swift`, line 66) also waits for the double tap.
5. Measure on the iPad the delay from the finger lift of a single tap on a card to the end of the recognizer wait. Record it in section 6.

Done when: tests cover a double tap on a card, on a text box over a card, and on empty canvas. The tap on a text box starts its edit without the wait. The keyboard fixes of commits c77cf46 and 477f4bc still hold (`ScribbleConditionTests`, `TextEditTests`).

Rules: CARD-03, TOOL-06, D-09, D-100.

#### 4.4 Navigation and the canvas of a card

1. `AppComposition` opens a canvas by `NavigationPath`, not by workspace. A workspace switch opens the deepest canvas of the stored path (D-99, D-112).
2. An open by double tap uses the camera of CARD-03: zoom 1, centered on the content bounds of the child. For an empty child, the camera centers on the origin.
3. A leave uses the camera of CARD-04: zoom 1, centered on the card.
4. The device state writes the path at each navigation, and the camera at rest, as before.
5. Each canvas keeps its own history in `CanvasSessions` (UNDO-02, D-12). Change the comment of `CanvasSessions.capacity`, because a canvas now belongs to a card or to a workspace.
6. An up button joins the chrome in the top left, after the tool button. While the path is empty, it does not show (architecture.md section 6.4). Add its icon to `DesignSystem` and its label to the String Catalog.

Done when: tests cover an open, a leave, a launch into a path of 3 cards, and a launch with a deleted card in the path. A test covers the history of a child after a leave and a new open. A snapshot test covers the chrome with the up button.

Rules: CARD-03, CARD-04, UNDO-02, UNDO-04, WS-04, TEST-07, D-12, D-99, D-112.

#### 4.5 Open animation

1. The double tap starts the open of D-98. The parent camera animates for 0.35 s with a spring. At the end, the card covers the screen at the scale k = max(W / w, H / h) (architecture.md section 6.2).
2. The child loads during the animation. At the end of the load, its renderer starts.
3. When the animation ends and the first frame of the child is ready, the crossfade of task 3.5 runs.
4. If the child load takes longer than the animation, the screen holds the last frame of the animation until the first frame of the child.
5. A second double tap during an open does nothing.

Done when: a device test captures each frame of an open of a D-56 card and records the largest change between two frames. The animation has 0 late frames at 120 Hz.

Rules: CARD-03, CAN-05, PERF-03, D-98.

#### 4.6 Leave with the up button

1. The tap starts the load of the parent and moves the child camera to the camera of the open in the same time (D-109).
2. When both are done, the reverse animation runs: the child shrinks into the card frame of the parent.

Done when: a device test captures each frame of the leave, as in task 4.5.

Rules: CARD-04, D-98, D-109.

#### 4.7 Pinch-out exit

1. Below `minZoom`, the child shows as a shrinking card over the faded image of the parent (D-109).
2. At the finger lift, compare the raw zoom of the fingers with `exitZoomRatio` times `minZoom` (D-104). The raw zoom has no rubber band. `exitZoomRatio` is a named constant of `CameraController`, with the start value 0.6.
3. Under the threshold: the minimize animation runs, and the child image crossfades to its preview while the card shrinks. Above it: the camera springs back to `minZoom`.
4. On the root canvas, the camera springs back and nothing else happens (CARD-06).
5. Tune the threshold on the iPad with the product owner. Record the value and the reason with a source comment (DOC-03).

Done when: tests of `CameraController` cover a lift just under and just over the threshold, at zoom 0.25 and 1, and the root canvas.

Rules: CARD-05, CARD-06, DOC-03, D-104.

#### 4.8 Preview write

1. At each leave event of D-111, the canvas asks its renderer for the preview of task 3.4.
2. The child screen stays until the preview render ends. The write runs off the main actor and does not block the next screen.

Done when: tests cover each leave event of D-111. On the iPad, a change in a child shows in the preview of its card after the leave.

Rules: CARD-02, D-97, D-111.

### Phase 5: acceptance tests

#### 5.1 Acceptance 1: open and leave without a visible jump

1. Run the frame captures of tasks 4.5 and 4.6 on a D-56 card and on an empty card.
2. The product owner records the screen on the iPad and steps through it frame by frame. This is the pass of acceptance 1.

Done when: the device tests pass, and the product owner reports a pass.

Rules: CARD-03, CARD-04, D-98.

#### 5.2 Acceptance 2: a tree of 32 levels

1. Add a device test that builds a tree of 32 cards, one in each canvas.
2. It opens each level from the root, draws one stroke at each level, and leaves to the root.
3. At level 32, "New card" is refused with the message (D-95).
4. A launch with the path of 32 cards opens level 32.

Done when: the test passes on the iPad.

Rules: CARD-09, D-95.

#### 5.3 Acceptance 3: a lift above the threshold cancels the exit

1. Add a test that drives a pinch below `minZoom` and lifts above the threshold. The canvas stays the child, and the camera springs back to `minZoom`.
2. The product owner runs the gesture with the fingers on the iPad.

Done when: the test passes, and the product owner reports a pass.

Rules: CARD-05, D-104.

### Phase 6: close of M6

1. The line coverage of each Tier A package is at least 90 % (TEST-02). For Tier B it is at least 70 %. The assertion density of each package is at least 2.00 (CONTRACT-02).
2. The documents in `docs/` match the code (DOC-06). Each new folder is in the context map of `AGENTS.md` (AGENT-07).
3. Run the full checklist of [code-of-code.md](code-of-code.md) section 5, with `make check` on the iPad (AGENT-05).
4. Run all snapshot tests on the iPad, each new class included in `make snapshots`. No snapshot test skips.
5. Run the full `PointerDeviceTests` 5 times in a row (D-79). Each test of section 6.1 must be at most 10 % slower.
6. Fill in section 6, and update the M6 status in [plan.md](plan.md).
7. List the manual tests for the product owner in section 6.6.

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, TEST-02, TEST-07, PERF-03, D-79.

## 6. Results

### 6.1 Baseline

Measured on 2026-10-21 on the iPad Pro 11-inch (M4) in Release, with the code of commit 7284f4e. Run 1 ran in the main tree at commit 64ae7be, which changes documents only. Runs 2 and 3 ran in a separate worktree at commit 7284f4e, and run 3 used the build of run 2. Each run passed 221 tests with 0 failures and 0 skips. The memory test and the open test use the corrected method of D-93.

| Run | Open of D-56, median / slowest | Memory of the open, held / peak | Content pass 20,000 / 200,000 / 200,000 handwriting | Eraser frame CPU / GPU median | Erase / undo / redo, slowest |
|---|---|---|---|---|---|
| 1 | 247.6 / 252.8 ms | 344 / 344 MB | 37.4 / 114.1 / 171.8 ms | 0.11 / 0.31 ms | 29.82 / 26.06 / 24.21 ms |
| 2 | 247.5 / 262.3 ms | 346 / 346 MB | 36.0 / 114.2 / 170.0 ms | 0.11 / 0.41 ms | 31.81 / 28.09 / 26.53 ms |
| 3 | 257.7 / 261.0 ms | 350 / 350 MB | 35.8 / 112.9 / 170.1 ms | 0.11 / 0.41 ms | 30.11 / 28.06 / 22.91 ms |

In each run, the 8 frame loop tests ran at 120 fps with 0 late frames of 479. The pan over the D-56 text showed uncovered screen in 166, 116, and 125 of 480 frames (D-94). The other 7 frame loop tests had 0 uncovered frames. The frame allocations were 15 against 15 of a bare Metal frame. `FrameRenderer.apply` made 14, 2, and 1 allocations for the erase, the undo, and the redo of the D-69 content. A text pass with cached glyphs made 2 allocations against 2 of a bare pass.

Other numbers of the same runs, for later tasks: the layout of the 5,000 text boxes of D-56 took 57.8, 55.5, and 56.4 ms (median). The text pass of 300 boxes at zoom 1 took 0.816, 0.824, and 0.824 ms, or 17.0 to 17.2 ns per glyph.

### 6.2 Model and persistence

Not measured yet.

### 6.3 Rendering

| Item | Target | Result |
|---|---|---|
| Open of D-56 with cards, median | under 300 ms, at most 10 % over section 6.1 | not measured |
| Memory of the open of D-56 with cards | under 380 MB (D-93) | not measured |
| Frame loop over the D-56 cards, alone | 120 fps, 0 late frames | not measured |
| Frame allocations with cards and cached previews | equal to a bare Metal frame | not measured |
| Preview render of the D-56 content | recorded, no dropped frame | not measured |
| Memory peak of an open from D-56 into a D-56 child | budget of D-110 | not measured |

### 6.4 Canvas

| Item | Target | Result |
|---|---|---|
| Delay of a single tap on a card (D-100) | recorded | not measured |
| Open animation, late frames | 0 | not measured |
| Pinch-out threshold after the tune | recorded with the reason | not measured |

### 6.5 Acceptance

Not measured yet.

### 6.6 Manual tests for the product owner

1. Hold a finger on empty canvas. Pick "New card". A card shows at the finger.
2. Double tap the card with a finger. The card grows to cover the screen, and its canvas shows without a jump (acceptance 1).
3. Draw in the card, then tap the up button. The parent shows at zoom 1, centered on the card. The preview shows the new ink.
4. Open the card again, and pinch out past the minimum zoom. Lift the fingers early: the camera springs back (acceptance 3). Pinch further and lift: the parent shows.
5. On the root canvas, pinch out past the minimum zoom. The camera springs back, and nothing else happens.
6. Hold a finger on a card. Rename it, then delete it. Undo brings it back with its content.
7. Hold a finger on a card, then drag. The card moves. Undo puts it back.
8. Tap a text box that lies over a card. The edit starts at once.
9. Force quit the app inside a card, and launch it again. The same card opens at its last camera.
