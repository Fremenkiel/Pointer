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

### 6.2 Baseline (task 0.5)

### 6.3 Measures of the pen tool (task 3.1)

### 6.4 Manual tests (tasks 2.5 and 4.1)

### 6.5 Close (phase 5)
