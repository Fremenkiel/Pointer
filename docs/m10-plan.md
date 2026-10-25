# M10 work plan: hardening

This document breaks milestone M10 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks take the open findings of [review-2026-10-24.md](review-2026-10-24.md) and [review-2026-10-24-m9.md](review-2026-10-24-m9.md). They build on D-94, D-105, D-125, D-131, D-132, D-136, D-137, D-159, D-170, and D-172 to D-174.

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

In this plan, "review M8" is [review-2026-10-24.md](review-2026-10-24.md), and "review M9" is [review-2026-10-24-m9.md](review-2026-10-24-m9.md). An item reference such as "M9 3.2.4" names section 3.2, item 4 of review M9.

## 1. How to work

### 1.1 Device and build

1. Use only the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator, and never make one (learned rule 1 of `AGENTS.md`).
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. If it prints `passcodeRequired: true`, stop and ask the product owner to unlock the iPad.
3. Give each device run that you compare a `-resultBundlePath` under `.build/Runs`, with the prefix `T-`.
4. Compare two builds only with alternating runs of the test alone (section 1.3 of [m6-fix-plan.md](m6-fix-plan.md)). Build the base with a worktree of the base commit under `.build/Base`. A full run alone does not decide a change, because the order of the suites changes its measures (D-145).
5. Run Tier A code on the Mac in release builds (`swift test -c release` or a release benchmark). Run the rest on the iPad.
6. For a memory measure, read `os_proc_available_memory` every 0.25 ms. Start it after 1.5 s of steady memory (`OnScreenCanvas.waitForSteadyMemory()`).
7. If a task needs an Instruments trace, record a Metal System Trace of the test process with a time limit. Do not record a System Trace of all processes. Such a trace filled the disk before.

### 1.2 What a test can and cannot do

1. Package tests of `Geometry`, `Model`, `InkEngine`, and `Persistence` run on the Mac.
2. The tests of `Rendering`, `Export`, the feature packages, and the app target run in `PointerDeviceTests` on the iPad (D-77).
3. A test cannot make Apple Pencil events. UIKit gives no API for a synthetic touch of type `.pencil`, and PencilKit gives no samples before the lift (D-33). The existing tests drive the converter, the handoff, and the gesture handlers directly.
4. A test can run Metal API validation with `TEST_RUNNER_MTL_DEBUG_LAYER=1`. Under validation, a bare Metal frame makes 121 allocations, so the allocation tests must not run under it (M9 3.4.1).
5. A race with a window of a few instructions has no deterministic test without a hook in the code. Section 5 asks the product owner how to handle such fixes.

## 2. Facts from the code

Read on 2026-10-25 on branch `m10` at commit 7287e42. Paths are under `Packages/` unless they start with `PointerApp`, `Scripts/`, or `docs/`.

### 2.1 Performance tests and baselines

1. No stored baseline exists: no `.xcbaseline` file, no test plan, and no compare script. The `Makefile` has no performance target.
2. Each device performance test reports its numbers as the title of an activity (`XCTContext.runActivity(named:)`) and in its assert message. The numbers reach the Mac only inside the result bundle. Earlier milestones read them by hand with `xcrun xcresulttool`.
3. No shared helper records samples. Five tests copy the 0.25 ms memory poll.
4. These tests have no limit:
   - `RenderingPerformanceTests`: 3 `measure` blocks with `_ = try?`.
   - `FrameLoopTests`: 11 tests that check only `frames > 0`.
   - The time of `LevelOfDetailPerformanceTests`.
   - `TextLayoutPerformanceTests`, `PreviewMakerPerformanceTests`, and `PreviewsAfterRestoreTests`.
   - `DeviceStatePerformanceTests`, `SQLiteSpeedTests`, and the export of 10,000 text boxes.
   - `EditAllocationTests`, and `EraseStepPerformanceTests` on the Mac.
5. Five of the 16 budgets of architecture.md section 12 have no automated check:
   - Pencil to ink.
   - The CPU and GPU time of a pen frame. Only the eraser frame has a test.
   - Dropped frames.
   - The save signpost.
   - "Back up now" and restore of 200,000 strokes.

   The previews after a restore are recorded without a budget, as D-157 says.
6. No test measures the time or the frame count of a whole build of the committed layer. Only the signpost `ContinueBuild` exists.

### 2.2 Limits (TEST-06)

1. These limits have tests at the limit and at the limit plus one: `maxDepth`, `maxNodesPerCanvas`, `maxTextLength`, `maxWorkspaces`, `maxTitleLength`, `maxSortKeyLength`, `minCardWidth` and `minCardHeight`, `maxHistoryDepth`, `maxGridCellsPerItem`, and `UUIDVersion7.maxMillis`.
2. Gaps on the Mac:
   - `Eraser.minimumChunk` and `maxChunks` have no test. `Rendering/TextStore.swift:36` keeps its own copies of 64 and 8.
   - `minZoom` and `maxZoom` have no test at exactly 0.25 and 8 and at the next values past them. The device state needs the same for a stored zoom.
   - `maxCanvasCoordinate` and `cardTitleReach` have no test exactly at the bound.
   - The precondition of `InkPoints` at 16,385 points has no exit test.
   - A stored path of 33 levels in `DeviceStateStore` has no test.
   - Some tests use the literal value of a limit, not its name: `RecordTests:79`, `ConstraintTests:52`, and `GridBoundTests`.
3. Gaps on the iPad:
   - The pen at `maxStrokesPerCanvas` drops the stroke with a log line only (`LiveStrokeHandoff.swift:68`, `CanvasViewController.swift:225` and `:236`). No message exists (M8 3.1.4).
   - An erase past `maxStrokesAfterErase` removes whole strokes without parts, with no message and no test (`CanvasViewController+Eraser.swift:88`).
   - `maxCameraCoordinate` has no test at the bound.
4. Messages exist for the depth, the nodes, the text length, the title length, and the workspaces. architecture.md section 10 asks for a message at each limit that the user reaches.

### 2.3 Text and glyphs

1. `GlyphAtlas` keeps one 2D texture of type `.r8Unorm` per page. A page holds one scale exponent from -2 to 5. Its side depends on the exponent, from 256 to 2,048 pixels.
2. A new page takes the first free index. `drop` frees an index without a generation, so a placement that a box keeps then points to the next page at that index.
3. `GlyphAtlas.insert` copies the key list of the page at each new glyph, because `guard var page` shares the buffer (M9 3.3.6).
4. `TextEncoder.writeQuads` writes one 32-byte `GlyphInstance` per glyph on the CPU, per pass and per build. The instance holds target pixels, so it is valid for one camera and one target only. It calls `atlas.fontID(of: fonts[0])` for each box (M9 3.3.6).
5. One draw per run of quads on one page. No texture array and no argument buffer.
6. `TextLayout` gives `fontIndices` that are local to the layout. The global font number exists only in the atlas, which assigns it on the render thread. The layout runs off the render thread (D-92).
7. `PreviewMaker` keeps a whole `FrameRenderer`, and each offscreen preview makes a new `TextStore`, `CardStore`, `GlyphAtlas`, and `GlyphRing` (M9 3.3.4).
8. `GlyphAtlas`, `TextEncoder`, and `FrameRenderer` have 16 to 21 code lines left under the type limit of 250 (SIZE-03).

### 2.4 Tools

1. `Scripts/assertion-density.swift` counts functions of more than 5 lines and fails below an average of 2.0. It counts each `guard` with any `return` of a value, and the checks of a nested function in the outer function too.
2. `Scripts/coverage.swift` checks only the percentages of lines.
3. No lint rule exists for FLOW-04, SAFE-02, or SAFE-03. The code has 12 `@discardableResult` attributes and 8 direct calls of `addCompletedHandler` or `addScheduledHandler`.
4. 31 lines of code and comments in the test and source folders name the simulator (M9 3.4.5).
5. `make build` builds incrementally, so it prints no warning for a file that it does not compile again (D-132).

### 2.5 Other

1. `PreviewStore.remove(_:)` has no caller, so the 30-day purge keeps the preview files of the removed canvases.
2. `checkpointPassive` compares `code != SQLITE_BUSY`, but the connection opens with extended result codes (M8 3.2.9).
3. No UI test target exists, and no control has an `accessibilityIdentifier`. Six controls have an accessibility label: `CurrentToolButton`, `CardButton`, `HistoryButtons`, `UpButton`, `ToolPalette`, and `WorkspaceButton`.

## 3. Decisions

The product owner decided these before M10. [decisions.md](decisions.md) gives the facts and the reasons.

| ID | Decision | Tasks |
|---|---|---|
| D-94, D-105 | Glyph quads of each text box in a GPU buffer that a build reuses, in M10. | 4.1 to 4.4 |
| D-125, D-136, D-137 | Trace the late frames at the start of the card flights, fix them, and remove the expected failures. | 5.1, 5.2 |
| D-131 | M10 takes the rest of the review before M7. | 2.1, 2.2, 3.1 to 3.3 |
| D-132 | `make build` builds in a fresh folder and fails on each warning line. A Swift extension of `MTLCommandBuffer` takes `@Sendable` handlers, and a lint rule bans a direct call. | 0.2 |
| D-159 | `EraseStrokes.revert` accepts up to `maxStrokesAfterErase`. | 2.9 |
| D-170 | A grid budget per canvas is open for M10. | 6.3 |
| D-172 | Each performance test writes its samples. `make perf-baseline` and `make perf-compare` with a median of at least 10 runs, 10 %, and a Mann-Whitney test with p < 0.01. The budgets stay hard limits. | 0.3, 0.4, 8.2 |
| D-173 | One real contract check in each Tier A and B function of more than 10 lines. Remove the checks that a reader can prove. | 1.1, 1.2 |
| D-174 | `make nesting`, lint rules for SAFE-03 and SAFE-02, a per-function check of TEST-02, and a try of `unused_declaration`. No Periphery. | 1.3 to 1.6 |

Section 5 lists the questions that M10 raised, D-175 to D-187. The product owner decided them with the recommendations on 2026-10-25.

## 4. Tasks

### Phase 0: tools and baselines

The tools of D-132 and D-172 come before any performance work, because M10 acceptance 1 depends on them.

#### 0.1 Baseline

1. Run `make check` with the iPad and `make coverage`. Keep the logs as `T-baseline-check.log` and `T-baseline-coverage.log`.
2. Run the full `PointerDeviceTests` once, with the bundle `T-base-full.xcresult`.
3. Record in section 6 the measures of each test of section 2.1.

Done when: section 6 holds the baseline.

#### 0.2 The clean build (D-132)

1. `make build` builds in a fresh derived data folder and fails on each line of the form `path: warning:`, as `make analyze` does.
2. Add an extension of `MTLCommandBuffer` in `Rendering` that takes `@escaping @Sendable` handlers. Move the 8 direct calls to it.
3. Add the SwiftLint rule `build_02_metal_handler`, which bans a direct call of `addCompletedHandler` and `addScheduledHandler` outside the extension file. Add a fixture to `Scripts/Fixtures` and to `Scripts/self-test.sh`.
4. Update code-of-code.md section 4 (the tool table) and BUILD-02 only as D-132 states.

Test before the change: a probe file with a capture of a non-Sendable value in `addCompletedHandler` passes the old `make build` and fails the new one. The lint fixture fails without the rule.

Rules: BUILD-01, BUILD-02, D-132.

#### 0.3 The samples and the compare (D-172)

1. Add a shared helper in the test support of `PointerDeviceTests`, `PerformanceRecord`. Each performance test passes its named samples to it, for example `erase.slowest.ms`. The helper attaches one JSON file per test to the result bundle (`XCTAttachment`, lifetime `.keepAlways`). It keeps the activity title of today.
2. Move each test of section 2.1 to the helper. A test with a hard budget keeps its assert. The `_ = try?` of `RenderingPerformanceTests` goes, so that a throw fails the test (M9 3.4.4).
3. Add `Scripts/perf.swift`. It reads the attachments of a list of result bundles with `xcrun xcresulttool`. It writes or compares a baseline file. The compare computes the median of each sample name and a two-sided Mann-Whitney U test. A sample fails with both of these: a median more than 10 % worse, and p < 0.01. A memory peak is reported without a gate (D-172).
4. Add `make perf-baseline` and `make perf-compare`. The baseline file goes into the new folder `Performance/Baselines/`, one file per device model. Add the folder to the context map of `AGENTS.md` (AGENT-07).
5. Add fixtures to `Scripts/Fixtures` for the compare: a pass, a slower median with p < 0.01, a slower median with p ≥ 0.01, a missing sample, and a memory sample. Add them to `Scripts/self-test.sh`. Make sure that the U statistic and p of one fixture match a value from a published table or from R (`wilcox.test`).
6. Update architecture.md section 12: what a baseline is, the two targets, and the run count.

Test before the change: the fixture with the slower median fails the compare. Before the change, no compare exists, so the self-test fails on the missing script.

Rules: PERF-03, TEST-04, AGENT-07, DOC-06, D-172. The run count and the set of tests depend on D-177.

#### 0.4 Record the baseline

1. Record the baseline on the code at the end of phase 1, before phase 2. Phase 1 changes only checks and tools, and phases 2 to 7 change the code that the baseline measures.
2. Run the runs of D-177 and `make perf-baseline`. Commit the baseline file.
3. Record the spread of each sample in section 6. A sample whose runs spread more than 10 % gets a note, because the compare cannot see a change of 10 % in it.

Done when: the baseline file is in the repository, and `make perf-compare` on 10 new runs of the same code passes.

Rules: D-172, D-177.

#### 0.5 Metal API validation

1. Add `make validation`. It runs `PointerDeviceTests` with `TEST_RUNNER_MTL_DEBUG_LAYER=1` and `TEST_RUNNER_MTL_SHADER_VALIDATION=1`, and it skips the allocation tests (M9 3.4.1).
2. It is not a part of `make check`. It runs at each close and for each change of the render code (D-186).

Done when: the target passes with 0 validation errors.

Rules: PERF-01, D-186.

### Phase 1: rules and checks

The contract rule of D-173 comes before the removal of the checks that restate the line before them.

#### 1.1 The rule CONTRACT-02 and its script (D-173)

1. Change the text of CONTRACT-02 in code-of-code.md to the text of D-173. Change the table of section 0: Tier C keeps its exception.
2. Change `Scripts/assertion-density.swift`:
   - A function of more than 10 lines without a contract check fails, with its file and line.
   - A nested function counts once, as a function of its own. Its checks do not count in the outer function.
   - A `guard` with an error exit of D-176 counts. Other `guard` statements do not count.
   - The script reports the average of each package without a limit.
3. Change the fixtures `density-low`, `density-syntax`, and `density-ok`, and add `density-nested` and `density-error-exit`.

Test before the change: `density-nested` and `density-error-exit` fail with the old script. With a package average of 2.0 or more, a function of 11 lines without a check passes the old script.

Rules: CONTRACT-02, AGENT-03, D-173, D-176.

#### 1.2 Real checks in each package (D-173)

1. Read the contract checks of each Tier A and Tier B package by hand: Geometry, Model, InkEngine, Persistence, Rendering, and Export.
2. Remove each check that a reader can prove always holds, for example `assert(textures.count == 2)` after a literal of two textures. Review M9 section 3.1, item 2 lists about 75 of them.
3. Add one real check to each function of more than 10 lines that has none. A real check tests a value that comes from outside the function or from an earlier state.
4. One commit per package. Record the count of removed and added checks of each package in section 6.

Done when: `make density` passes, and each package reports its average.

Rules: CONTRACT-02, CONTRACT-03, CONTRACT-04, D-173.

#### 1.3 The nesting check of FLOW-04 (D-174)

1. Add a SwiftSyntax tool in the new folder `Scripts/Nesting/`, a Swift package with an executable target. It counts the depth of control flow in each function body and fails above 3. The constructs that count follow D-175. The tool is a development tool under D-04, and the app never links it.
2. Add `make nesting`, and add it to `make check`. Add fixtures and self-test lines.
3. Fix each finding in the code. A finding in a hot path needs a device measure of no regression over 10 %.
4. Add the folder to the context map of `AGENTS.md`, and the tool to code-of-code.md section 4.

Test before the change: a fixture with 4 levels fails the tool.

Rules: FLOW-04, AGENT-07, D-04, D-174, D-175.

#### 1.4 The lint rules of SAFE-03 and SAFE-02 (D-174)

1. Add `safe_03_discardable_result`. It fails on `@discardableResult` without a `///` comment line before it.
2. Add `safe_02_dropped_try`. It fails on `_ = try?` and on a statement that starts with `try?`.
3. Fix each finding: `StressContent.swift:47`, `TemporaryFolder.swift:18`, `NavigationTests.swift:43`, and the rest that the rule finds (M8 3.4.5, M9 3.4.4).
4. Add a lint fixture for each rule to `Scripts/Fixtures/lint-violations`.

Test before the change: the fixture lines pass the old configuration.

Rules: SAFE-02, SAFE-03, D-174.

#### 1.5 One test per Tier A function (TEST-02, D-174)

1. `Scripts/coverage.swift` reads the `functions` array of each report of `llvm-cov export` and fails on a Tier A function with an execution count of 0.
2. An allow list in `Scripts/coverage-allow.txt` names a function and the reason. Its form follows D-187.
3. Add a test for each function that the check finds, or an allow entry.
4. Add fixtures `coverage-function-missed` and `coverage-function-allowed`.

Test before the change: `coverage-function-missed` passes the old script.

Rules: TEST-02, D-174, D-187.

#### 1.6 Dead code and documentation (SCOPE-01, DOC-01)

1. Try the SwiftLint analyzer rule `unused_declaration` with the compiler log of a clean build of the app and of each package. If it gives findings that are true on the packages, add `make unused`. If it does not work on the packages, change the text of SCOPE-01 to review only, as D-174 says. Record the result in section 6.
2. Remove the code without a caller of M9 3.4.6. Make each public declaration that only tests use `internal`, and import it with `@testable` in the tests.
3. Add the missing documentation comments of M9 3.4.7 (DOC-01).
4. Move the bounds of the two `while` loops of M9 3.4.8 into the loop condition (FLOW-03).
5. Remove the `#if targetEnvironment(simulator)` branches and the comments that name the simulator (M9 3.4.5, learned rule 1).

Rules: SCOPE-01, DOC-01, FLOW-03, SAFE-08, D-174.

### Phase 2: correctness

The single lock of the `isLoading*` flags comes first, because the UI tests of phase 7 wait on those flags.

#### 2.1 One lock for the loading flags (M9 3.2.1)

1. `RenderEngine` counts the text loads, the card loads, and the preview loads in transit under the inbox lock. `take()` moves an item from the inbox into the frame, and the count drops only after the frame applies it.
2. `isLoadingText`, `isLoadingCards`, and `isLoadingPreviews` read one state under one lock. Add `isLoading` for all three.

Test before the change: a device test posts a text load and stops the frame between `take()` and the apply with a test hook of the frame. With the old code, `isLoadingText` reads `false` in that gap.

Rules: TEST-03, D-92, D-131.

#### 2.2 Completions after the locks (M9 3.2.2)

1. The completions of a card load and of a preview render run after their lock, not under it: `CanvasRenderer+Cards.swift:37`, `FrameRenderer+PreviewRender.swift:17` and `:99`, and `PreviewRenderer.swift:117` and `:120`.

Test before the change: a device test gives a completion that posts to the same engine. The old code stops at the second lock of the `Mutex`. The test then fails at its timeout.

Rules: TEST-03, D-131.

#### 2.3 The parent image without a wait on the main actor (M9 3.2.3)

1. `giveParentImage` no longer takes the frame lock of two engines on the main actor. It posts the request to the inbox of the child, and the render thread of the child takes the image.

Test before the change: a device test blocks the render thread of the parent in `DrawListRing.beginFrame` and measures the time of `giveParentImage` on the main actor. The old code waits for the block.

Rules: TEST-03, PERF-02.

#### 2.4 The camera semaphore and other races (M8 3.2.4, M9 3.2.10)

1. `RenderEngine` gets the internal hook `afterCameraLock` between the inbox lock and the signal, `nil` in the app (D-184). A device test holds `post` in the hook until the wait of the frame times out. With the old code, the next wait ends at once.
2. The fake library of the selector tests runs on a custom serial executor that releases the jobs in the order of the test. A test runs `rename` and `delete`, and two `create` calls, in the order that breaks the old code.
3. Fix both races. Add a SwiftLint rule that only `Tests/` passes a hook that is not `nil`.

Rules: TEST-03, D-184.

#### 2.5 Previews (M8 3.2.5, M8 3.2.6, M9 3.2.5 to 3.2.7, M9 3.2.13)

1. `PreviewAtlas.want` keeps the requests past 16 for the next frame, not a silent drop.
2. A frozen frame of an open marks the preview slot of the opened card as used.
3. A failed preview render gives `.dropped`, not `.unavailable`, so the card asks again.
4. A failed `CommittedLayer` init waits before the next try and logs once.
5. `PreviewFiles` takes the view size at each render, not at its creation.
6. A device test makes the frame loop come to rest at zoom 0.25 over 2,000 cards with 512 slots. If it does not come to rest, fix the eviction so that a slot of a drawn card stays.

Each item gets a test that fails before its fix.

Rules: TEST-03, D-97.

#### 2.6 Lifetimes (M9 3.2.8, M9 3.2.9)

1. `RowChannel` ends its consumer task in `deinit`. A send after `finish()` throws or returns an error value, not only an `assertionFailure`.
2. The close of a canvas cancels its export. `PDFExporter` checks for a cancel between strokes and between text boxes.

Test before the change: a device test drops a canvas without `willMove(toParent:)` and shows that the library goes. A device test closes a canvas during an export of 200,000 strokes and shows that the points go within 1 s.

Rules: TEST-03, TEST-04.

#### 2.7 Persistence (M8 3.2.8 to 3.2.11, M9 3.2.11)

1. The launch asks for a checkpoint after its cleanup.
2. `checkpointPassive` compares the primary result code (`code & 0xFF`).
3. `RowReader.double()` checks for `NULL` before it reads.
4. `PreviewStore.write` reads `errno` right after the failed call.
5. A test of the busy path of the hard-limit checkpoint, with a hook after the checkpoint lock.

Each item gets a Mac test that fails before its fix.

Rules: SAFE-10, TEST-03.

#### 2.8 Strings and the PDF (M9 3.2.12, M9 3.2.14)

1. The strings of `WorkspaceStrings.swift:19` and `:24` take the numbers from `Limits` as format arguments.
2. The order of the text boxes in the PDF follows D-185.

Rules: STYLE-03, STYLE-05, EXP-02, D-185.

#### 2.9 The undo of an erase and the preview files (D-159)

1. `EraseStrokes.revert` accepts up to `Limits.maxStrokesAfterErase` (D-159). Update its documentation comment.
2. The 30-day purge deletes the preview file of each canvas that it removes, with `PreviewStore.remove(_:)`.

Test before the change: a Mac test of two erases near the limit, whose undo fails with the old code. A test of the purge finds the preview file with the old code.

Rules: TEST-03, D-18, D-159.

### Phase 3: memory and allocations

Each change in `InkEngine`, `Rendering`, or `CanvasFeature` needs a device measure: no regression over 10 % in alternating pairs. Items 3.3.4 and 3.3.6 of review M9 come before phase 4.

#### 3.1 The inbox and the deliveries (M9 3.3.1, M9 3.3.2)

1. `RenderInbox.reset()` keeps the capacity of its edit lists. A card drag and a text-box drag post one item without an array.
2. `CanvasRenderer.deliver(upTo:)` and `deliverCompletions(upTo:time:)` loop with an index, without a copy.

Test before the change: `TextMoveAllocationTests` and a new card drag test count the allocations per sample. Today 1 to 2, the target 0.

Rules: PERF-01, D-131.

#### 3.2 The erase (M9 3.3.7 to 3.3.9)

1. Measure the release preconditions of `Eraser.command` and `EraseStrokes.init` on the Mac in a release build. If their cost shows, move them to `assert` (D-131).
2. Add a serial prefilter of the bounds before the parallel split of `Eraser`.
3. `SpatialGrid.removeEntry` finds an entry without a linear scan of the cell.

Measure: `EraseTimingTests` and the release benchmark on the Mac, and `EraseUndoPerformanceTests` on the iPad in alternating pairs.

Rules: PERF-01, CONTRACT-03, D-131.

#### 3.3 The committed layer and the renderer (M9 3.3.3, M9 3.3.5)

1. The lists of `CommittedLayer` keep their capacity from the last layer. A new layer after a rotation or a leave thus does not grow them in a frame.
2. One `InkResources` per device, shared by all renderers. Correct the arena size: `RendererConfiguration.initialArenaSlabs` states 8 MB, but each buffer holds 128 slabs, 16 MB.

Measure: the open of an empty card and of a D-56 card, and the memory of each renderer.

Rules: PERF-01, DOC-03.

#### 3.4 The offscreen preview (M9 3.3.4)

1. `PreviewMaker` keeps only the parts that a preview uses: no unused arena of 16 MB, no glyph table of 1.31 MB, and no text lists of 960 KB.
2. It keeps one `GlyphAtlas`, `GlyphRing`, and `TextEncoder` for all its previews.
3. The arena of each pass takes the size of the points of the pass, not the worst case.
4. The text filter takes only the boxes that touch the region.

Measure: `PreviewMakerPerformanceTests` and `PreviewsAfterRestoreTests` in alternating pairs. Today 0.184 s and 206 MB for a D-56 child.

Rules: PERF-01, D-157.

#### 3.5 The glyph atlas and the text encoder (M9 3.3.6)

1. `GlyphAtlas.insert` appends the key in place, without a copy of the list.
2. `TextEncoder` takes the font ID of the base font without a lookup (an identity check against `TextLayout.baseFont`).

Measure: 4,000 inserts and 5,000 boxes per pass, on the iPad. Today 807 µs and 0.43 ms.

Rules: PERF-01.

#### 3.6 Small allocations (M9 3.3.10 to 3.3.12)

1. `PointArena.allocate` begins its signpost without a string. The presented handler of a handoff makes no closure per frame.
2. `History.renderDelta` builds one delta. `nextTextSortKey` and `nextCardSortKey` take the largest key without an array.
3. `CanvasContent` reserves its capacity at the load.

Rules: PERF-01.

#### 3.7 Allocation tests through UIKit (M9 3.4.9)

1. Add allocation tests that drive `PencilTouchObserver`, `handlePan`, and `handlePinch` through UIKit events.
2. Count `RenderEngine.apply` and the commit handler in `FrameLoopProbe`. Add counts of a handoff frame, an eraser mask frame, and a redraw frame.
3. Add a test that a `CanvasRenderer` and its `FrameRenderer` go away.

Rules: PERF-01, TEST-04.

### Phase 4: glyph quads in a GPU buffer (D-94 option (b), D-105)

#### 4.1 The design

1. Write a design section in architecture.md section 5.4 before any code. It answers the blockers of review M9 section 4:
   - How a stored quad keeps its atlas position after `drop` reuses a page index: a generation counter per page, or a table per exponent.
   - How one draw per box reads pages of different sizes: a texture array per exponent, or an argument buffer.
   - How the layout gets dense font numbers off the render thread (D-92).
   - Which space the stored quads use. Today a quad holds target pixels, so it is valid for one camera only. A stored quad needs canvas units and a transform per draw.
   - The memory budget of the stored quads of D-56: about one million glyphs of 32 bytes each.
   - How an edit, a move, and a delete update the buffer, and how the buffer evicts.
2. Add a build measure first. It measures the CPU time and the frame count of a whole build of the D-56 text at zoom 0.25 and 1. It also counts the uncovered frames of the pan over the text. Today the build takes 9.3 to 10.2 ms of CPU against a budget of 2 ms (D-105).
3. Give the design and the measure to the product owner. Raise a new D-number for each choice that the design leaves open. Do not write the code of task 4.2 before the product owner approves the design.

Rules: AGENT-04, PERF-03, D-92, D-94, D-105.

#### 4.2 The code

1. Build the approved design in `Rendering`, in new files, so that no type passes SIZE-03.
2. The snapshot tests of text (`TextRenderingTests`, `TextAlignmentSnapshotTests`, `CardRenderingTests`, `PreviewRenderTests`) pass with the old references.

#### 4.3 The measures

1. The build measure of task 4.1, in alternating pairs against the base.
2. `FrameLoopTests` over the text: late frames and uncovered frames.
3. `TextPassPerformanceTests`, `TextPassAllocationTests`, and the memory of the D-56 open.

Done when: the build of D-56 text fits the budget of 2 ms per frame, or the product owner accepts the measured gain. No other measure regresses over 10 %.

Rules: PERF-01, PERF-03, D-94, D-105.

### Phase 5: traces of the card flights

#### 5.1 The late frame of the empty card (D-125)

1. Trace the render thread during the open of an empty card with a Metal System Trace with a time limit (section 1.1, item 7).
2. Find why the render thread skips the target at place 0. Benchmark each possible fix on the iPad.
3. Remove the expected failure of D-125 in `OpenAnimationTests` and `FlightStallTests`.
4. Trace the late frame at place 41 of 43, at the end of an open, the same way. It is older than M10 (section 6.15). It failed the strict check of the open of a D-56 card in 2 of the 10 runs of the baseline.

#### 5.2 The GPU wait at the start of a leave (D-137)

1. Trace frames 0 to 2 of each leave, with the thread states and the display queue.
2. Measure the options of D-137 again with the shared `InkResources` of task 3.3.
3. Remove the expected failures of D-137.

Done when: 10 iterations of `OpenAnimationTests` and `FlightStallTests` alone have 0 late frames, and 5 full runs pass without an expected failure.

Rules: PERF-03, FEEL-04, D-125, D-136, D-137.

### Phase 6: limits

#### 6.1 Tests at each limit (TEST-06)

1. Add the tests of the gaps of section 2.2, at the limit and at the limit plus one. Use the names of `Limits`, not the values.
2. Move the copies of 64 and 8 in `Rendering/TextStore.swift:36` to named constants with a source, or to the constants of `Eraser`.

Rules: TEST-06, STYLE-03.

#### 6.2 The message at the stroke limit (M8 3.1.4)

1. The pen at `maxStrokesPerCanvas` shows "This canvas holds no more ink. Erase some ink or draw in a card." from the String Catalog of the canvas, once per pencil down at the limit (D-181).
2. An erase past `maxStrokesAfterErase` shows no message (D-181). A test covers its whole-stroke erase.
3. A snapshot test of the message.

Test before the change: a device test at the limit finds no message with the old code.

Rules: STYLE-05, TEST-07, D-181.

#### 6.3 Open items of review M9 section 3.1

1. No grid budget per canvas (item 6, D-181).
2. The restore after a stop of the process (item 5, D-180): a marker file with the name of the pre-restore snapshot, written with `fsync` before the copy. At launch, a marker and a failed open run the way back, with its own extra time. A test stops the helper process at each step, as the crash test of D-54 does.
3. The sort keys (item 7, D-182): `after` and `before` add one unit at a width of at least 4 digits. A Mac test makes 1,000,000 appends, which fail at 3,874 with the old code. data-model.md section 6 changes.
4. The history budget (item 8 and M8 3.1.5, D-183): the shown canvas counts inside `CanvasSessions`, in bytes, 17 × n + 192 per stroke. Measure the bytes of the text of D-88. A test with strokes of 2 points passes the budget with the old code.

### Phase 7: UI tests and accessibility

#### 7.1 UI tests of the main flows

1. The form of the tests follows D-178. The flows of code-of-code.md section 3.11: create a workspace, draw, open a card, leave a card, undo, and export.
2. The tests wait on `isLoading` of task 2.1, never on a fixed time.
3. Add `accessibilityIdentifier` values to the controls that the tests use.
4. Add each new folder to the context map of `AGENTS.md`.

Rules: TEST-01, TEST-04, AGENT-07, D-178.

#### 7.2 Accessibility

1. A VoiceOver label for each button. The checkmark of a workspace row reads as the state of the row, not as "Checkmark".
2. The rename and the delete of a workspace row get `accessibilityAction(named:)`.
3. Dynamic Type in the chrome follows D-179. Today the selector has the fixed sizes `selectorTitleWidth` 260, `selectorListWidth` 300, and `selectorListHeight` 480.
4. Snapshot tests at the largest text size of D-179.

Rules: STYLE-03, STYLE-05, TEST-07, D-179.

### Phase 8: close

#### 8.1 The checks

1. Run `make check` with the iPad, `make coverage`, and `make validation`.
2. Run the checklist of code-of-code.md section 5. Report each failure with its output (AGENT-05).

#### 8.2 The baselines (M10 acceptance 1)

1. Run the runs of D-177 and `make perf-compare` against the baseline of task 0.4.
2. A slower sample is a regression: find the cause and fix it (learned rule 2).

#### 8.3 Five full runs

1. Run the full `PointerDeviceTests` 5 times in a row. Each run passes without an expected failure.

#### 8.4 Documents and manual tests

1. Fill in section 6 of this plan and the M10 status in [plan.md](plan.md).
2. Give the product owner the list of manual tests with the pencil. It holds at least these tests:
   - The message at the stroke limit.
   - The text at zoom 0.25 and 8 after phase 4.
   - The open and the leave of cards.
   - VoiceOver on each button.
   - The selector at the largest text size.

Done when: each step passes. M10 acceptance 1 and 2 pass.

Rules: AGENT-05, DOC-06, D-79.

## 5. Questions for the product owner

The product owner decided each question with the recommendation on 2026-10-25. [decisions.md](decisions.md) holds the full text.

| ID | Question | Decision | Task |
|---|---|---|---|
| D-175 | Which constructs count as one level of nesting (FLOW-04)? | A body adds one level: `if`, `else`, `guard`, `for`, `while`, `repeat`, `switch`, `do`, `catch`, or a closure. A `case` adds none, and an `else if` stays flat. As SonarSource, ESLint, and Checkstyle. 2 of 1,413 functions fail. | 1.3 |
| D-176 | Which `guard` exit counts as an error exit (CONTRACT-02)? | `throw`, `preconditionFailure`, `precondition`, and `assert`. Another value counts only with `// contract: error value`. Body lines without blank and comment lines, as SIZE-01. 7 functions need a check or a marker. | 1.1 |
| D-177 | What is one run of D-172? | One new process of the performance suites alone, 286 s on the iPad. 10 runs against 10. With p from 0.01 to 0.05, 10 more runs. Time samples only. Outside `make check`. The rule finds 15 to 20 % in a reliable way, not 10 %. | 0.3, 0.4, 8.2 |
| D-178 | Which form do the UI tests take? | An XCUITest target for the finger flows, with `-uiTestLibrary` for a temporary library. The draw step runs in process, because no public API makes pencil touches. Waits on an accessibility value. | 7.1 |
| D-179 | What does Dynamic Type cover? | Text scales to AX5. The icon buttons keep their size and show the Large Content Viewer, as Apple asks for bars. Custom actions for rename and delete. New requirements A11Y-01 and A11Y-02. | 7.2 |
| D-180 | How does a restore survive a stop of the process? | A marker file with the snapshot name. At launch, a marker and a failed open run the way back. Measured: the SQLite copy switches only at `SQLITE_DONE`. | 6.3 |
| D-181 | Message at the stroke limit, and a grid budget? | "This canvas holds no more ink. Erase some ink or draw in a card." No message for the erase. No grid budget, because handwriting takes 32 to 75 MB of grid. | 6.2, 6.3 |
| D-182 | Is the rebalance of sort keys built? | No. New option (c): appends add one unit at a width of 4 digits, as rocicorp and Figma do. 1,000,000 appends stay at 4 digits. | 6.3 |
| D-183 | How does the history budget count? | The shown canvas counts inside `CanvasSessions`, in bytes: 17 × n + 192 per stroke, measured. | 6.3 |
| D-184 | How does a race fix pass TEST-03? | A hook closure that stays in Release and is `nil` in the app, as `beforeCommit` is. A custom serial executor for the actor race. A lint rule keeps hooks in tests. | 2.4 |
| D-185 | In which order does the PDF write its text boxes? | Top to bottom, then left to right, then by ID. PDFKit reads by position anyway, so the gain is a stable file. | 2.8 |
| D-186 | Is `make validation` a part of `make check`? | No. It runs at each close and for each change of the render code, with API and shader validation. A run takes about 6 minutes. | 0.5 |
| D-187 | What can the allow list of TEST-02 hold? | The script skips the message autoclosures (434 of 445 entries). The list holds at most 3 functions. 4 functions get tests. | 1.5 |

[decisions.md](decisions.md) holds the sources and the measures of each question.

## 6. Results

The tasks fill in this section.

### 6.1 Baseline (task 0.1)

The baseline ran on 2026-10-25 on branch `m10` at commit 7287e42, before any change. `make -k check` passed in 7 minutes 56 seconds with the iPad: build, analyze, the tests on the Mac and the iPad, snapshots, format, lint, layers, density, self-test, and plist (`T-baseline-check.log`). The option `-k` lets each check run after a failure, and no check failed.

| Package | Tests on the Mac | Contract checks (CONTRACT-02 today) |
|---|---|---|
| Geometry | 48 | 24 functions, 50 checks, 2.08 |
| Model | 122 | 51 functions, 106 checks, 2.08 |
| InkEngine | 15 | 27 functions, 54 checks, 2.00 |
| Persistence | 148 | 111 functions, 226 checks, 2.04 |
| Rendering | on the iPad | 240 functions, 480 checks, 2.00 |
| Export | on the iPad | 7 functions, 15 checks, 2.14 |

`make test` runs `PointerDeviceTests` with `-quiet` and no result bundle, so the log holds no count of the device tests.

`make coverage` passed in 6 minutes 58 seconds (`T-baseline-coverage.log`): Geometry 90.12 %, Model 90.78 %, InkEngine 92.70 %, Persistence 90.46 %, Rendering 86.90 %, and Export 87.20 %.

The full run of `PointerDeviceTests` passed 440 of 440 tests in 367 s, with no expected failure (`T-base-full.xcresult`). `T-base-full-measures.txt` in `.build/Runs` holds all its activity titles with numbers.

| Measure | Baseline |
|---|---|
| Open of D-56 to the first frame, median and slowest of 10 | 252.1 ms, 257.8 ms |
| Memory of the open D-56 canvas | held 321 MB, peak 334 MB |
| Transition memory: open peak, leave peak | 350 MB, 431 MB |
| Erase, undo, redo of 1,000 strokes: median and slowest of 5 | 22.95 and 24.72 ms, 19.67 and 21.80 ms, 20.39 and 23.03 ms |
| `FrameRenderer.apply` allocations: erase, undo, redo | 17, 2, 7 |
| Eraser frame: CPU p50 and max, GPU p50 and max | 0.15 and 0.35 ms, 0.34 and 0.62 ms |
| Open of a D-56 card, open of an empty card | 464 ms and 466 ms to the child, 44 frames, 0 late |
| Leave of a D-56 card, leave of an empty card | 591 ms and 488 ms, 0 late |
| Frame loops: late frames | 0 of 479 in each, except the zoom over the D-56 text with 1 of 478 |
| Pan over the D-56 text: uncovered frames | 115 of 480 |
| Text pass of 300 boxes at zoom 1 | median 0.846 ms, 17.6 ns per glyph |
| Text layout of 5,000 boxes | median 56.5 ms |
| Preview of a D-56 child, first and second of a maker | 0.052 s and 53 MB, 0.052 s and 74 MB |
| Previews of 100 cards after a restore | 0.31 s, peak 93 MB |
| Export of D-56, of 200,000 handwriting strokes | 6.85 s and 218 MB, 14.64 s and 313 MB |
| "Back up now" and restore of D-56 | 0.173 s and 11 MB, 0.607 s and 5 MB |
| Save of 240 strokes, median and slowest of 50 | 2.60 ms, 3.76 ms |
| Store of 200,000 handwriting strokes | 58.2 MB, heap growth 68.0 MB |
| Allocations of a text move step | median 6 |

Two device runs measured the questions of section 5 on 2026-10-25. The performance suites alone took 286 s for 51 tests (`T-q-perf-1.xcresult`). A full run with Metal API validation took 368 s, and only the 3 allocation tests failed (`T-q-validation-1.xcresult`).

### 6.2 The clean build (task 0.2)

A probe file with a capture of a non-Sendable value in `addCompletedHandler` passed the old `make build` with exit code 0 and one warning (`T-02-probe-old.log`). The new `make build` fails on that warning line (`T-02-probe-new-direct.log`). The same capture through `whenCompleted(_:)` is a compile error (`T-02-probe-new-wrapper.log`). The clean build of the app takes 10 to 14 s on the Mac and prints no warning. The lint fixture `lint-violations` fails without the rule `build_02_metal_handler`.

The change touches `Rendering`, so four alternating pairs of `EraseUndoPerformanceTests` alone ran against the base commit 28de13b (`T-02-alt-base-1` to `-4`, `T-02-alt-new-1` to `-4`):

| Measure | Base, mean of 4 | New, mean of 4 | Change |
|---|---|---|---|
| Erase, median | 23.29 ms | 22.91 ms | -1.7 % |
| Erase, slowest | 26.97 ms | 25.35 ms | -6.0 % |
| Undo, slowest | 21.31 ms | 20.65 ms | -3.1 % |
| Redo, median | 19.89 ms | 20.84 ms | +4.8 % |
| Redo, slowest | 23.83 ms | 24.02 ms | +0.8 % |

The allocation tests of a frame, an open frame, and a flight frame stayed at 15, equal to the bare frame (`T-02-render.xcresult`).

### 6.3 The samples and the compare (task 0.3)

Each performance test of section 2.1 now attaches its samples through `PerformanceRecord`. `RenderingPerformanceTests` times its passes with `ContinuousClock`, so a throw fails the test (M9 3.4.4). One run of the 24 performance suites alone gave 180 samples in 317 s: 127 times that the compare gates and 53 memory sizes and counts that it records (`.build/Perf/probe-1.xcresult`). A compare of that run with itself passed with exit code 0.

`Scripts/perf.swift` gives the exact two-sided p of the Mann-Whitney test at the critical values of the published table for 10 runs against 10: U = 16 gives p 0.0089 and U = 17 gives 0.011, U = 23 gives 0.043 and U = 24 gives 0.052. The self-test runs six cases: the same code, a slower time, U = 16, U = 23 (exit code 3), a missing time, and a recorded memory peak.

### 6.4 Metal validation (task 0.5)

`make validation` passed in 73 s on 2026-10-25 (`T-05-validation.log`). It runs `PointerDeviceTests` with API validation and shader validation, without the 11 allocation suites and the 24 performance suites. A run of `FrameAllocationTests` alone with the same settings shows that validation is on: the bare frame makes 237 allocations, against 15 without validation and 121 with API validation alone (`T-05-proof.xcresult`).

### 6.5 The rule CONTRACT-02 (task 1.1)

`Scripts/assertion-density.swift` follows D-173 and D-176. It counts 297 functions of more than 10 code lines in Tier A and B, the same number as the research of D-176. It found 7 functions without a check, and each got one:

| Function | Check |
|---|---|
| `StrokeSplitter.cutPoint(of:at:)` | precondition: the cut parameter is inside the curve |
| `SnapshotFiles.counter(of:prefix:)` | precondition: the prefix is not empty |
| `DeviceStateStore.camera(for:)` | the `nil` of a bad row is marked as the error value of the contract |
| `LibraryStatements.init(_:)` | precondition: the connection opened a library file. `SQLiteConnection` keeps its mode for it. |
| `PreviewImage.pngData()` | the `nil` of a failed image is marked as the error value of the contract |
| `FrameRenderer.continuePreviewRender(_:)` | assert: the cursor of the job is inside its list |
| `RenderInbox.reset()` | assert: a sleeping frame loop takes no changes |

The old script failed or passed the new fixtures for the wrong reason. It counted the check of a nested function for the outer function (`density-nested`: "1 functions, 1 checks"), and it counted a plain `return nil` (`density-error-exit`: "4 functions, 2 checks"). The new script finds a function of 11 code lines and passes one of 10 (`density-error-exit`). The lines of a multi-line string count as code (`density-low`).

| Package | Functions over 10 lines | Checks | Average |
|---|---|---|---|
| Geometry | 13 | 27 | 2.08 |
| Model | 23 | 55 | 2.39 |
| InkEngine | 17 | 37 | 2.18 |
| Persistence | 79 | 160 | 2.03 |
| Rendering | 160 | 317 | 1.98 |
| Export | 5 | 10 | 2.00 |

### 6.6 The nesting check (task 1.3)

`make nesting` builds the SwiftSyntax tool in `Scripts/Nesting` and checks 285 files in 0.05 s. The first build takes about 2 minutes. It found the 2 functions of the research of D-175: the initializer of `RowChannel` at 5 levels and the body of `WorkspaceList` at 4 levels. The consumer of `RowChannel` now hands each item to a function of its own, and the rows of `WorkspaceList` are a view property of their own. The fixture `nesting-deep` fails at 4 levels, and `nesting-ok` passes at 3 levels with an `else if` chain, a `case`, a `catch`, and a nested function. The 38 device tests of the selector, the navigation, the restore, and the history passed after the split (`T-13-subset.xcresult`). `make layers` reports no finding: the SwiftSyntax package is outside the app and its packages.

### 6.7 Real checks in each package (task 1.2)

Three readers listed the checks that a reader can prove from the lines around them, one per package group. Each removal was read again before it went. The checks of compile-time constants moved into `LayoutConstantTests`, so a change of a layout still fails a test.

| Package | Removed | Added | Kept from the list | Average after (report only) |
|---|---|---|---|---|
| Geometry | 8 | 0 | 0 | 1.85 |
| Model | 19 | 1 | 0 | 2.13 |
| InkEngine | 14 | 1 | 3: a NaN of extreme coordinates can fail them | 1.71 |
| Persistence | 22 | 4 | 0 | 1.86 |
| Export | 3 | 0 | 0 | 1.60 |
| Rendering | 47 | 5 | 1: its proof is 100 lines away | 1.87 |

The reading found a fault: the assert that counts the rows of a save ran in a `defer`, so a save that failed in the middle trapped in a Debug build. `RepositorySavingTests.failureInsideWrite` stopped at "Wrote 1 of 2 rows" before the fix (commit 4fe3b9b). `make check` passed with the iPad in 8 minutes 25 seconds with all changes (`T-12-check.log`).

### 6.8 The lint rules of SAFE-02 and SAFE-03 (task 1.4)

`safe_02_dropped_try` and `safe_03_discardable_result` fire on the new lines of the fixture `lint-violations`. The code had two dropped `try?` statements, both in the cleanup of test folders (`TemporaryFolder`, `NavigationTests`). They now record the error. All 12 `@discardableResult` attributes already had a documentation comment.

### 6.9 One test per Tier A function (task 1.5)

`Scripts/coverage.swift` reads the functions of each Tier A report and fails on a function that no test runs. It skips the message closures of `precondition` and `assert` by their mangled suffix, 434 of the 445 entries of the research. On the reports of the baseline it found the 7 real functions of D-187. Four got tests: `EditText.forEachHeldStroke`, the redo loop of `History.unheldStrokeIDs`, the save of the pending rows in `validPath`, and the initializer of the app of `SQLiteLibraryRepository`. `Scripts/coverage-allow.txt` holds the other 3: two rollbacks after a failed `COMMIT`, and the initial value of a private property. The old script passed the fixture `coverage-function-missed`, and the new one fails on it.

| Package | Line coverage at the baseline | After phase 1 |
|---|---|---|
| Geometry | 90.12 % | 90.97 % |
| Model | 90.78 % | 91.94 % |
| InkEngine | 92.70 % | 93.91 % |
| Persistence | 90.46 % | 90.96 % |

### 6.10 Dead code (task 1.6, part 1)

The SwiftLint analyzer rule `unused_declaration` works on the compiler log of the clean build of the app and its packages. It read 284 files in 40 s and found 27 declarations. `make unused` now runs it in `make check`, so SCOPE-01 keeps its tool (D-174). The analyzer does not see the tests and the shaders:

- Removed, because nothing reads them: `navigate(to:camera:)` of the app, `ToolState.isTextEnabled`, `Transform.inverted()`, `NavigationPath.parentCanvas`, and the empty `BackupFeature` namespace.
- Kept with a local exception and its reason: 20 probes that only tests read, for example `LiveStrokeHandoff.liveStrokeCount` and `SQLiteLibraryRepository.settle()`, the class `SceneDelegate` that Info.plist names, and the fields of the structs that the shaders read.
- Made internal: 12 public declarations of Geometry, Model, and InkEngine that no other package reads, among them `StrokeHitTest` and `StrokeSplitter`. `BezierSegment`, `CanvasNode`, `CameraFlight.standardDuration`, and `GridCell.maxCoordinate` stay public, because public signatures or inlinable code use them.

### 6.11 Documentation, loop bounds, and the simulator (task 1.6, part 2)

- DOC-01: 205 declarations got a documentation comment, and 10 that only their own file uses became `private` (M9 3.4.7).
- FLOW-03: the loops of `SnapshotImport` and `CardOpening.waitForFirstFrame` keep their bound in the condition (M9 3.4.8).
- Learned rule 1: the `#if targetEnvironment(simulator)` branches of 11 test files and of `FrameRenderer` are gone, and the test comments name the iPad (M9 3.4.5).

`make check` passed with the iPad in 9 minutes 4 seconds at the end of phase 1 (`T-16-check.log`).

### 6.12 The test bundle in the clean build

The clean build of the base of the phase 1 compare printed a warning from `PerformanceRecord`: a call of the main-actor method `XCTContext.runActivity` from a nonisolated function. The incremental device builds never printed it again, and `make build` built only the app. `make build` now also builds the test bundle in its fresh folder (56 s for both). It failed on the warning before `PerformanceRecord` became `@MainActor`, and passes after.

### 6.13 Phase 1 against its base

Four alternating pairs of the base c7026d6 and commit 703c3c3 ran the suites of the hot paths alone: `EraseUndoPerformanceTests`, `EraserFramePerformanceTests`, `TextPassPerformanceTests`, `CanvasOpenPerformanceTests`, and `FrameLoopTests` (`T-P1-alt-*`). No time is more than 10 % slower with p < 0.1. The largest changes are main-thread p99 values of a few microseconds and the one preview frame of `testPreviewRenderOfD56`, each with p ≥ 0.11.

| Measure | Base, median of 4 | Phase 1, median of 4 |
|---|---|---|
| Erase, median and slowest | 21.52 ms, 26.36 ms | 22.31 ms, 27.27 ms |
| Undo, median and slowest | 18.05 ms, 20.78 ms | 17.57 ms, 20.13 ms |
| Redo, median and slowest | 20.22 ms, 23.89 ms | 18.56 ms, 25.19 ms |
| Open of D-56, median | 255.7 ms | 253.0 ms |
| Eraser frame, CPU p50 | 0.137 ms | 0.136 ms |
| Text pass of D-56 | 0.926 ms | 0.921 ms |

### 6.14 The baseline (task 0.4)

`make perf-baseline` recorded `Performance/Baselines/iPad16,4.json` in 47 minutes 41 seconds: 10 runs of the 24 performance suites alone at commit 015b6b6, iPadOS 26.5, Xcode 27.1. It holds 180 samples, 127 of them gated times.

The spread between the 10 runs, as the coefficient of variation (CV):

| CV | Gated times | Examples |
|---|---|---|
| over 10 % | 22 | the slowest save of `LibrarySavePerformanceTests` and `SnapshotPerformanceTests` (34 to 106 %), main-thread p99 values of a few microseconds in `FrameLoopTests` (11 to 38 %), the slowest undo (12 %) |
| 5 to 10 % | 17 | the slowest redo (8.4 %), the median erase (8.2 %) |
| under 5 % | 88 | the open of D-56, the text pass, the exports |

The compare cannot see a change of 10 % in a time with a CV over 10 % (D-177). The hard budgets of architecture.md section 12 still guard those measures.

Runs 5 and 9 of the baseline each failed one test: the open of a D-56 card had 1 late frame at place 41 of 43, near the end of the flight (`.build/Perf/baseline-5.xcresult`, `baseline-9.xcresult`). It is not the late frame at place 0 of D-125 and D-137. Section 6.15 holds the search for its cause.

### 6.15 The late frame at the end of an open

Eight alternating pairs of `OpenAnimationTests` alone ran on the commit before M10 (7287e42) and on commit 4456612 (`T-OA-alt-*`):

| Flight | Before M10, late frames in 8 runs | M10, late frames in 8 runs |
|---|---|---|
| Open of the empty card, place 0 (D-125) | 3 runs | 2 runs |
| Open of the empty card, place 41 | 2 runs | 1 run |
| Open of a D-56 card | 0 | 0 |
| Leave of a D-56 card | 1 run, 2 late frames | 0 |
| Leave of the empty card | 0 | 0 |

The late frame at place 41 is older than M10. It is a second fault of the flights, at the frame before the swap to the child. Task 5.1 traces it with the late frame at place 0.

### 6.16 One lock for the loading flags (task 2.1)

The inbox now marks the loaded text, the loaded cards, and the decoded previews from the take until the end of their frame. It also counts the preview requests that the loader holds, mirrors the uploads that wait in the frame work, and notes the requests that the last frame left for the loader. `isLoadingText`, `isLoadingCards`, `isLoadingPreviews`, and the new `isLoading` read this one state under the inbox lock. The main actor no longer takes the frame lock for `isLoadingPreviews`.

`LoadingStateTests` reads the flags in a hook between the take and the apply (D-184). With the old definitions of the flags, all 3 tests failed: each flag read `false` after the take (`T-21-old.xcresult`). With the change, 47 of 47 tests of the loading, preview, card, text, transition, and frame-loop suites pass (`T-21-new2.xcresult`). A first run found a fault of the change itself: without a preview source, the wanted previews of a frame never go to a loader, so `isLoading` stayed `true`. The flag now counts them only with a source.

### 6.17 Completions after the locks (task 2.2)

A preview request that ends without an image now calls its completion on a queue of its own (`PreviewRenderRequest.endWithoutImage()`), so the completion never runs under the inbox lock or the frame lock. The five places of review M9 3.2.2 use it. `PreviewCompletionLockTests` gives a completion that posts to its own renderer, and one that takes the frame work. Both crashed the app on the old code (`T-22-old.xcresult`). With the change, 16 tests of the preview, transition, and open suites pass, one of them the expected failure of D-125 (`T-22-new.xcresult`).

### 6.18 The parent image without a wait on the main actor (task 2.3)

`giveParentImage` tries both frame locks with `Mutex.withLockIfAvailable` (SE-0433). If a frame holds one of them, a task tries again every 2 ms, up to 500 times. The two render threads never hold both locks, so the nested tries cannot deadlock. `ParentImageHandoffTests` holds the frame lock of the parent for 200 ms on another thread. With the old code, the call on the main actor took 0.203 s (`T-23-old.xcresult`). With the change, it returns in under 20 ms, and the child gets the image after the lock (`T-23-new.xcresult`, 17 of 17 tests of the flight suites).

### 6.19 Races with a test hook (task 2.4)

- The camera wait of `RenderEngine`: the post now signals inside the inbox lock. `CameraSignalTests` holds the post in the hook `afterCameraLock` until the waiting frame times out. With the old signal after the lock, the next wait ended after about 1 µs instead of 3 ms in 3 of 3 runs (`T-24-oldcam-*`). With the change, 5 of 5 runs pass (`T-24-cam-*`).
- The selector: `rename` looks up its row after the await, and `create` takes a key after the largest key that it gave out and puts the row at the place of its key. `WorkspaceSelectorRaceTests` runs the jobs of a fake library on a gated executor (SE-0392). With the old model, a rename after a delete wrote over the wrong row (["Beta", "Renamed"]), and two creates got one key (`T-24-old.xcresult`).
- The lint rule `test_04_hooks_in_tests` fails on a hook that the product code sets.

Two faults of my own tests came up on the way. A last read of the fake library waited for a job that the gated executor kept, and a spin as a `for ... where` loop ran all its steps, because such a loop only skips its body. Xcode stopped the first after a test time allowance of 60 s, and its spindump showed the waiting task.

### 6.20 Previews, part 1 (task 2.5, items 1, 3, and 4)

- Item 1: a wanted preview past the limit of 16 waiting requests now waits in a bounded list of the atlas, and each result moves the next one on. Before, only a later build or redraw asked again.
- Item 3: a source without data gives `.dropped`, so the card asks again at the next build. Only data that does not decode gives `.unavailable`.
- Item 4: a failed committed layer waits 120 calls before the next try and logs once per failure. The hook `beforeLayer` of the frame work lets a test refuse the textures, because only memory pressure makes Metal refuse them (D-184).

`PreviewRequestTests` failed on the old behavior: 18 of 24 previews loaded, a missing preview was read once, and a failed layer was tried 30 times in 30 calls (`T-25-old.xcresult`). With the change, 36 of 36 tests of the preview, card, transition, loading, and frame-loop suites pass (`T-25-new.xcresult`).

### 6.21 A screen with more cards than slots (task 2.5, item 6)

`PreviewCrowdTests` draws 2,000 cards of 64 by 48 points at zoom 0.25 on a drawable of the 11-inch screen. The frame loop came to rest after 127 frames with 2,000 reads of the source, one per card (`T-25-crowd2.xcresult`). The atlas holds a slot of 128 pixels for each of these cards, so no slot of a drawn card is evicted, and the measured case has no fault. The test stays as a guard.

### 6.22 The preview of the opened card during a flight (task 2.5, item 2)

Each frame of a flight now marks the preview slot of the opened card as used, so a full atlas keeps that slot while the flight draws it. `PreviewRequestTests.openMarksSlot` read a last use at frame 3 while the flight drew frame 4 on the old code (`T-25b-old.xcresult`). With the change, it and the transition and open suites pass, 11 of 11 (`T-25b-new.xcresult`).

### 6.23 The screen size of a new preview (task 2.5, item 5)

`PreviewFiles` now reads the size of the canvas screen at each render, through a closure of the main actor, instead of the size at its creation. `PreviewFilesTests` renders the same ink for two canvases, before and after a change of the size from landscape to portrait. With the old fixed size, both previews were the same 937 bytes (`T-25c-old.xcresult`). With the change, the second preview follows the new size, and the app suites of the navigation pass (`T-25c-new.xcresult`). The files of earlier previews keep their region until the next event that writes a preview (D-111).

### 6.24 Lifetimes (task 2.6)

- `RowChannel` finishes its stream in `deinit`, so a channel that goes without `finish()` frees its consumer and the library. `RowChannelTests` found the library alive with the old code (`T-26-old.xcresult`). A send after the end now also writes a log entry.
- The close of a canvas cancels its export, the canvas forwards the cancel to the detached task of the PDF, and `PDFExporter` throws `ExportError.cancelled` at the next check. `ExportCancelTests` cancels an export of 200,000 handwriting strokes after 200 ms. The old export ended 14.23 s after the cancel with a whole PDF (`T-26b-old.xcresult`). The new one ends within 1 s with `.cancelled` (`T-26b-new.xcresult`).

### 6.25 Persistence (task 2.7)

| Item | Change | Test, result with the old code |
|---|---|---|
| M8 3.2.8 | The launch asks for a checkpoint after its cleanup | `RepositoryLaunchTests.checkpointAfterCleanup`: a cleanup of 12,000 old strokes left 1,657 WAL pages and no checkpoint |
| M8 3.2.9 | `checkpointPassive` compares the primary result code | `SQLiteConnectionTests.passiveCheckpointBusy`: a passive checkpoint while a `FULL` checkpoint holds the lock reports busy. It passes on the old code too, because SQLite 3.50 gives the plain `SQLITE_BUSY` here. |
| M8 3.2.10 | `RowReader.double()` checks for `NULL` first | `RowReaderTests`: passes on the old code too. SQLite 3.50 keeps the NULL type after the read, but the documentation leaves the type undefined after a conversion. |
| M8 3.2.11 | `PreviewStore.write` keeps `errno` of the rename | `PreviewStoreTests.renameErrno`: the old code reported "errno 0" instead of `EISDIR` |
| M9 3.2.11 | The busy path of the hard-limit checkpoint | `passiveCheckpointBusy` above. A writer cannot keep running while a blocking checkpoint holds the lock, so the test covers the start of the busy path at the connection. |

The 160 tests of Persistence pass on the Mac.

### 6.26 Strings and the PDF (task 2.8)

- The messages at the workspace limit and of an invalid name take their numbers from `Limits` as format arguments, with the same visible text. The selector snapshots pass unchanged, and a test makes sure that the messages show the numbers of `Limits` (`T-28-new2.xcresult`).
- The PDF writes its text boxes in the order of the page (D-185). `PDFTextTests.pageOrder` covers the order, and the PDF suites pass (`T-28b.xcresult`).

### 6.27 The undo of an erase and the preview files (task 2.9)

- `EraseStrokes.revert` accepts up to `Limits.maxStrokesAfterErase` (D-159). The undo of a cutting erase and a whole-stroke erase at 200,000 strokes failed at each try with the old code, and it passes now.
- The 30-day purge reports the canvases that it removes in `LibraryLaunch.removedCanvases`, and the launch removes their preview files. `RepositoryLaunchTests.removedCanvases` covers the report on the Mac. `PurgedPreviewTests.removesPurged` found both preview files of a purged workspace on the old code (`T-29-old.xcresult`) and passes on the new code (`T-29-new.xcresult`). The previews of a tombstone of one day stay.

### 6.28 The erase (task 3.2)

The measures ran in release builds on the Mac, with the median of 11 to 31 repeats, three runs each.

| Change | Case | Before | After |
|---|---|---|---|
| The duplicate checks of `Eraser.command` and `EraseStrokes.init` move to `assert` | `Eraser.command` of 1,000 strokes cut in two | 1.18 to 1.29 ms | 1.02 to 1.07 ms |
| A serial filter of the bounds before the split | 1,000 hits and 19,000 misses | 7.3 to 10.4 ms | 0.99 to 1.06 ms |
| A serial filter of the bounds before the split | 1,000 hits, no misses | 0.99 to 1.00 ms | 1.01 to 1.02 ms |
| A position table in a cell of more than 1,024 entries | Remove the 1,000 oldest of 20,000 in one cell | 5.80 ms | 0.13 ms |
| The same | Remove 1,000 of 20,000 strokes of handwriting | 0.135 ms | 0.125 ms |
| The same | Insert 200,000 strokes of handwriting, about 330 per cell | 8.9 ms, 35.5 MB | 8.7 ms, 35.5 MB |
| The same | Insert 200,000 strokes into one cell | 11.6 ms, 42.1 MB | 18.2 ms, 50.5 MB |

- The sets of the two checks cost 0.04 ms and 0.13 ms of an erase of 1.73 ms (command and apply). A stroke twice in a release build fails the apply with `strokeNotLive` or `strokeAlreadyLive`, and the apply rolls the content back.
- A threshold of 64 built tables in the cells of handwriting and made the load of 200,000 strokes take 14 ms. A threshold of 1,024 leaves those cells as they were. The cells of D-56 hold about 170 strokes, so its open builds no table. Only a cell of more than 1,024 entries pays for its table at the load.
- `ErasePrefilterTests` makes sure that misses among the candidates change nothing in the command. `CrowdedCellTests` covers the threshold and the threshold plus one, and random removals with inserts after them.

### 6.29 Small allocations (task 3.6)

- The load of a canvas counts its strokes, cards, and text boxes with one query and reserves room for them in `CanvasContent`. The count includes erased and deleted rows, so it is an upper bound, and the limits of a canvas cap it. In a release build on the Mac, the count of 20,000 strokes took 0.24 ms, and the reserve cut the growth of the stroke table from 1.8 ms to 0.8 ms. The whole load went from 36.0 to 39.6 ms to 32.6 to 35.0 ms in three runs each.

### 6.30 Phase 2 against its base, and the deferred previews

Four alternating pairs of the base 0673d1e and commit f6c7e5e ran `EraseUndoPerformanceTests`, `EraserFramePerformanceTests`, `TextPassPerformanceTests`, `CanvasOpenPerformanceTests`, `FrameLoopTests`, `RenderingPerformanceTests`, `PreviewMakerPerformanceTests`, `ExportPerformanceTests`, and `OpenAnimationTests` (`T-P2-alt-*`). 79 measures passed. Three were unsure, with all four new runs above all four base runs (p = 0.029):

| Measure | Base | Phase 2 |
|---|---|---|
| Card pan, render p50 | 0.419 ms | 0.501 ms (+19.4 %) |
| Card zoom, render p50 | 0.339 ms | 0.436 ms (+28.4 %) |
| Handwriting pan, main p99 | 0.013 ms | 0.025 ms |

The cause of the render time was task 2.5 (a754c20). `PreviewAtlas.moveDeferred` looped with `for request in deferred where requested.count < requestLimit`. Such a loop does not stop when its condition turns false: it skips the rest, so it walked the whole list of deferred requests at each stored preview. `removeFirst` then shifted the rest of the list. With the 5,000 cards of D-56, the cost grew with the square of the waiting cards. The loop now stops at the limit, and a head index takes a request without a shift. Four pairs of `FrameLoopTests` against f6c7e5e (`T-P2fix-alt-*`):

| Measure | f6c7e5e | Fix |
|---|---|---|
| Card pan, render p50 | 0.490 ms | 0.394 ms (-19.5 %, p = 0.029) |
| Card zoom, render p50 | 0.441 ms | 0.350 ms (-20.7 %, p = 0.029) |

Both are back at the level of the base. The main-thread p99 values move by a few microseconds in both directions between runs, and two of them were unsure again. The fix runs on the render thread only. The compare of 10 runs in phase 8 decides them (D-177).

### 6.31 Phase 3 against its base (tasks 3.1 and 3.3 to 3.6)

Four alternating pairs of the base 619beb3 and the changes of tasks 3.1 and 3.3 to 3.6 ran the hot-path suites, the memory suites, and the new measures (`T-P3-alt-*`). 77 measures passed, and none failed.

| Measure | Base | Phase 3 |
|---|---|---|
| Allocations of a drag step of a text box and of a card (3.1) | 2 and 2 | 0 and 0 |
| Metal memory that the preview maker keeps (3.4) | 16.78 MB | 0.98 MB |
| Preview of a D-56 child, first and second | 0.054 s, 0.050 s | 0.053 s, 0.050 s |
| 100 previews after a restore | 0.297 s | 0.281 s |
| 4,000 glyph inserts with their rasters (3.5) | 40.14 ms | 38.76 ms (p = 0.029) |
| Text pass of D-56 (3.5) | 0.844 ms | 0.812 ms (p = 0.029) |
| Open of D-56, median | 248.6 ms | 252.7 ms (p = 0.11) |
| Memory of a D-56 canvas | 353.5 MB | 349.3 MB |

- Task 3.3 keeps one command queue per renderer and shares only the compiled pipelines. One shared queue would also have put the offscreen previews and both renderers of a card flight into one GPU order, which changes the scheduling of D-137.
- The card zoom of `FrameLoopTests` was unsure in these pairs: render p50 from 0.356 to 0.407 ms (+14.2 %, p = 0.029). The cause was a change of task 3.4 in that build: `TextEncoder.ring` had become a variable, so that the offscreen preview could put a larger ring in place. A stored variable of a class costs a dynamic exclusivity check at each access in a release build, and the text pass reads the ring for each card. The ring is a constant again, and the offscreen preview makes a new encoder when it needs a larger ring. Four new pairs of `FrameLoopTests` against 619beb3 (`T-P3b-alt-*`): card zoom render p50 0.354 to 0.341 ms (-3.4 %), card pan 0.397 to 0.375 ms (-5.3 %), card pan at zoom 1 0.118 to 0.111 ms (-6.1 %), each with p = 0.029.
- The text pan of `FrameLoopTests` has two modes in base runs and new runs alike: a run with 5 builds has a render p50 of about 0.23 ms, and a run with 10 builds about 2.23 ms. The median of 4 pairs then depends on how many runs of each side fall into each mode (base 1.227 ms, new 2.233 ms, p = 0.11, in `T-P3b-alt-*`). The compare of 10 runs in phase 8 decides it (D-177).
- The text filter of the offscreen preview had a gap older than M10: it compared the bare origin of a box, but the glyphs reach half a line past the line box, as the bounds of the store do. A region that ended in that margin dropped a box whose glyphs reached into it. `PreviewTextFilterTests` failed 43 times on 619beb3 (`T-32-old`) and passes now. The filter now also drops a box that ends above the region, with one line height per UTF-16 unit as the bound.

### 6.32 Allocation tests through UIKit and the counts of the frame kinds (task 3.7)

- `GestureAllocationTests` drives `handlePan`, `handlePinch`, and `PencilTouchObserver.touchesMoved` through objects of UIKit. iOS has no public way to make a touch at a place, so the pan and the pinch are test subclasses that report their state, their touches, and their place. `AllocationTracer` counts each allocation by its caller (D-43). On 619beb3, with all allocations of the main thread counted, a pan step made 1 allocation and a pinch step 140 (`T-P3-alt-base-*`). The pan step and the pinch step built a list of the two recognizers in `cameraMayRest`. The pinch count also held a test artifact: the test recognizer was not the one of the canvas, so the camera came to rest at each step and made a new pen tool of PencilKit. `cameraMayRest` now checks the recognizers one by one and takes the recognizer of the calling handler as active. Each of the three steps now makes 0 Pointer allocations (`T-33`).
- `FrameKindAllocationTests` counts the Pointer allocations of a handoff frame, an eraser frame, and a redraw frame against a pan frame. The tracer counted the GPU driver (`AGXMetal…`) and `FramePacing` as Pointer code, so both now count as Metal work (D-43). A pan frame makes 1 Pointer allocation, the block of its completed handler. An eraser frame makes the same. A handoff frame and a redraw frame made 3 more: the closure of the presented handler with its block, and one in `InkEncoder.appendEntries` for the new stroke. The presented handler now captures nothing and finds its handoff in a table of the process by the identity of the drawable, so it makes only the block (task 3.6). The bound is the pan frame plus 2.
- `RenderEngine.draw` now counts the apply of the inbox and the frame in one measure, and the frame renderer holds the observer as a reference, not a closure, so a frame with an observer makes no closure.
- `RendererLifetimeTests` makes sure that a renderer and its frame work go away after frames with a handoff, text, cards, and previews.

### 6.33 The design of the glyph quads (task 4.1)

- The design is in architecture.md section 5.4.1. It answers the six blockers of review M9 section 4. D-188 to D-190 hold its open choices. Task 4.2 waits for the approval of the product owner.
- `TextBuildPerformanceTests` measures a whole build of the D-56 text (`T-33`): at zoom 0.25, 46.05 and 71.27 ms of CPU in 24 and 32 frames, each frame at most 2.39 ms; at zoom 1, 7.93 and 7.77 ms in 4 frames. Each frame keeps the build budget of 2 ms, so the build of the zoom 0.25 text takes up to a quarter of a second.

### 6.34 The late frame at the end of an open (task 5.1, item 4)

- The report of `OpenAnimationTests` now gives, for each late interval, the frames from two before to two after it: target, present time, render time, and GPU span. It also gives the time when the child canvas comes, the time when the swap starts, and the screen moves of the first and the last frames.
- Run alone with 10 iterations, the opens of an empty card had late intervals in 5 of 20 opens, and the strict open of a D-56 card in 1 to 4 of 10, all at places 37 to 41 (`T-F0` to `T-F10`). It is the late frame of section 6.14.
- What it was not: the GPU work of each late frame ended 1 to 2 ms after its target. The child canvas comes before the first frame of the flight and presents its first frame at 16.7 or 25 ms. A start of the swap 30 ms later, a camera wait that ends at a flight, and a pen tool that stays during an open each left the count as it was (`T-F6` to `T-F8`). The test with a blocked main thread had the same late places, so the main thread at the end of the flight is not the cause either. The Metal System Trace (`.build/Traces/M10-open.trace`, 169 MB) had gaps in its present events and could not place single frames.
- What it was: the last frames of an open move the screen by 0.00 to 0.76 points. After the render thread showed the last camera of its flight, the main thread sent that camera and the parent weight again at the end of its own flight. The frame for them showed nothing new, but it came after an idle refresh, and its present made a late interval.
- The fix: a frame whose only inputs are the camera, the parent weight, or the end of a flight draws nothing when the shown camera and weight stay the same. `FlightEndTests` sends the last camera of a flight again: the old code drew a frame (`T-36-old`), and the new code draws none. With the fix, 30 opens alone had 0 late intervals (`T-F11`), and the full run passed (`T-36`).

### 6.35 The sort keys (task 6.3, item 3)

- `FractionalIndex.between` at an end of the list now adds or takes one unit at the fourth digit, or at the last digit of a longer key (D-182). `SortKeyAppendTests` makes 1,000,000 appends and 100,000 prepends: the old code failed both with `sortKeyNeedsRebalance` (the appends after 3,874 keys), and the new keys are at most 4 digits long. data-model.md section 6 says so. The end-key cases of `FractionalIndexTests` now hold the keys of the new rule.

### 6.37 Tests at each limit (task 6.1)

- `ParallelChunks` in Model holds the numbers of the chunks of the erase split and of the layouts of a load, which `Eraser` and `TextStore` kept as two copies of 64 and 8. `ParallelChunksTests` covers each bound and one past it.
- New tests at the bound and one step past it: the stored zoom at exactly 0.25 and 8 and the next `Double` past each (`DeviceStateLimitTests`), a stored path of `Limits.maxDepth` cards and of one more, a stroke and a card title reach exactly at `Limits.maxCanvasCoordinate` and one step past it (`ItemBoundTests`), and `InkPoints` of `Limits.maxPointsPerStroke + 1` points as an exit test (`StrokeTests`).
- `RecordTests`, `ConstraintTests`, and `GridBoundTests` use the names of the limits, not their values. Geometry does not import Model, so `GridBoundTests` names the cell size with a note on its source.

### 6.36 The history budget in bytes (task 6.3, item 4)

- The history counts bytes, not points (D-183). `HistoryCost` gives 17 bytes per control point plus 192 bytes for each stroke, the measure of D-183, and the UTF-8 bytes plus 192 bytes for each text. A measure on the Mac in a release build gave the text bytes of D-88: a text box of 200 ASCII characters held 256 bytes of heap and its value of 144 bytes, one of 10,000 CJK characters 32,787 bytes and 144, within 5 % of the formula for texts of 200 characters and more.
- The budgets are 64 MiB per canvas and 256 MiB for all canvases, the "about 67 MB" and "about 270 MB" of D-76. The shown canvas reports the bytes of its history to `CanvasSessions` after each step and when it takes its session, so the stored sessions make room for it. Before, a taken history counted nowhere until the canvas left.
- `HistoryByteBudgetTests` holds 500 steps of 4,000 strokes of 2 points: the old point budget kept 2,000,000 such strokes, about 452 MB, and the test failed on 619beb3. The byte budget keeps them inside 64 MiB. `CanvasSessionsTests.shownCanvasCounts` covers the shown canvas.

### 6.38 The message at the stroke limit (task 6.2)

- The pen at `Limits.maxStrokesPerCanvas` shows "This canvas holds no more ink. Erase some ink or draw in a card." from the String Catalog of the canvas, once per pencil down at the limit (D-181). `StrokeLimitTests.penAtLimit` fills the canvas to the limit and hands two strokes in one touch and one in the next: the old code showed no message (`T-37-old`), and the new code shows it twice.
- An erase past `Limits.maxStrokesAfterErase` removes the strokes whole and shows no message (D-181, D-73). `StrokeLimitTests.eraseAtBound` covers it. It passes on the old code too, because the behavior is older.
- `CardMenuSnapshotTests.testStrokeLimitMessage` compares the message as an alert with its reference, made on the iPad.
- `CameraControllerTests.centerExactlyAtBound` covers `Limits.maxCameraCoordinate` exactly at the bound and one step past it (task 6.1, the gaps on the iPad).


### 6.39 A restore after a stop of the process (task 6.3, D-180)

- Before the copy, the restore writes the marker `library.sqlite.restoring` with the name of the pre-restore snapshot and flushes it with `fsync`. A good open removes it. At a launch, a marker and a library that does not open run the way back from the named snapshot and show `restoreUndone`. The way back has extra time of its own. storage.md section 7.5, steps 4 and 9, say so.
- `RestoreCrashTests` (Mac) stops the helper process with `SIGKILL` after the marker, during the copy, and after `SQLITE_DONE`. Each case opens with the old or the new content and passes `integrity_check`, and the marker names a snapshot that exists.
- `RestoreMarkerTests` (iPad) launches with a marker and a restored library whose clock row is damaged, as the process stopped before the way back in memory ran. The old code showed "libraryFailed" ("The launch failed: … hex clock value of 7 characters"). The new code restores the snapshot, shows `restoreUndone`, and removes the marker. A first form of the test wrote bytes that are no SQLite file, and the way back failed on it. A stop never leaves such a file, because the copy switches only at `SQLITE_DONE`, so the test now uses the case that can happen.
- The peak of a restore at the stroke limit (D-180, item 5): `BackupBudgetTests.testRestorePeakOfStrokeLimit` restores a library of 200,000 strokes of 60 points, 271 MB. In 3 runs it took 0.48 to 0.56 s, with a peak of 9 to 11 MB of the 5,012 to 5,065 MB available. The 78 MB peak of the Mac measure in D-180 was the footprint of the whole helper process. The peak is far from the memory limit, so the copy needs no new decision.
