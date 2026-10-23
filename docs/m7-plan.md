# M7 work plan: Apple Pencil interactions

This document breaks milestone M7 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on D-05, D-23, D-63, D-64, D-70, D-87, and D-125 to D-131.

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

## 1. How to work

### 1.1 Device and build

1. Use only the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator, and never make one (learned rule 1 of `AGENTS.md`).
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. If it prints `passcodeRequired: true`, stop and ask the product owner to unlock the iPad.
3. Run one device suite with this command. Replace `<Suite>` and `<Name>`.

```
xcodebuild test -project Pointer.xcodeproj -scheme PointerApp -configuration Release \
  -destination 'id=00008132-000018993E8B801C' -derivedDataPath .build/DeviceData \
  -allowProvisioningUpdates ENABLE_TESTABILITY=YES \
  -only-testing:PointerDeviceTests/<Suite> -resultBundlePath .build/Runs/<Name>.xcresult
```

4. Read the measures as in section 1.2 of [m6-fix-plan.md](m6-fix-plan.md). Compare two builds only with alternating runs (section 1.3 there).
5. The test pencil is an Apple Pencil Pro (D-129). Only the product owner can hover, tap, or squeeze. A task that needs the pencil ends with a manual test for the product owner.

### 1.2 What a test can and cannot do

1. A test cannot make a `UIPencilInteraction.Tap`, a `UIPencilInteraction.Squeeze`, or a hover event. Keep each delegate method and each recognizer handler thin. Put the logic in a pure function, as `PaletteAnchor` does, and test that function.
2. A test can call the methods of `CanvasViewController` that the handlers call. Test the effect on the tool, the palette, and the dot through these methods.

## 2. Facts from the code at the start of M7

Read on 2026-10-22 on branch `m7`, from `main` at commit 42ac61e. Paths are under `Packages/CanvasFeature/Sources/CanvasFeature/` unless they start with `PointerApp/`.

### 2.1 Pencil interaction and tools

1. `CanvasViewController+Tools.swift:9` installs one `UIPencilInteraction` on the view of the canvas (line 13). The controller is its delegate. Only `pencilInteraction(_:didReceiveSqueeze:)` exists (line 73). No double-tap method exists.
2. `PaletteAnchor.squeeze(isEnded:action:hoverLocation:lastPencilLocation:)` is a pure function with tests in `ToolPaletteTests`. It opens nothing for `.ignore` and `.runSystemShortcut`.
3. `ToolState` holds `selected` and `active` and applies D-70: a tool change takes effect at the next pencil down. `ToolStateTests` covers it.
4. `CanvasViewController.select(_:)` (`CanvasViewController.swift:144`) ends a text edit (D-87) and updates the button. It also prepares the eraser mask (D-78) and sets the drawing gesture of PencilKit. A double tap calls it.
5. `lastPencilLocation` (`CanvasViewController.swift:40`) holds the last pencil sample in view space.
6. `PencilTouchObserver` sees pencil touches only. Nothing in the app sees a hover.
7. During a card flight, two canvas screens exist, and each has its own pencil interaction. `isInCardTransition` (`CanvasViewController+Transition.swift:36`) is `true` during a flight. When two interactions exist, Apple does not say which one gets a tap.

### 2.2 Views and rendering

1. `CanvasView` adds `inkView`, then `liveCanvas` (`CanvasView.swift:22` and `:23`). The hover layer goes above both (D-126).
2. The eraser radius is 8 view points (`EraserTool.swift:7`). It stays the same on the screen at every zoom.
3. `applyCamera()` (`CanvasViewController.swift:329`) makes a new `PKInkingTool` at each zoom change (line 333). On the root canvas, this runs at each pinch sample and at each frame of a spring or a flight. A canvas inside a card has the zoom 1 only (D-119).
4. `DesignSystem` has no token for the hover dot.

### 2.3 Navigation faults of the review (D-131)

1. `makeCanvas` calls `container.canvas?.endSession()` before the open of a child is sure (`PointerApp/AppComposition+Navigation.swift:275`). If the open then fails, `cancelCardTransition` gives the input back to the parent, but `hasEndedSession` stays `true` (`CanvasViewController+History.swift:209`). The steps after that do not go into the session, so the undo history of the parent is lost at the next switch.
2. If the card is not in the content of the parent, or if `makeCanvas` gives `nil`, `loadParent` returns at `PointerApp/AppComposition+Navigation.swift:143`. `opening` then stays set, so each later open and leave is refused. `loadChild` has the same return for `makeCanvas` (line 61).
3. A leave renders the preview of the child (`PointerApp/AppComposition+Previews.swift:18`). `finishLeave` waits for `isPreviewDone` (`PointerApp/AppComposition+Navigation.swift:183`). If the render thread of the child stops before the render ends, the completion possibly never runs. This fault is not proven.

## 3. Decisions

The product owner decided these on 2026-10-22. [decisions.md](decisions.md) gives the facts and the reasons.

| ID | Decision | Tasks |
|---|---|---|
| D-125 | The check of late frames of the open of an empty card is an expected failure that is not strict. M10 traces the late frame. | Done before this plan |
| D-126 | The hover dot is a `CAShapeLayer` above the live `PKCanvasView`, not a Metal pass. | 2.2 |
| D-127 | Check on the device whether PencilKit shows a hover shadow with the monoline pen. If it shows, accept it and keep the dot. | 0.1 |
| D-128 | A gray dot for the pen and the text tool, the eraser circle for the eraser, hidden while "Show Hover Preview" is off. | 2.1, 2.2 |
| D-129 | The test pencil is an Apple Pencil Pro. Acceptance 3 runs with double tap and squeeze set to "Ignore". | 4.1 |
| D-130 | Only "Switch to eraser" and "Switch to previous tool" switch between pen and eraser. Text goes to the pen. Every other value does nothing. | 1.1, 1.2 |
| D-131 | Phase 0 fixes three navigation faults. Phase 3 sets the pen tool only at a pencil down and at rest. The rest goes to M10. | 0.2 to 0.4, 3.1 |

Raise each new question as an open entry in [decisions.md](decisions.md) before the task that needs it. Do not decide it yourself (AGENT-04).

## 4. Tasks

### Phase 0: preparation

#### 0.1 The hover shadow of PencilKit (D-127)

1. Ask the product owner to open a canvas with the pen and hold the Apple Pencil Pro above it.
2. Ask the product owner to note whether a shadow shows below the pencil. Ask for the same check with the eraser and the text tool.
3. Record the answer in section 6 of this plan.

Done when: section 6 says whether the shadow shows for each tool. Phase 2 does not change with the answer.

#### 0.2 A failed open keeps the session of the parent

1. Add a device test to `NavigationCancelTests` or a new suite. Make the open of a child fail after `makeCanvas`. For example, give the composition a repository whose `content(of:)` throws for the child. Then draw a stroke on the parent, switch the workspace, and switch back. The undo of the stroke must work.
2. Make sure that the test fails on the current code.
3. Fix it. Pick the smaller of two changes. One change ends the session of the parent after a successful open only. The other gives the session back in `cancelCardTransition`. Keep F-02: the new screen reads the sessions.

Done when: the test passes, and `NavigationTests`, `DeepTreeTests`, and `CanvasSwitchTests` pass.

Rules: TEST-03, UNDO-01, F-02.

#### 0.3 A leave without its parent card ends

1. Add a device test. Start a leave whose parent content has no card of the child, for example after a delete of the card in the repository. The leave must end with a message, and the next open must run.
2. If a test can make an open whose `makeCanvas` gives `nil`, add the same test for it. If not, record why.
3. Make sure that the tests fail on the current code.
4. Fix it. In `loadChild` and `loadParent`, a return that is not a cancel calls `fail(_:on:)`.

Done when: the tests pass, and the tests of task 0.2 pass.

Rules: TEST-03, WS-02, CARD-04.

#### 0.4 A preview render on a stopped thread

1. Add a device test. Start the preview render of a leave, then take the child view out of the window before the render ends. The completion must run. If the render did not end, it gets `nil`.
2. If the test passes on the current code, record in section 6 that the fault does not exist, and keep the test.
3. If it fails, call each waiting completion with `nil` when the render thread stops.

Done when: the test passes.

Rules: TEST-03, D-111.

#### 0.5 Baseline

1. Run the full `PointerDeviceTests` once, with a result bundle.
2. Record in section 6: the erase, undo, and redo steps, the open of the D-56 canvas, its memory, the frame loops, and the allocations of each allocation test.

Done when: section 6 holds the baseline. Phase 5 compares against it (code-of-code.md section 5, item 10).

### Phase 1: double tap

#### 1.1 The mapping of a double tap

1. Add a pure function, for example `ToolSwitch.tool(after:action:)`, next to `PaletteAnchor`. It takes the selected tool and `UIPencilPreferredAction`, and returns the new tool or `nil`.
2. Follow D-130:
   - `.switchEraser` and `.switchPrevious`: the pen goes to the eraser, the eraser goes to the pen, and text goes to the pen.
   - Every other value, also an unknown future value: `nil`.
3. Add a parameterized Swift Testing test over each value of the enum and each tool (TEST-06).

Done when: the tests pass on the iPad.

Rules: PEN-01, PEN-02, D-130, TEST-06.

#### 1.2 The double-tap handler

1. Add `pencilInteraction(_:didReceiveTap:)` to `CanvasViewController+Tools.swift`. Read `UIPencilInteraction.preferredTapAction` at each tap, because the user can change it while the app runs.
2. Call `select(_:)` with the result of task 1.1. A tap during a pencil touch takes effect at the next pencil down (D-70). A tap during a text edit ends the edit (D-87).
3. Add a test that calls the code behind the handler for each value. It checks the tool, the button, and the end of a text edit.

Done when: the tests pass.

Rules: PEN-01, PEN-02, D-70, D-87, D-130.

#### 1.3 No tap and no squeeze during a card flight

1. Add a check to the tap and the squeeze: do nothing while `isInCardTransition` is `true` or while the canvas is not the shown canvas of the container. Give the canvas a flag that the container sets, or check `view.window` and `isUserInteractionEnabled`. Pick the smaller change.
2. Add a test that starts the open of a card and calls the tap and the squeeze code on both screens during the flight. The tool and the palette must not change.

Done when: the test passes, and `TransitionTests` and `PinchCancelTests` pass.

Rules: CARD-03, CARD-04, D-63.

### Phase 2: hover dot

#### 2.1 The model of the dot

1. Add a pure type, for example `HoverDot`. It takes the selected tool, `prefersHoverToolPreview`, the hover location, whether the pencil touches, and whether a card flight runs. It returns `nil` for no dot, or a center and a radius in view points.
2. Follow D-128:
   - The pen and the text tool: a small dot.
   - The eraser: a circle with `EraserTool.radius`.
   - No dot while the preference is off, while the pencil touches, or during a flight.
3. Add the dot color and the dot radius to `DesignSystem` (STYLE-03). Start with a gray of the chrome and a radius of 2 view points. These are start values. The product owner tunes them in task 2.5.
4. Add parameterized tests for each case.

Done when: the tests pass.

Rules: PEN-04, D-128, STYLE-03, TEST-06.

#### 2.2 The layer and the recognizer

1. Add a `CAShapeLayer` to `CanvasView`, above `liveCanvas` (D-126). Make its path once for the dot and once for the eraser circle, and switch between the two paths only at a tool change.
2. Turn off the implicit animations of the layer, for example with an empty `actions` dictionary, so that a move does not animate.
3. Add a `UIHoverGestureRecognizer` with `allowedTouchTypes = [.pencil]` to the canvas view. At `.began` and `.changed`, move the layer to the result of `HoverDot`. At `.ended` and `.cancelled`, hide it.
4. Hide the layer in `pencilBegan()` and at the start of a card flight. Read `prefersHoverToolPreview` at `.began` of each hover, because the user can change it in Settings.
5. The recognizer must not block the pan, the pinch, the text taps, or the live canvas. Make sure that `TextEditTests`, `CameraControllerTests`, and the palm tests pass.

Done when: the tests of the canvas pass on the iPad.

Rules: PEN-04, D-126, D-128, D-36.

#### 2.3 No allocation at a hover sample

1. Add an allocation test, as `EraserSampleAllocationTests` does. Count the allocations of the code that a hover sample runs: `HoverDot` and the move of the layer.
2. The count must be 0 in Pointer code (PERF-01). The work of Core Animation does not count, as the Metal work does not count (D-43). Subtract the count of a bare layer move.
3. Add an `OSSignposter` interval around the hover update (PERF-03).

Done when: the test passes.

Rules: PERF-01, PERF-03.

#### 2.4 A snapshot of the dot

1. Add `HoverDotSnapshotTests`. Render a `CanvasView` with the dot of the pen and with the eraser circle with `UIGraphicsImageRenderer`, and compare with reference PNGs (TEST-07).
2. Add the class to the `snapshots` target of the `Makefile`.

Done when: the test passes in `make snapshots`.

Rules: TEST-07.

#### 2.5 The manual test of the dot

1. Ask the product owner to hover with the pen, the eraser, and the text tool, on the root canvas and inside a card.
2. Ask the product owner to turn "Show Hover Preview" off in Settings, then hover again.
3. Ask whether the size and the gray of the dot fit. If the product owner asks, change the tokens of task 2.1.

Done when: the product owner accepts the dot, and section 6 records it.

Rules: PEN-04, D-127, D-128.

### Phase 3: the pen tool at a zoom (D-131)

#### 3.1 Set the pen tool only when it is needed

1. Measure first. Count the allocations of `applyCamera()` during a zoom on the root canvas, and record the main-thread time of the `dense 20k zoom` frame loop. Record both in section 6.
2. Set `liveCanvas.tool` in `pencilBegan()` and at the rest of the camera. Do not set it at each frame of a pinch, a spring, or a flight.
3. The first stroke after a zoom must have the width of the new zoom. Add a test: zoom with a spring, put the pencil down during the spring, and compare the tool width with `PenTool.inkingTool(zoom:)` of the camera at the pencil down.
4. Run `PencilKitParityTests` and the handoff tests of FEEL-03. They must pass.

Done when: a zoom frame makes no `PKInkingTool`, the tests pass, and the frame loops are not slower.

Rules: PERF-01, FEEL-03, D-37, TEST-03.

### Phase 4: manual acceptance

#### 4.1 The manual tests for the product owner

1. Acceptance 1. Set each double-tap value of Settings in turn, and double-tap with the pen, the eraser, and the text tool. Only "Switch to eraser" and "Switch to previous tool" switch the tool (D-130).
2. Acceptance 2. Set the squeeze to "Show contextual palette", and squeeze above the canvas. The palette opens at the pencil tip. Repeat inside a card.
3. Acceptance 3 (D-129). Set double tap and squeeze to "Ignore". Then draw, erase, and write text with Scribble. Make a card, open it, and leave it. Pick each tool with the button in the top left corner.
4. Acceptance 4. Turn the haptics of the pencil on in Settings. Draw, erase, double-tap, squeeze, and pick each tool in the palette. Only the system haptic of a squeeze or a double tap plays (D-23). Drawing plays none.
5. Record each result in section 6.

Done when: the product owner reports a pass for each test, or decides about a failure.

Rules: PEN-01 to PEN-06, D-23, D-129, D-130.

### Phase 5: close

1. Run `make check` with the iPad, and `make coverage`.
2. Run the full `PointerDeviceTests` 5 times in a row (D-79). Compare each measure with the baseline of task 0.5. A measure can be at most 10 % slower.
3. Fill in section 6 of this plan, and the M7 status in [plan.md](plan.md).
4. Update the context map of `AGENTS.md` if a folder is new (AGENT-07).

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, D-79.

## 5. Facts to keep in mind

- `CanvasViewController` has a type body limit of 250 lines and a function body limit of 40 lines (SwiftLint). Put new code in an extension file, for example `CanvasViewController+Hover.swift`.
- `#expect` cannot hold a call of a mutating method. Assign the result to a constant first.
- A test that keeps a canvas screen in a local constant keeps it alive until the end of the scope. Put the steps of a round in a function of their own (`CanvasLifetimeTests`).
- A test helper that gives a closure to the composition must capture it weakly, or the composition stays alive after the test.
- A test that waits for a canvas must also wait for the end of `AppViewController.isSwapping` and of `isInCardTransition`.
- The assertion density script needs 2.00 checks per function in Tier A and Tier B packages (CONTRACT-02, `make density`).

## 6. Results

Fill in this section during the work.

### 6.1 The hover shadow of PencilKit (task 0.1)

The product owner held the Apple Pencil Pro above a canvas on the iPad on 2026-10-22 and reported: "All tree tools have a hover indicator." PencilKit thus shows its hover indicator for the pen, the eraser, and the text tool. Under D-127, Pointer accepts it as behavior of the system and keeps its own dot (PEN-04).

### 6.2 Baseline (task 0.5)

Measured on 2026-10-22 on the iPad Pro 11-inch (M4) in Release, with the code of commit 7607388. The run is one full run of `PointerDeviceTests` with the result bundle `.build/Runs/T05-baseline.xcresult`. It took 302 s, and all 314 tests passed. The open of the empty card had 0 late frames in this run, so the expected failure of D-125 did not show.

| Step | Median | Slowest | Steps |
|---|---|---|---|
| Erase | 25.62 ms | 26.32 ms | 5 |
| Undo | 17.69 ms | 20.52 ms | 5 |
| Redo | 22.88 ms | 24.32 ms | 5 |

The main-thread calls of `EraseUndoPerformanceTests` took 5.0 to 13.3 ms.

The open of the D-56 canvas (`CanvasOpenPerformanceTests`) took a median of 256.3 ms and at most 262.4 ms over 10 opens, from the tap to the first frame. The load part took 70.4 to 84.2 ms. The memory of the open canvas was 339 MB held and 352 MB at the peak. The transition between two D-56 canvases (`TransitionMemoryPerformanceTests`) held 223 MB for the parent, 352 MB at the peak of the open, 296 MB after the open, and 433 MB at the peak of the leave, and it freed the parent.

| Card flight | Time | Frames | Late | Held |
|---|---|---|---|---|
| Open of the D-56 card | 468 ms to the child | 56 | 0 | 0 |
| Leave of the D-56 card | 592 ms | 2 child, 43 parent | 0 | 0 |
| Open of the empty card | 478 ms to the child | 57 | 0 | 0 |
| Leave of the empty card | 487 ms | 2 child, 43 parent | 0 | 0 |
| Open, main thread blocked | 468 ms to the child | 56 | 0 | 0 |
| Leave, main thread blocked | 492 ms | 2 child, 43 parent | 0 | 0 |

Each frame loop of `FrameLoopTests` ran at 120.0 fps with 0 late frames of 479. The main-thread time is the time per frame on the main thread.

| Frame loop | Main ms, mean / p99 / max | Render ms, p50 / max | GPU ms, p50 / max | Allocations, p50 / p99 / max | Uncovered |
|---|---|---|---|---|---|
| few pan | 0.00 / 0.02 / 0.04 | 0.16 / 0.26 | 0.34 / 1.59 | 17 / 29 / 43 | 0 / 480 |
| dense 20k pan | 0.01 / 0.03 / 0.06 | 0.20 / 2.88 | 0.37 / 2.60 | 17 / 2,413 / 2,640 | 0 / 480 |
| dense 20k fast pan | 0.00 / 0.03 / 0.03 | 0.20 / 2.85 | 0.35 / 2.55 | 17 / 2,325 / 2,737 | 0 / 480 |
| dense 20k zoom | 0.01 / 0.03 / 0.06 | 0.19 / 2.79 | 0.38 / 2.99 | 17 / 2,100 / 2,255 | 0 / 480 |
| handwriting 200k pan | 0.00 / 0.03 / 0.03 | 0.20 / 2.20 | 0.38 / 5.04 | 17 / 2,168 / 2,181 | 0 / 480 |
| handwriting 200k zoom | 0.01 / 0.03 / 0.04 | 0.18 / 2.13 | 0.35 / 5.02 | 17 / 2,161 / 2,181 | 0 / 480 |
| D-56 text pan | 0.00 / 0.02 / 0.05 | 2.18 / 3.49 | 0.81 / 2.92 | 50 / 2,224 / 3,025 | 137 / 480 |
| D-56 text zoom | 0.01 / 0.01 / 0.07 | 2.20 / 3.57 | 0.84 / 3.49 | 50 / 2,119 / 3,024 | 0 / 480 |
| D-56 cards pan | 0.00 / 0.01 / 0.01 | 0.44 / 2.26 | 0.68 / 4.99 | 238 / 9,527 / 9,533 | 0 / 480 |
| D-56 cards pan at zoom 1 | 0.00 / 0.01 / 0.03 | 0.13 / 2.54 | 0.67 / 6.97 | 88 / 2,613 / 2,621 | 0 / 480 |
| D-56 cards zoom | 0.00 / 0.00 / 0.01 | 0.38 / 3.17 | 0.70 / 4.96 | 220 / 5,900 / 8,509 | 0 / 480 |

The preview render of D-56 took 30.9 ms. The eraser frame took 0.12 ms on the CPU and 0.30 ms on the GPU at the median, and at most 0.21 and 0.60 ms.

| Allocation test | Count |
|---|---|
| `FrameAllocationTests` | frame p50 15, bare Metal frame p50 15 |
| `TransitionAllocationTests`, flight frame | p50 15, bare frame p50 15 |
| `TransitionAllocationTests`, open frame | p50 15, bare frame p50 15 |
| `PreviewAllocationTests` | card pass p50 2, bare pass p50 2 |
| `TextPassAllocationTests` | text pass p50 2, bare pass p50 2 |
| `TextMoveAllocationTests`, move step | median 6 |
| `EditAllocationTests` | `FrameRenderer.apply`: erase 14, undo 2, redo 1 |
| `EraserSampleAllocationTests`, canvas samples and mask samples | 0, the test fails above 0 |
| `GridAllocationTests`, 1,000 removals | 0, the test fails above 0 |

`TextMoveAllocationTests.testEditedTextGetsANewLayout` checks the layout, not a count.

### 6.3 Measures of the pen tool (task 3.1)

Measured on 2026-10-23 on the iPad in Release. Commit cab4bd9.

`FrameLoopTests` is in `Rendering` and never runs `applyCamera()`, so the product owner decided D-134: the frames of the canvas screen in the new `ZoomFrameAllocationTests` decide, and the `dense 20k zoom` loop is recorded only. Before the change, that loop gave main ms mean 0.00, p99 0.02, and max 0.03. After it, in the full run of `make check`, it gave mean 0.01, p99 0.03, and max 0.04, at 120.0 fps with 0 late frames of 479.

`ZoomFrameAllocationTests` steps the frame callback of a root canvas screen through a spring of 52 frames after a pinch past the minimum zoom, and through a glide at one zoom. Before the change, a spring frame made 139 allocations at the median and 141 at most. The line `liveCanvas.tool = PenTool.inkingTool(zoom:)` alone made 139, so the tool made all of them. A glide frame made 0.

Alternating runs in a worktree of commit 09044e4, in the order base, new, base, new, each with 5 iterations:

| Build | Allocations of a spring frame, median | Main thread of a spring frame, median | Slowest frame |
|---|---|---|---|
| Base | 139 | 26.5 to 34.9 µs | 30.0 to 56.1 µs |
| New | 0 | 0.2 to 0.3 µs | 37.5 to 63.1 µs |

After the change, each zoom frame makes 0 allocations. The last frame of the spring brings the camera to rest and makes the one tool of the new zoom, so the slowest frame is that frame. Before the change, every frame of the spring cost as much.

`PenToolZoomTests` checks the width of a new canvas, the width at a pencil down during a spring, and the width at rest. Before the change, the test of the pencil down failed with "No new tool at a zoom frame", and `ZoomFrameAllocationTests` failed with "Optional(140) is not equal to Optional(0)". After it, both suites passed 4 of 4 in 3 iterations, and `PencilKitParityTests`, `LiveStrokeHandoffTests`, `PencilKitStrokeConverterTests`, `CameraControllerTests`, `CameraRestTests`, `TransitionTests`, `NavigationTests`, and `CanvasViewControllerTests` passed.

No test can make a pencil touch, so no test shows whether PencilKit reads its tool before `pencilBegan()` sets it. The converter takes the width that PencilKit drew. Phase 4 checks it by hand: a stroke drawn while two fingers still pinch must have the width of the other strokes at that zoom.

Close of task 3.1, with the code of commit cab4bd9. After a touch of the changed Swift files, `make build` printed 0 lines with `warning:`. `make check` passed with the iPad: `analyze` with 0 findings, 350 of 350 tests of `PointerDeviceTests` in 319 s, 48 of 48 snapshots, and `format`, `lint`, `layers`, `density` with Rendering at 2.00, `self-test`, and `plist`. The full run gave erase 21.70 ms, undo 19.13 ms, and redo 19.27 ms at the median. `make coverage` passed: Geometry 90.80 %, Model 90.80 %, InkEngine 92.73 %, Persistence 91.15 %, and Rendering 86.98 %. Only `EraseUndoPerformanceTests` failed in its instrumented run, which the target ignores (D-120).

Manual check of task 3.1, 2026-10-23. The product owner pinched, kept both fingers on the screen, drew a stroke, lifted, and drew a second stroke. The widths differed. The build before task 3.1 (commit 09044e4), installed for the check, also gave different widths past the smallest zoom, and the canvas sprang back while the line was drawn. Two faults came out:

1. Past a zoom limit, `pencilBegan()` ends the pinch, and the end of the pinch started the spring back under the pencil. This fault is older than M7. The product owner decided D-135: the camera holds while the pencil draws, and the spring back starts after the handoff of the pen stroke, or at the lift for the other tools. Commit 436fe7b. `SpringHoldTests` failed without the hold with "The camera moves under the pencil" in 3 tests, and passed with it.
2. Inside the zoom range, a stroke during a running pinch came out thicker. The product owner reported: "When starting at 1, zooming out within the range and drawing a line, then the line is thicker than the default." PencilKit takes its tool before `pencilBegan()` runs, so the stroke got the width of the last rest. This was a regression of commit cab4bd9, because the code before it set the tool at each pinch sample. `CanvasView.hitTest(_:with:)` now sets the pen width for each new touch, before any gesture recognizer gets it. Commit 194959c. The test `hitTestDuringPinch` failed before the fix and passed after it.

A probe on the iPad gave `PKInkingTool.InkType.monoline.validWidthRange` as 0.5 to 4.0. The product owner drew at zoom 8 with the same width as at zoom 1, so PencilKit does not clamp the drawing at 4.0. After both fixes, the product owner repeated the checks inside the range, past the smallest zoom, and past the largest zoom, and reported: "That fixed it. Everything is at the same width."


### 6.4 Manual tests (tasks 2.5 and 4.1)

Task 2.5, on 2026-10-23 on the iPad with the Apple Pencil Pro, with the code of commit 3739e40. The product owner hovered with the pen, the eraser, and the text tool on the root canvas and reported: "Works as expected." Inside a card, and with "Show Hover Preview" off in Settings, the product owner reported: "It works in cards, and are correctly disabled when setting are disabled." On 2026-10-23, the product owner accepted the start tokens: "Yes, they are fine with me." The tokens stay: a dot radius of 2 view points, a ring width of 1 view point, and the gray of `chromeSecondary`. Task 2.5 is done.

Task 4.1, on 2026-10-23 on the iPad with the Apple Pencil Pro. The product owner ran acceptance 1 to 4 and reported: "1 - 4 is good." Acceptance 1, the double-tap settings, acceptance 2, the squeeze palette at the tip on the root canvas and inside a card, acceptance 3, the work with double tap and squeeze set to "Ignore", and acceptance 4, the haptics, all pass. The fifth check, the pen width after a zoom, is in section 6.3. It passes after commits 436fe7b and 194959c.

### 6.5 Close (phase 5)

Measured on 2026-10-23 on the iPad in Release.

Five full runs of `PointerDeviceTests` in a row with the code of commit 194959c (bundles `.build/Runs/P5-full1` to `P5-full5`) took 300 to 309 s. One run passed all 356 tests. Four runs failed 1 or 2 tests: a late frame at place 0 or 1 of the leave of the empty card (2 runs), of the open with a blocked main thread (2 runs), and of the leave of the D-56 card (1 run), and one save of 50.34 ms in `testSnapshotOfTwentyThousandStrokesWithSaves` against its limit of 50 ms. Alternating full runs gave the same late frame for the code before phase 1 (550aaef) in 1 of 2 runs, so M7 did not cause it (D-136). The trace of D-136 and D-137 found that frames 0 to 2 of each leave wait 1 to 4 ms for the GPU while the driver wires new memory. D-137 records the four experiments. No fix went into the code, and M10 traces the rest of the wait.

The measures of the five runs, against the baseline of section 6.2. A value is the median of the five runs, and the range follows it.

| Measure | Baseline | Phase 5 | Change |
|---|---|---|---|
| Erase, median | 25.62 ms | 20.86 ms (19.71 to 25.18) | 19 % faster |
| Erase, slowest | 26.32 ms | 25.65 ms (22.51 to 29.05) | 3 % faster |
| Undo, median | 17.69 ms | 18.17 ms (17.17 to 19.45) | 3 % slower |
| Undo, slowest | 20.52 ms | 20.21 ms (19.05 to 21.12) | 2 % faster |
| Redo, median | 22.88 ms | 20.27 ms (16.05 to 22.01) | 11 % faster |
| Redo, slowest | 24.32 ms | 23.42 ms (18.97 to 25.99) | 4 % faster |
| Open of the D-56 canvas, median | 256.3 ms | 258.5 ms (257.1 to 265.8) | 1 % slower |
| Open of the D-56 canvas, slowest | 262.4 ms | 268.8 ms (266.6 to 284.0) | 2 % slower |
| Memory of the open canvas, held | 339 MB | 353 MB (335 to 354) | 4 % more |

Each frame loop of `FrameLoopTests` had 0 late frames in each run. The largest main-thread time of a frame was 0.09 ms, and the mean stayed at 0.00 to 0.01 ms. The transition memory held 223 to 224 MB for the parent, 349 MB at the peak of the open, 292 MB after the open, and 430 to 431 MB at the peak of the leave, and it freed the parent. No measure is more than 10 % slower than the baseline (code-of-code.md section 5, item 10).

`AppMessageTests` "A message shows while the palette is open" failed in `make check` once and in one traced run. It fails in each repetition after the first of `-test-iterations`, also on the code before M7, so M7 did not cause it. M10 holds it.

Close, with the code of commit 9aad697. After a touch of the changed Swift files, `make build` printed 0 lines with `warning:`. `make check` passed with the iPad: `analyze` with 0 findings, the Tier A tests, 356 of 356 tests of `PointerDeviceTests` in 323 s, 48 of 48 snapshots, and `format`, `lint`, `layers` with 0 findings, `density` with Rendering at 2.00, `self-test`, and `plist`. `make coverage` passed: Geometry 90.80 %, Model 90.80 %, InkEngine 92.73 %, Persistence 91.15 %, and Rendering 86.97 % (5,978 of 6,874 lines). Only `EraseUndoPerformanceTests` failed in its instrumented run, which the target ignores (D-120). No folder is new, so the context map of `AGENTS.md` stays (AGENT-07).

### 6.6 Navigation faults (tasks 0.2 to 0.4)

Measured on 2026-10-22 on the iPad in Release. Each test ran first on the code before its fix and failed, then on the fixed code and passed. The tests are in `PointerAppTests/NavigationFailureTests.swift` and `PointerAppTests/PreviewStopTests.swift`.

Task 0.2, commit 27e09ba. The test `failedOpenKeepsSession` takes the app off the window during an open, so the child with one stroke never draws, and the open fails after `makeCanvas` with `FirstFrameTimedOut`. Without the stroke, the open of the empty child did not fail without a window. The test then draws a stroke on the parent, switches the workspace, and switches back. Before the fix, the parent had 0 undo steps after the switch back ("shown.history.undoSteps.count → 0"), and the undo left the stroke. The fix is the smaller of the two changes of the task: `cancelCardTransition` calls the new `resumeSession()`. It takes the saved copy out of the sessions and clears `hasEndedSession`, so that the screen owns its history alone again. A session that `discardSession()` dropped stays dropped (M-03). `makeCanvas` still ends the session before the new screen reads the sessions (F-02). After the fix, the test passed, and `NavigationTests`, `DeepTreeTests`, `CanvasSwitchTests`, and `NavigationCancelTests` passed.

Task 0.3, commit 19f0904. The test `leaveWithoutParentCard` deletes the card of the child in the repository, then leaves, then opens a card inside the child. The test `openWithoutScreen` sets the clock of the composition to `nil`, so `makeCanvas` gives `nil`, then opens the card again with the clock. Before the fix, both failed with "Expectation failed: hasEnded: The failed navigation still runs" after 15 s, because `opening` stayed set. Now each return in `loadChild` and `loadParent` that is not a cancel calls `fail(_:on:)`, and both tests see the message `AppStrings.canvasFailed`. `loadParent` checks the card before `makeCanvas`, so it makes no screen without the card. After the fix, both tests passed with the tests of task 0.2, `NavigationTests`, `DeepTreeTests`, `CanvasSwitchTests`, `NavigationCancelTests`, and `PinchCancelTests`.

Task 0.4, commit 7607388. The fault exists. The test `stoppedRenderThread` starts the preview render of a leave and takes the child view out of the window at once, so the render thread stops. Before the fix, the completion did not run in 3 s ("Expectation failed: isDone: The completion of the preview render did not run"). The test does not show whether the request still waited in the inbox or ran as a job, so the fix ends both. Now the stop block of `RenderThread` calls `RenderEngine.endPreviewRender()` after the link stops. It takes the waiting request and the running job out under their locks, and calls their completions with `nil` after the locks. After the fix, the test passed, and `PreviewWriteTests`, `PreviewRenderTests`, `CanvasLifetimeTests`, and `NavigationFailureTests` passed.

Close of phase 0, 2026-10-22, with the code of commit 7607388. `make check` passed with the iPad: `build`, `analyze` with 0 findings, `test` with the Tier A tests and all of `PointerDeviceTests`, `snapshots`, `format`, `lint`, `layers` with 0 findings, `density`, `self-test`, and `plist`. `make coverage` passed: Geometry 90.80 % (474 of 522 lines), Model 90.80 % (1,293 of 1,424), InkEngine 92.73 % (625 of 674), Persistence 91.15 % (2,163 of 2,373), and Rendering 86.87 % (5,957 of 6,857). In the instrumented run of `make coverage`, `EraseUndoPerformanceTests` failed, and the target ignores that failure by design (D-120).

A full build of the `Rendering` package prints one warning: `FrameRenderer+PreviewRender.swift:116:25: warning: capture of 'renderer' with non-Sendable type 'PreviewRenderer' in a '@Sendable' closure [#SendableClosureCaptures]`. The build of the code before task 0.4 prints the same warning, and `make build` exits with 0. The build of `make check` was incremental, so it did not compile that file again. Item 1 of the checklist of code-of-code.md section 5 asks for zero warnings. Section 6.7 gives its fix.

### 6.7 The build warning of the preview readback

The product owner asked on 2026-10-22 to fix the warning of section 6.6, to research it first, and to benchmark the solutions.

Research. `FrameRenderer.finishPreview` captured the `PreviewRenderer` in the completion handler of the command buffer, to read the shared readback buffer on a thread of Metal. `PreviewRenderer` is not Sendable. The compiler of `Rendering` got `-warnings-as-errors` and `-swift-version 6`, but the build passed with the warning. A probe with the same flags showed that the same capture in a Swift `@Sendable` closure is an error, and in the Metal handler, which the header marks `NS_SWIFT_SENDABLE`, it is a warning only. `any MTLBuffer` is not Sendable either, so a capture of the buffer alone gives the same kind of diagnostic. The shared buffer had a second risk: no rule stopped the blit of a later preview from writing the buffer while the handler of the earlier one still read it. No test showed this race. D-132 asks how the build can stop such warnings.

Three solutions, each in a worktree of commit 573a872:

- A: the shared buffer in a private `@unchecked Sendable` box in `PreviewRenderer+Unsafe.swift` (SAFE-09), with a semaphore, so that the render thread blits into the buffer only after the read.
- B: no handler. The render thread checks the status of the command buffer at each frame and reads the image itself.
- C: a new shared buffer of `width * height` bytes for each preview, which the handler owns alone, in a private box.

Benchmark: `FrameLoopTests/testPreviewRenderOfD56` with `-test-iterations 10`, in the order base, A, B, C, base, A, B, C, so 20 previews each, from the request to the image. The times fall at about 30, 39, and 48 ms, the frames of the display, so the quartiles count more than the median.

| Build | Median | Quartiles | Range | Slowest frame on the render thread | Late frames |
|---|---|---|---|---|---|
| Base | 38.0 ms | 30.4 to 39.0 ms | 28.8 to 47.8 ms | 2.36 ms | 0 |
| A | 38.1 ms | 30.1 to 39.2 ms | 29.5 to 48.1 ms | 2.38 ms | 0 |
| B | 41.8 ms | 41.7 to 41.9 ms | 33.4 to 50.2 ms | 2.36 ms | 0 |
| C | 34.5 ms | 30.1 to 39.2 ms | 29.2 to 47.9 ms | 2.31 ms | 0 |

The largest allocation count of a frame was 1,247 to 1,256 in each build. Each variant passed `PreviewRenderTests`, `PreviewStopTests`, `PreviewWriteTests`, and `OpenAnimationTests`, 10 of 10 tests. Each variant built with 0 warnings. B needed one more frame for each preview and broke the function body limit. A and C cost nothing that the benchmark shows.

Decision of the agent on the request of the product owner: C. It holds no new state and no skip path, and its safety does not depend on timing: the handler is the only owner of its buffer, so no later preview writes it. The offscreen preview of `FrameRenderer+Image.swift` keeps the shared buffer of its own `PreviewRenderer`, because it waits for the GPU on its own thread.

### 6.8 Double tap (tasks 1.1 to 1.3)

Measured on 2026-10-22 on the iPad in Release.

Task 1.1, commit 9d9bc65. `ToolSwitch.tool(after:action:)` follows D-130. Each value that D-130 does not name gives `nil`, also through `@unknown default`. `ToolSwitchTests` covers the 7 values of the SDK with each tool, and the raw values 7, 8, and 99 of a later SDK. 5 tests with 29 runs passed.

Task 1.2, commit e8655b7. `pencilInteraction(_:didReceiveTap:)` reads `preferredTapAction` at each tap and calls `doubleTap(action:)`, which calls `select(_:)`. `DoubleTapTests` checks the tool, the button, the drawing gesture, the end of a text edit (D-87), and a tap during a pencil touch (D-70). 29 tests with 53 runs passed, with `TextEditTests`, `ToolPaletteTests`, and `ToolStateTests`.

Task 1.3, commit 75945ba. During an open, the child waits above the parent at opacity 0, in the window, with interaction on. A check of `view.window` and `isUserInteractionEnabled` thus does not stop it, so the smaller change that works is a flag. `CanvasViewController.isShownCanvas` is `true` only for the canvas of `AppViewController`, and a tap and a squeeze act only on the shown canvas outside a flight. The test `PencilFlightTests` failed before the gate: both screens switched to the eraser ("screen.tool → .eraser"), and the palette opened ("The palette opened"). With the gate, it passed, with `DoubleTapTests`, `ToolPaletteTests`, `TransitionTests`, `PinchCancelTests`, and `NavigationTests`: 23 of 23 tests.

### 6.9 Hover dot (tasks 2.1 to 2.4)

Measured on 2026-10-22 on the iPad in Release.

Task 2.1, commit 87f8a47. The product owner decided D-133: the eraser circle is an outline ring. `HoverDot.mark` gives a filled dot for the pen and the text tool, and a ring with `EraserTool.radius` for the eraser. The start tokens are `DesignSystem.Color.hoverDot` (the gray of `chromeSecondary`), `Size.hoverDotRadius` of 2 view points, and `Size.hoverRingWidth` of 1 view point. `HoverDotTests` passed: 6 tests with 15 runs.

Task 2.2, commit 9eeafd9. `HoverDotLayer` is a `CAShapeLayer` above the live canvas, with both paths made once. Its actions hold `NSNull` for each changed key, because an empty dictionary leaves the default animations on. The canvas view also holds the hover recognizer of `UIPencilInteraction`, so the new `UIHoverGestureRecognizer` recognizes together with every recognizer. A test cannot make a hover event, so task 2.5 checks on the device that the dot and the squeeze palette both work. `HoverTests` passed with `TextEditTests`, `CameraControllerTests`, `PalmGuardTests`, `CardTapTests`, `DoubleTapTests`, `PencilFlightTests`, `CanvasViewControllerTests`, and `ScribbleConditionTests`: 53 of 53 tests.

Task 2.3, commit 592ed42. `HoverSampleAllocationTests` counts 1,023 hover samples of the pen and of the eraser on the main thread, with a commit of Core Animation after each 16 samples. Both counted 0 allocations, and the bare layer move counted 0. With a probe that kept a string at each sample, the tests failed with 1,918 and 1,919 allocations, so the counter sees the code. The signpost interval "Hover" of `CanvasSignpost` times each sample.

Task 2.4, commit 989150a. `HoverDotSnapshotTests` renders the canvas view with the dot of the pen and with the eraser circle. The iPad made the references `hover-dot-pen.png` and `hover-dot-eraser.png`. The second run passed 2 of 2. The `snapshots` target of the `Makefile` runs the class.

Close of tasks 1.1 to 2.4, with the code of commit 989150a. After a touch of the 18 changed Swift files, `make build` printed 0 lines with `warning:` (D-132). `make check` passed with the iPad: `build`, `analyze` with 0 findings, `test` with the Tier A tests and 345 of 345 tests of `PointerDeviceTests` in 325 s, `snapshots` with 48 of 48, `format`, `lint`, `layers` with 0 findings, `density` with Rendering at 2.00, `self-test`, and `plist`. The open of the empty card had no late frame in this run. `make coverage` passed: Geometry 90.80 %, Model 90.80 %, InkEngine 92.73 %, Persistence 91.15 %, and Rendering 87.04 % (5,983 of 6,874 lines). In its instrumented run, only `EraseUndoPerformanceTests` failed, which the target ignores (D-120). The full run of `make check` gave erase 21.01 ms, undo 17.09 ms, and redo 21.64 ms at the median, against 25.62, 17.69, and 22.88 ms in the baseline of section 6.2. Phase 5 compares all measures over 5 runs.

Fix after the close, commit 3739e40. On 2026-10-23, the product owner hovered on the iPad and reported: "The eraser is the same shape and color as the other tools. This indicator was present before the attempt of implementing hover indicator." Only the indicator of PencilKit showed, so the dot of Pointer did not. Task 2.2 made the canvas controller the delegate of the hover recognizer, and its `gestureRecognizer(_:shouldReceive:)` refuses every touch that is not a finger. UIKit delivers a hover as a pencil touch. The Mac needs root to read the logs of the iPad, so the check was the device itself. `PencilHoverRecognizer` is now its own delegate with the simultaneous rule only. The test `receivesPencilTouches` failed before the fix, because the delegate responded to `gestureRecognizer:shouldReceiveTouch:`, and it passed after it. With the fixed build, the product owner hovered again and reported: "Works as expected."

In the first run after the fix, with 9 other suites, `HoverSampleAllocationTests` counted 1 allocation of the eraser in one batch. Alone it counted 0 in 20 of 20 runs, and in the full runs of `make check` it counted 0. The cause of the one count is not known.

Second close, 2026-10-23, with the code of commit 3739e40. After a touch of the changed Swift files, `make build` printed 0 lines with `warning:`. `make check` passed with the iPad: `analyze` with 0 findings, 345 tests of `PointerDeviceTests` passed with 0 failures and 1 expected failure of D-125, `snapshots` passed 48 of 48, and `layers`, `density`, `format`, `lint`, `self-test`, and `plist` passed. `make coverage` passed: Geometry 90.80 %, Model 90.80 %, InkEngine 92.73 %, Persistence 91.15 %, and Rendering 86.91 %. Only `EraseUndoPerformanceTests` failed in its instrumented run, which the target ignores (D-120). The full run gave erase 21.50 ms, undo 18.84 ms, and redo 17.91 ms at the median.
