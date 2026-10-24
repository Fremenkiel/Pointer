# M8 fix plan: three flaky device tests

The close of M8 ([m8-plan.md](m8-plan.md) section 6.7) left three device tests that fail in some full runs and pass in runs alone. The product owner did not accept them on 2026-10-24 and asked for a fix of each cause (learned rule 2 of [AGENTS.md](../AGENTS.md)). This plan defines the behavior and the failure of each test, gives the sources, and records the benchmarks of the possible solutions.

All rules of [code-of-code.md](code-of-code.md) apply. The device is the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Each run that this plan compares has its own result bundle under `.build/Runs`.

## 1. The three failures

| Test | Behavior that the test checks | Failure |
|---|---|---|
| `TextEditFrameAllocationTests.testGlideFramesWithALongText` | A glide frame with an open text edit makes no heap allocation in Pointer code (PERF-01). UIKit work to move the edit view does not count (D-43). | "edit frame max 5, bare move max 4": one glide frame made one allocation more than the largest bare move of a text view. |
| `SnapshotPerformanceTests.testSameSavesWithoutSnapshot` | Each save of 10 strokes takes less than 50 ms (architecture.md section 12, "Save after a stroke"). | One save took 205.07 ms in a full run. |
| `AppMessageTests.messageOverPalette` | A message shows as an alert on top of an open palette (architecture.md section 10). | `palette.presentedViewController` was not an alert with the message. |

## 2. How to work

1. Find the cause with a measure on the iPad before a fix. A guess is not a cause.
2. Read the cause in a reliable source: Apple documentation, the SQLite documentation, or the source of the library.
3. Benchmark each possible solution on the iPad with enough runs to show the failure rate before and after.
4. A fix of a test must still catch the fault that the test exists for. Put the fault back for one run and make sure that the test fails.

## 3. The glide allocation test

### 3.1 Cause

A temporary diagnostic test recorded the call stack of each main-thread allocation of each glide frame with `backtrace`. The buffers of the trace were made before the trace (`.build/Runs/F-glide-diag-2.xcresult` and `F-glide-diag-3.xcresult`). Each frame made 4 allocations, all from UIKitCore, Foundation, or libobjc below `TextEditView.layOut`, which moves the edit view. In 3 of 20 runs, frame 79 made a fifth allocation: libobjc called from UIKitCore, also below `TextEditView.layOut`. Pointer code made no allocation in any frame.

The old test compared the largest count of the glide frames with the largest count of a bare move of a text view. Both counts measure UIKit work, and UIKit sometimes makes one allocation more. In 40 runs, the bare move had 5 allocations 4 times, and the glide frames had 5 allocations 3 times. If the extra allocation fell in the glide frames, the test failed.

### 3.2 Solutions

| Solution | Result |
|---|---|
| (a) Compare the medians instead of the maxima. | Not taken. A median does not show a Pointer allocation in one frame, for example at the end of a glide. |
| (b) Count each allocation by its caller. The first frame above malloc, the runtimes, Foundation, Core Text, and Core Graphics decides: an image of Pointer counts, and UIKit, Core Animation, and Metal do not (D-43). | Taken. |

`AllocationTracer+Unsafe.swift` in the Rendering tests (SAFE-09 allows the file in Tier B) does (b). The test requires 0 Pointer allocations per frame, and more than 0 system allocations, which shows that the trace ran.

### 3.3 Benchmark

1. `.build/Runs/F-glide-fix-2.xcresult`, 20 iterations of the three tests: 60 of 60 passed. Each glide had 0 Pointer allocations. UIKit made 5 allocations in 4 of 40 glides. The old test fails on such a glide.
2. The control test counts one array of the test code as 1 Pointer allocation.
3. For one run, the old fault was back: a new `TextLayout` in each `TextEditView.layOut`. The test failed with 163 Pointer allocations per frame for the long text and 20 for the short text (`.build/Runs/F-glide-inject.xcresult`).

## 4. The save stall

## 5. The message over the palette

### 5.1 Cause

The test presented a palette on the root screen of the test host, showed a message, and dismissed the palette at the end. A state report in the failure message showed the chain `AppViewController`, `UIViewController`, `UIAlertController`: an old palette with an alert was still on the root screen. The new palette did not show, and `showMessage` found an alert on top and showed nothing.

1. With 5 iterations of the test alone, 1 passed and 4 failed (`.build/Runs/F-msg-2.xcresult`). With the suites that also present on the window of the host, 9 of 10 failed (`F-msg-1.xcresult`). So the test left its own palette and alert behind.
2. The wait loop of the test read `isBeingPresented`. Apple documents `transitionCoordinator` as the object of "a currently active transition", or `nil` if no transition is in progress (<https://developer.apple.com/documentation/uikit/uiviewcontroller/transitioncoordinator>). The loop ended while the animated presentation of the alert still ran. The `dismiss(animated: false)` of the test then came during that transition and did not dismiss.
3. In a full run, the test runs once, so its own leak cannot make it fail. Other suites run at the same time (<https://developer.apple.com/documentation/testing/parallelization>), and their screens present on the same window. A presentation that another test leaves or makes on the root screen has the same effect as the leak.

### 5.2 Solutions

| Solution | Alone, 10 runs | With the neighbor suites, 10 runs |
|---|---|---|
| Before the fix | 4 of 5 failed | 9 of 10 failed |
| (a) Wait on `transitionCoordinator` of the screen and of each presentation above it, and make sure that the dismissal ended | 0 failed | 0 failed |
| (b) As (a), and the test makes a window of its own with its own `AppViewController` | 0 failed | 0 failed |

(b) is taken. (a) fixes the leak, but the test still depends on the root screen that other suites use. (b) shares nothing with them (TEST-04). The window does not become the key window, which other tests use. The neighbor suites are `PencilFlightTests`, `NavigationFailureTests`, `DeepTreeTests`, `CardMenuSnapshotTests`, and `NavigationCancelTests`.

### 5.3 Control

For one run, the fault F-12 was back: `showMessage` presented the alert on the app screen instead of on the top presentation. The test failed (`.build/Runs/F-msg-inject.xcresult`).

## 6. Results
