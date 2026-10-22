# M6 fix plan: coverage, late frames, and step speed

This document gives a new agent the work that closes three open items of the M6 close of 2026-10-22. Each item has the research that found it, the sources, a fix, and a target. The results of M6 are in [m6-plan.md](m6-plan.md) section 6. The acceptance criteria of M6 stay in [plan.md](plan.md).

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

## 1. How to work

### 1.1 Device and build

1. Use only the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator, and never make one (learned rule 1 of `AGENTS.md`).
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. If it prints `passcodeRequired: true`, stop and ask the product owner to unlock the iPad.
3. The iPad locks during long builds. Ask the product owner to keep it unlocked.
4. Run one device suite with this command. Replace `<Suite>` and `<Name>`.

```
xcodebuild test -project Pointer.xcodeproj -scheme PointerApp -configuration Release \
  -destination 'id=00008132-000018993E8B801C' -derivedDataPath .build/DeviceData \
  -allowProvisioningUpdates ENABLE_TESTABILITY=YES \
  -only-testing:PointerDeviceTests/<Suite> -resultBundlePath .build/Runs/<Name>.xcresult
```

5. `-only-testing` takes the name of a Swift Testing suite type or an XCTest class. Add `-test-iterations N` to repeat a suite.
6. The package tests of the Tier A packages run on the Mac with `swift test --package-path Packages/<Package>`. The other packages build for iOS only, so their tests run in `PointerDeviceTests` (D-77).

### 1.2 Reading the results

The tests write their measures as activity titles. To read them, list the test cases with `xcrun xcresulttool get test-results tests --path <bundle>`. Then read each case with `xcrun xcresulttool get test-results activities --test-id <id> --path <bundle>`, and print the titles that hold digits. The earlier sessions used a small Python script for this, run with `python3 -I`. To export attachments, such as new snapshot images, run `xcrun xcresulttool export attachments --path <bundle> --output-path <folder>`, and read `manifest.json` in that folder.

### 1.3 Speed comparisons

Compare two builds only with alternating runs on the iPad (section 4 of m6-plan.md). Use a separate worktree for the older build, with its own derived data:

```
git worktree add -f .build/Base/tree <commit>
```

Then run the same suite in the order base, new, base, new, with the same `-test-iterations`. When you are done, remove the worktree. A Swift Testing suite runs its tests at the same time, and a full run runs the suites at the same time. A test that needs the key window or the main thread alone must use `.serialized`.

## 2. Research and sources

### 2.1 Item 1: the coverage of the device packages

TEST-02 needs 90 % line coverage for each Tier A package and 70 % for Tier B. The M6 close measured it by hand.

1. Tier A runs on the Mac: `swift test --enable-code-coverage` in each package, then `swift test --show-codecov-path` gives the JSON. On 2026-10-22: Geometry 91.06 %, Model 90.88 %, InkEngine 92.73 %, Persistence 91.23 %.
2. The Persistence number leaves out `Sources/PersistenceCrashHelper`. That target is an executable that the crash test starts as a separate process (D-54), so in-process coverage cannot count it. With it, Persistence has 89.31 %.
3. Rendering is Tier B. Its tests run on the iPad only. `-enableCodeCoverage YES` alone did not instrument the packages, also not in Debug. The report of `xccov` lists each package with 0 files.
4. Each package is a framework of its own in `Pointer.app/Frameworks/<Package>_<hash>_PackageProduct.framework`. A run with `-enableCodeCoverage YES` and `OTHER_SWIFT_FLAGS='$(inherited) -profile-generate -profile-coverage-mapping'` instruments them. An extra `OTHER_LDFLAGS=-fprofile-instr-generate` breaks the link with `unknown argument`.
5. After that run, `xcrun llvm-cov export <framework binary> -instr-profile <derived data>/Build/ProfileData/<UDID>/Coverage.profdata -summary-only` gives the coverage of the package. Count the lines of the files under `/Sources/`. On 2026-10-22: Rendering 86.69 % (5,821 of 6,715 lines), CanvasFeature 77.80 %, WorkspaceFeature 78.37 %.
6. The instrumented code is slower, so one performance test failed in that run (`EraseUndoPerformanceTests`). The measures of a coverage run do not count.

Sources: m6-plan.md section 6.2, commit b2e6d76, the `Makefile` (targets `test` and `snapshots`), and code-of-code.md TEST-02 and section 5.

### 2.2 Item 2: the late frame in the open and the leave of a card

The close runs of D-79 had 1 late frame in the open of an empty card in 2 of 5 runs (`OpenAnimationTests.testOpenAndLeaveOfEmptyCardHaveNoLateFrame`). If the interval between two presented frames is over 12.5 ms, the frame is late (`FrameLoopReport.lateIntervalMilliseconds`).

What the research found, in order:

1. In runs of `OpenAnimationTests` with 10 iterations, the late frames fall almost only in the empty card test, in the open and in the leave. The leave of the D-56 card had them in 3 of 40 events. The open of the D-56 card had none.
2. These causes were ruled out by experiment:
   - The state of the iPad: the build before task 4.8 (182dde0) showed the same late frames.
   - The `malloc_logger` hook of `AllocationCounter`: runs with the count off had the same late frames.
   - Background preview renders of `PreviewFiles`: none ran at the start of the test.
   - The canvas of the test host app in the same window: removing it did not help.
3. The late gap is always the second interval of the parent's animation, 16.7 to 33.3 ms long. The interval positions were printed from `FrameLoopReport.intervals`.
4. Time marks in `AppComposition.loadChild` showed this order for an empty card:
   - The content loads 0.1 to 0.6 ms after the tap.
   - `makeCanvas` blocks the main thread for 3 to 10 ms.
   - `container.showAbove` blocks it for 1.3 to 3.8 ms more.
   A frame at 120 Hz is 8.33 ms.
5. An experiment made the child screen only after the flight. The gap then moved with it, to intervals 41 and 42 at the end of the flight. This is the proof for the open.
6. The cause: the main thread steps the camera of the flight. `InkView.onFrame` calls `CanvasViewController.stepCamera(to:)` (`CanvasViewController.swift:177` and `:319`). That calls `CameraController.step(to:)`, then `applyCamera()` sets `renderer.camera`, and `stepCardTransition()` sets the parent weight (`CanvasViewController+Transition.swift:55-75`). The render thread waits at most `RenderEngine.cameraWaitBudget` (3 ms, `RenderEngine.swift:18` and `:89`) for a new camera. Without one, the frame has no change and presents nothing. Main-thread work of more than one frame therefore stops the animation.
7. In the leave, the gap is at the start of the parent's flight. That flight starts in the completion of `AppViewController.fadeOut`. The same main-thread step removes and frees the child screen and starts `runLeave` (`CanvasViewController+Transition.swift:156`). Deferring only the removal did not remove the gap, so other main-thread work there also blocks it. A fix that does not depend on the main thread covers all of these.
8. The flight has a closed form. `CameraController.Flight`, `progress(of:)`, and `camera(of:)` (`CameraController.swift`, from line 30 and line 236) compute the camera from the elapsed time alone. It is a critically damped spring, stiffness 9.23, duration 0.35 s, with the zoom on a log scale (D-98).

Sources:

- m6-plan.md section 6.3.1, and architecture.md sections 6.2 and 6.3.
- Decisions D-98, D-108, D-109, and D-110.
- `RenderEngine.swift`, `RenderInbox.swift`, `CanvasRenderer.swift:29` (the camera setter), and `CanvasRenderer+Transition.swift`.
- `PinchExit.swift`, `FrameTransition.swift`, and `PointerAppTests/OpenAnimationTests.swift`.

### 2.3 Item 3: the slower tail of the redo

The slowest redo of the close runs was 30.10 ms against 26.53 ms in the baseline of m6-plan.md section 6.1. The budget of M4 acceptance 2 is 33 ms (D-69, D-75). The test is `EraseUndoPerformanceTests` (Packages/CanvasFeature/Tests/CanvasFeatureTests). It times each step from the call until the GPU completes the first frame that holds the result (D-74).

What the research found:

1. Alternating runs of 3 times 3 iterations, base 7284f4e against HEAD:
   - The median redo was the same: 22.60 against 22.75 ms.
   - The largest redo was the same: 30.89 against 31.14 ms.
   - Only the median of the slowest redo per run rose: 24.18 to 29.86 ms.
   A step ends at about 22 ms or at about 30 ms, one frame apart. The tail thus depends on where the step falls relative to the frame.
2. A code review of `git diff 7284f4e..HEAD` found no extra pass, encoder, clear, or wait on an ink-only redo. The new work per frame is under 0.1 ms: `cardDelta`, `requestPreviews`, `applyCards`, and the nil checks of the transitions.
3. On the main thread, a redo call took a median of 5.5 ms against 5.3 ms in the base. The test records it in `callMilliseconds`.
4. Time marks in `CanvasViewController.runStep` (`CanvasViewController+History.swift`) split a redo of 3,170 rows:
   - `history.redo` on the content: 4.0 to 5.1 ms. An undo took 4.7 to 7.9 ms.
   - `textDelta` and `cardDelta`: 0.15 to 0.30 ms.
   - `renderer.change`: about 0.03 ms.
   - `send(rows)`: under 0.01 ms.
   - `historyDidChange`: about 0.1 ms.
5. `renderer.change` comes after `history.redo`. The render thread therefore starts about 5 ms after the call. The erase does the same in `finishErase` (`CanvasViewController+Eraser.swift`): `perform(command)` comes before `renderer.change`.
6. `renderDelta(of:isUndo:)` already gives the change from the command for `EraseStrokes` and `AddStroke`, without the content (P-06 of m4-fix-plan.md).
7. The model step is `EraseStrokes.apply` and `revert` (`EraseStrokes.swift:50` and `:85`). They call the batch `remove` and `restore` of `CanvasContent` (`CanvasContent.swift` from line 160). These change `strokes` and `erased`, two dictionaries of about 20,000 entries, and write a `ChangeLog` and one `LibraryChange` per stroke. 4 to 5 ms for 3,000 strokes is about 1.5 µs per stroke, which is high for two dictionary operations. No profile of it exists yet. One hypothesis to test first: if a second reference to the content exists during the step, the step makes a copy-on-write copy of a whole dictionary.

Sources: m6-plan.md section 6.3.1, m4-fix-plan.md phase 3 (P-01 to P-10), m4-plan.md section 4.6, plan.md M4 acceptance 2, and the files named above.

## 3. Decisions for the product owner

Raise these as open entries in [decisions.md](decisions.md) before the task that needs them. Do not decide them yourself (AGENT-04).

1. D-120: does `make check` run the coverage of item 1? A coverage run is one more full device run, and its measures do not count. Recommendation: a separate target `make coverage`, which the pull request checklist of code-of-code.md section 5 names.
2. D-121: the render thread computes the camera of a flight (item 2). This changes architecture.md section 6.2: the main thread no longer drives the frames of a flight. Recommendation: yes, as in task 2.2.
3. D-122: undo, redo, and the erase hand the change to the renderer before the model step (item 3). If the model step then fails, the renderer gets the reverse change, and the screen can show the wrong ink for one frame. Recommendation: yes, as in task 3.2.

## 4. Tasks

### Phase 0: measurement base

#### 0.1 Baseline of the current code

1. Note the commit of the start. Run `OpenAnimationTests` with `-test-iterations 10` twice, and `EraseUndoPerformanceTests` with `-test-iterations 3` three times.
2. Record the late frames per event type, the open and leave times, and for each step the median, the slowest, and the main-thread call time.

Done when: section 6 of this plan holds the baseline.

Status (2026-10-22): done, section 6.1. The empty card had late frames in 3 of 20 opens and 3 of 18 leaves, the D-56 card in 1 of 20 leaves. The slowest steps were 32.95 ms (erase), 30.34 ms (undo), and 31.56 ms (redo).

### Phase 1: coverage (item 1)

#### 1.1 A coverage target

1. Raise D-120 and wait for the decision.
2. Add `Scripts/coverage.swift`. It reads the coverage of each package and fails below its limit.
   - Tier A: from the JSON of `swift test --enable-code-coverage`, the files under `Sources/<Package>/`. Leave out `PersistenceCrashHelper`, and name the reason in a comment.
   - Tier B (Rendering): from `llvm-cov export` of the framework binary and the profile data of a device run with the flags of section 2.1 item 4.
   - Print one line per package: the percent and the counted lines.
3. Add the target of D-120 to the `Makefile`. Give it a derived data folder of its own, for example `.build/CoverageData`. Then the coverage build does not replace the Release build of `make test`.
4. Add a fixture and a case to `Scripts/self-test.sh`, as the other check scripts have (`Scripts/Fixtures`).
5. Update the context map of `AGENTS.md` (AGENT-07) and the command list of `AGENTS.md`. If D-120 asks for it, also update code-of-code.md section 5.

Done when: the target prints the coverage of Geometry, Model, InkEngine, Persistence, and Rendering. If one is below its limit, the target fails. The self-test covers the script.

Rules: TEST-02, AGENT-05, AGENT-07, BUILD-03 (no new dependency).

Status (2026-10-22): done, D-120 (a). `make coverage` passed on the iPad: Geometry 91.06 % (438 of 481 lines), Model 90.17 % (1,275 of 1,414), InkEngine 92.73 % (625 of 674), Persistence 91.23 % (2,163 of 2,371), Rendering 86.66 % (5,819 of 6,715). The instrumented run passed 301 of 303 device tests. `EraseUndoPerformanceTests` failed, as item 6 of section 2.1 expects, with a slowest erase of 49.60 ms. The snapshot of the card menu failed with 28,664 pixels of difference. Phase 4 runs the snapshots again in Release. The self-test runs the script on three fixtures.

### Phase 2: the camera of a flight on the render thread (item 2)

#### 2.1 A test that stalls the main thread

1. Add a device test to `OpenAnimationTests`, or to a new XCTest class in `PointerAppTests`. It starts the open of an empty card and blocks the main thread for 20 ms in the first 50 ms of the flight. Use one `Thread.sleep` inside a main-actor block, then yield. Do not block in other tests, because a blocked main actor broke `AppMessageTests` before.
2. The test asserts 0 late frames of the parent, and 0 held frames. A held frame repeats the camera of the frame before it during the flight: the screen holds, and then the camera jumps. The frames before the first move and the frames at the last camera do not count.
3. Do the same for the leave: block the main thread for 20 ms at the start of the parent's flight.

Done when: both tests fail on the current code (TEST-03).

Fact found on 2026-10-22: with the 20 ms block, the old code had 0 late frames in 3 of 3 opens and 3 of 3 leaves. The render thread presents frames during the block, but with the same camera, and then the camera jumps: the largest move between two frames rose from 64.3 to 172.7 points, and the largest zoom step from 1.119 to 1.320. The count of late frames alone therefore does not show the fault, so item 2 also counts the held frames.

Status (2026-10-22): done. On the code before task 2.2, with 3 iterations, the open test had 1 to 3 held frames in each open, and the leave test had 3, 0, and 1 held frames. The leave test blocks only after the first move of the parent flight, because the old controller starts a flight at its first step, and a block before it only delays the flight. With task 2.2, both tests pass in 3 of 3 iterations with 0 late and 0 held frames. The blocked open then has the same largest move, 64.2 points, and zoom step, 1.119, as an open without a block.

#### 2.2 The render thread computes the camera and the weight of a flight

1. Raise D-121 and wait for the decision.
2. Move the closed form of the flight into `Geometry` as a value type, for example `CameraFlight`. It holds the start camera, the target camera, the duration, and the start time. It gives `progress(at:)` and `camera(at:)` from a time. Move `CameraFlightTests` with it, so they run on the Mac (Tier A, 90 % coverage). `CameraController` uses the new type.
3. Add `CanvasRenderer.fly(_:)`. It posts the flight through `RenderInbox`. On each frame, the render thread takes the camera from the flight at the target time of the frame, until the end of the flight. At the end, the camera is exactly the target, as now.
4. The render thread also takes the weight of the parent from the progress of the flight: `1 - progress` for an open, `progress` for a leave (`FrameTransition`). The main-thread calls of `setParentWeight` stay as a fallback and must give the same values.
5. Pick one clock for the start time and the frame time. The render thread uses the `targetTimestamp` of `CAMetalDisplayLink`. The main thread uses the `modelTime` of `InkView.onFrame`. Both are in the time base of `CACurrentMediaTime()`. At the start of the flight, set the start time once, and give it to both sides.
6. During a flight, `waitForCameraIfMoving` must not wait for the main thread.
7. The main thread still steps its own `CameraController` for the logic: the end callbacks, `isInCardTransition`, and the input lock. A camera from the main thread must not overwrite the camera of a running flight on the render thread.
8. Do the same for the minimize animation of the pinch-out exit (`startPinchLeave`). Its progress comes from the zoom of the flight camera (`CameraController.exitProgress`), so the render thread computes it from the same flight.
9. Keep PERF-01: no allocation per frame. Add a signpost to the flight step on the render thread (PERF-03).

Done when:
- The tests of task 2.1 pass.
- `OpenAnimationTests` with 10 iterations, run twice, has 0 late frames in each event.
- The open and leave times stay within 10 % of the baseline of phase 0.
- `TransitionTests` and `PinchCancelTests` pass, and the snapshots match their references.
- architecture.md sections 6.2 and 6.3 describe the new flow.

Rules: CAN-05, CARD-03, CARD-04, CARD-05, D-98, D-109, D-121, PERF-01, PERF-03, TEST-03.

Status (2026-10-22): the code is in, D-121 (a). One target fails, and the product owner must decide (section 6.2).
- Pass: the tests of task 2.1 pass. `TransitionTests`, `PinchCancelTests`, `DeepTreeTests`, `NavigationTests`, and `PreviewWriteTests` pass, with the transition snapshots. A frame of a flight makes 15 allocations against 15 of a bare Metal frame (`TransitionAllocationTests`). architecture.md sections 5.1, 6.2, and 6.3 describe the new flow.
- Pass: the times stay within 10 % of the baseline. The open of the D-56 card has a median of 464.5 to 466.0 ms (baseline 457.5 ms), and the open of the empty card 467.5 to 469.0 ms (baseline 467.5 ms).
- Fail: `OpenAnimationTests` with 10 iterations still has late frames in the empty card, in 3 runs. The D-56 card had none in 60 events.
- Decided by the product owner on 2026-10-22: (a). Phase 2 stays as it is, and the late frame at the start of the flight of an empty card is an open item. Its cause is on the render thread, not the main thread. A trace of the render thread during an open with Instruments is the next step.

### Phase 3: the step speed (item 3)

#### 3.1 A profile of the model step

1. Add a Tier A performance test in `Packages/Model/Tests`. It applies and reverts one `EraseStrokes` on a content of 20,000 strokes. The step removes 1,000 strokes and adds 2,000 parts, as the D-69 content does (m4-plan.md section 4.6). Run it on the Mac in Release (`swift test -c release`).
2. Make sure that the content is uniquely referenced during the step. Then compare a run where a second copy of the content exists. If the step copies a dictionary, find the second reference in `CanvasViewController` or in the test, and remove it.
3. Profile the step with Instruments on the Mac: `xcrun xctrace record --template 'Time Profiler' --launch -- <test binary>`. Another way: put signposts around each part of `remove`, `restore`, the `ChangeLog`, and the `LibraryChange` rows.
4. Record the cost of each part in section 6 of this plan.

Done when: section 6 names the parts of the 4 to 5 ms with their measured cost.

Status (2026-10-22): done, section 6.3. The step itself costs about 0.5 to 0.8 ms on the iPad. Most of the 4 to 6 ms in the app comes from the state of the CPU after the main thread waited for a frame.

#### 3.2 The renderer gets the change before the model step

1. Raise D-122 and wait for the decision.
2. In `runStep`, take the change from `renderDelta(of:isUndo:)` and call `renderer.change` before the model step, for `EraseStrokes` and `AddStroke`. For the other commands, keep the order of today.
3. In `finishErase`, call `renderer.change` with `command.removed` and `command.parts` before `perform(command)`.
4. If the model step throws, call `renderer.change` with the reverse change, and log the error. Add a test with a step that throws, which makes sure that the renderer ends with the content of the model.
5. Fold `textDelta` and `cardDelta` into one pass over the rows.

Done when: in alternating runs against the commit before this task, the median and the slowest of erase, undo, and redo are lower or equal. Expected: about 4 to 5 ms less per step, often one frame.

Rules: UNDO-01, D-69, D-74, D-122, PERF-01, TEST-03.

Status (2026-10-22): done, D-122 (a). Alternating runs, base 80fc47a, new, base, new, each with 3 iterations, give 6 runs of 5 steps per build. Each measure is lower:

| Step | Median of medians, base / new | Median of the slowest, base / new | Largest, base / new |
|---|---|---|---|
| Erase | 25.41 / 20.98 ms | 27.81 / 25.44 ms | 29.53 / 28.74 ms |
| Undo | 26.31 / 17.75 ms | 28.99 / 20.24 ms | 29.85 / 20.94 ms |
| Redo | 22.18 / 20.99 ms | 29.25 / 23.45 ms | 29.87 / 25.90 ms |

The recovery after a failed step removes each added stroke that the model does not hold, and adds back each removed stroke that the model holds. A plain reverse change would put back a stroke that the model no longer holds. `CanvasHistoryTests` has a test for this. `nodeDelta(of:)` reads the rows of text boxes and cards in one pass.

#### 3.3 A faster model step

1. From the profile of task 3.1, change the costly part. Options to measure:
   - Reserve capacity in the dictionaries before a batch.
   - Avoid a copy of `Stroke` values in the `ChangeLog`. The log can hold the IDs and get the strokes back from the command.
   - Build the `LibraryChange` rows lazily, off the main thread, from the command, at the send of `RowChannel`.
2. Each change needs an alternating comparison, and the tests of TEST-09 (apply, revert, and redo give the same rows) must still pass.

Done when: the model step of the D-69 erase takes under 2 ms on the iPad, or section 6 explains why it cannot.

Rules: PERF-01, TEST-09, CONTRACT-02.

### Phase 4: close

1. Run `make check` with the iPad, and the coverage target of D-120.
2. Run the full `PointerDeviceTests` 5 times in a row (D-79). Compare each test of m6-plan.md section 6.1 with its baseline, at most 10 % slower.
3. Fill in section 6 of this plan, update m6-plan.md section 6, and the M6 status in plan.md.
4. List the manual tests for the product owner: open and leave of an empty card and of a D-56 card, and erase, undo, and redo of a large erase with the pencil.

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, D-79.

## 5. Facts to keep in mind

- `CanvasViewController` has a type body limit of 250 lines and a function body limit of 40 lines (SwiftLint). Put new code in an extension file.
- `#expect` cannot hold a call of a mutating method. Assign the result to a constant first.
- Tests must wait for their background work before they end (m6-plan.md section 4).
- A test that waits for a canvas must also wait for the end of `AppViewController.isSwapping`, and a navigation test must wait for the end of a card flight before the next leave (`isInCardTransition`).
- The assertion density script needs 2.00 checks per function in Tier A and B packages (CONTRACT-02, `make density`).

## 6. Results

### 6.1 Baseline of phase 0

Measured on 2026-10-22 on the iPad Pro 11-inch (M4) in Release, with the code of commit f14d220. `OpenAnimationTests` ran twice with `-test-iterations 10`, and `EraseUndoPerformanceTests` ran three times with `-test-iterations 3`.

| Event | Events | Events with late frames | Median | Slowest |
|---|---|---|---|---|
| Open of the D-56 card | 20 | 0 | 457.5 ms | 468 ms |
| Leave of the D-56 card | 20 | 1 (run 1) | 593.0 ms | 616 ms |
| Open of the empty card | 20 | 3, with 4 late frames (run 2) | 467.5 ms | 473 ms |
| Leave of the empty card | 18 | 3 (1 in run 1, 2 in run 2) | 489.5 ms | 499 ms |

In both runs, iteration 10 of the empty card test ended with "Test crashed with signal kill." after the open, so that iteration has no leave. Just before it, the log shows "[CAMetalLayer nextDrawable] returning nil because allocation failed." The system stopped the process for its memory after 30 canvas loads in one process. The time of an open is from the tap to the child. The time of a leave is from the tap to the end of the parent flight.

| Step | Median of the 9 medians | Medians, lowest to highest | Median of the 9 slowest | Largest | Main-thread call, median / largest |
|---|---|---|---|---|---|
| Erase | 25.43 ms | 21.14 to 27.06 ms | 28.38 ms | 32.95 ms | 12.10 / 15.00 ms |
| Undo | 25.94 ms | 21.96 to 28.41 ms | 28.95 ms | 30.34 ms | 6.00 / 8.10 ms |
| Redo | 23.53 ms | 18.30 to 29.13 ms | 27.44 ms | 31.56 ms | 5.40 / 5.80 ms |

Each step stayed under the 33 ms of D-69. The main-thread call of the erase is `finishErase` after the pencil lift. The undo has two calls per round, because each round ends with one more undo.

### 6.2 Phase 2: the flight on the render thread

Measured on 2026-10-22 on the iPad in Release, with the code of task 2.2. Each run is `OpenAnimationTests` with `-test-iterations 10`. As in the baseline, iteration 10 of the empty card test ended with a kill for memory in each run, so each run has 9 leaves of the empty card.

| Event | Baseline, 2 runs | Run 1 | Run 2 | Run 3 |
|---|---|---|---|---|
| Open of the D-56 card, events with late frames | 0 of 20 | 0 of 10 | 0 of 10 | 0 of 10 |
| Leave of the D-56 card | 1 of 20 | 0 of 10 | 0 of 10 | 0 of 10 |
| Open of the empty card | 3 of 20 | 0 of 10 | 0 of 10 | 4 of 10 |
| Leave of the empty card | 3 of 18 | 1 of 9 | 3 of 9 | 2 of 9 |

Run 3 printed the place of each late interval in the flight. Each late interval is interval 0 or 1, 12.5 to 25.0 ms long, and each event has 0 held frames. The render thread therefore did not wait for the main thread, and its own frames came late at the start of the flight. At that time, the open of an empty card makes the child screen with its renderer and adds its view, and the leave removes the child screen with its renderer. The D-56 child loads for longer, so its screen comes in the middle of the flight, and those events have no late frames. A first run of the empty card test alone had 3 late frames in its first open after the launch.

### 6.3 Phase 3: the parts of the model step

Measured on 2026-10-22. On the Mac in Release, `EraseStepPerformanceTests` gave 1.3 ms for one apply and one revert of the D-69 erase, and 2.8 ms while a second copy of the content exists. A copy of the dictionaries therefore costs about 0.75 ms per step on the Mac.

Temporary time marks in the app, on the iPad, in `EraseUndoPerformanceTests`, 2 runs of 5 rounds:

| Part | Erase (`perform`) | Undo | Redo |
|---|---|---|---|
| The whole model step | 1.73 to 3.08 ms | 4.61 to 7.00 ms | 4.89 to 5.20 ms |
| `remove` of the batch | 0.56 to 0.87 ms | 3.90 to 6.49 ms, 2,012 parts | 1.94 to 2.30 ms, 1,006 strokes |
| `restore` of the batch | 0.51 to 0.73 ms | 0.52 to 1.26 ms | 2.06 to 2.76 ms |
| `textDelta` and `cardDelta` | | 0.07 to 0.20 ms | 0.08 to 0.21 ms |
| `renderDelta`, `renderer.change`, `send`, `historyDidChange` | under 0.1 ms each | under 0.1 ms each | under 0.1 ms each |
| The cut of the eraser path before the step | 7.91 to 9.89 ms | | |

A probe on the iPad ran the same step on the same content, with no frames in between. One apply took 0.50 to 0.94 ms, and one revert 0.55 to 1.11 ms. Each of these changes made at most 0.4 ms of difference:

- a second copy of the content
- a flush of the cache of 64 MB before each step
- a removal in the order of the eraser path instead of the order of the hash table

With a sleep of 30 ms before each step, as the main thread waits for a frame in the app, the apply took up to 3.63 ms and the revert up to 4.34 ms.

The dictionary work is about 0.5 to 0.8 ms per step. The rest of the 4 to 6 ms comes from the state of the CPU after a wait: the system ramps up the core of the main thread again, or moves the thread to a faster core. The erase is fast because the cut of the path runs for 8 to 10 ms just before it. No second reference to the content exists in the canvas screen. The local `dependencies` value of the test holds one, but that costs only the first step. A faster model step therefore saves less than its share of the time. Task 3.2 lets the render thread start before the model step, so it does not wait for that state.

