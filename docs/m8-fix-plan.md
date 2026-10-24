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

### 4.1 Cause

The library uses WAL mode with `synchronous = NORMAL` (storage.md section 3) and the automatic checkpoint of SQLite. The SQLite documentation says that the automatic checkpoint runs "by the same thread that does the COMMIT that pushes the WAL over its size limit" of 1,000 pages, and that with `synchronous = NORMAL` "the checkpoint is the only operation to issue an I/O barrier or sync operation" (<https://sqlite.org/wal.html>). So one save in about every 80 runs a checkpoint and waits for a sync. If another writer of the process syncs at the same time, as in a full run, that save waits for the disk.

A temporary benchmark on the iPad copied the save pattern of the control run with raw SQLite: 20,000 rows of 4,800 bytes, then 640 saves of 10 rows. A WAL hook marked each save that ran a checkpoint. A disk stress thread wrote 1 MB blocks with `F_FULLFSYNC`, to copy the disk load of a full run. With the automatic checkpoint, the checkpoint saves took about 6 ms when quiet and 31 to 155 ms under stress (`.build/Runs/F-save-bench-2.xcresult`). That matches the 205 ms of the full run.

A connection has only one WAL hook, and `sqlite3_wal_autocheckpoint` replaces it. The first benchmark run thus ran without any checkpoint and is not valid (`F-save-bench-1.xcresult`). It showed one more fact: without checkpoints, the WAL grows, and a save that grows the WAL file can also wait 190 to 460 ms under stress.

### 4.2 Solutions

The SQLite documentation names the fix: "disable automatic checkpointing and run the periodic checkpoints in a separate thread". The benchmark compared it with the automatic checkpoint, with one save every 20 ms, 50 times faster than the save interval of 1 s of the app (`F-save-bench-3.xcresult`, 3 runs each):

| Variant | Quiet, slowest save | Under stress, slowest save | WAL, most pages |
|---|---|---|---|
| (a) Automatic checkpoint (now) | 18.1 to 18.7 ms, 8 saves over 10 ms | 178 to 306 ms, 10 to 13 saves over 10 ms | 1,013 |
| (b) No automatic checkpoint, a passive checkpoint on a second connection in a thread of its own at 1,000 pages | 1.1 to 1.4 ms, 0 over 10 ms | 10.7 ms, and about 300 ms once at save 1 | 1,084 to 1,112 |

The stall at save 1 came in both variants, when the stress thread started its first file, so it does not come from the checkpoint. Without a pause between saves, the checkpointer of (b) did not catch up, and the WAL grew to 9,035 pages (`F-save-bench-2.xcresult`). The app pauses at least 1 s between timed saves, so the checkpointer catches up there.

D-146 holds the decision, because (b) changes the storage design. The product owner chose (c) on 2026-10-24: (b), and a checkpoint on the write connection at a hard limit of 8,000 pages.

### 4.3 The change

1. `SQLiteConnection.trackWALPages()` sets a WAL hook that counts the pages of the WAL after each commit. The hook replaces the automatic checkpoint. `checkpointPassive()` runs `sqlite3_wal_checkpoint_v2` in the passive mode.
2. `WALCheckpointer` is an actor on its own serial queue with a second connection.
3. After each commit, `SQLiteLibraryRepository.checkpointIfNeeded()` asks the checkpointer at 1,000 pages, and runs the checkpoint on the write connection at 8,000 pages.
4. `RepositoryCheckpointTests` on the Mac: the write connection runs no automatic checkpoint (the WAL reaches 3,000 pages), the checkpointer lets the next save restart the WAL, the write connection checkpoints at the hard limit, and the rows stay. All 105 Persistence tests pass, and the line coverage of `Persistence` is 91.06 %.

### 4.4 Benchmark with the real repository

A temporary device test ran the 640 saves of the control run under the disk stress of section 4.1, in 3 alternating pairs of the build before the change (116c375) and the new build (`.build/Runs/F-save-alt-*.xcresult`):

| Build | Saves over 50 ms per run | p99 | Slowest save |
|---|---|---|---|
| Before | 17, 19, 16 | 92.3 to 115.0 ms | 125.0 to 400.5 ms |
| New | 1, 1, 1 | 11.3 to 17.9 ms | 132.4 to 164.3 ms |

Without stress, the p99 of `testSameSavesWithoutSnapshot` dropped from 8.1 to 8.3 ms to 0.7 to 1.2 ms.

The one slow save of the new build is the hard limit (`.build/Runs/F-save-why-1.xcresult`). The saves of the test come back to back, about every 5 ms. Under the stress, one checkpoint takes longer than that, so the checkpointer does not catch up, and the WAL reaches 8,000 pages. The write connection then runs the checkpoint, and that save waits for the sync: 135 ms in one run and 253 ms in the other. The app saves at most once per second, so it does not reach the hard limit this way. Full runs of `PointerDeviceTests` decide whether the test passes under the real load of a full run (section 6).

### 4.5 The end of a snapshot

Five full runs with the change of section 4.3 passed `make check` and 4 runs. Run 1 failed `SnapshotPerformanceTests.testSnapshotOfTwentyThousandStrokesWithSaves` with 54.58 ms, always at the last save of the snapshot run (`.build/Runs/F-full-1.xcresult`). Before the change, that save took 40 to 43 ms, and after it 44 to 55 ms.

A temporary device test split the last saves into phases with the `beforeCommit` hook of the repository and the `beforeRename` hook of the snapshot writer (`.build/Runs/F-snap-diag-1.xcresult`). The last save starts within 1 ms of the end of `VACUUM INTO`. It reaches `COMMIT` at once and then waits 31 to 45 ms. During the snapshot, the WAL grew to 18,000 to 26,000 pages, because `VACUUM INTO` pins it. The first commit after the snapshot ran the hard-limit checkpoint of D-146 on the write connection, which copied the whole backlog and synced it.

The product owner chose to hand the checkpoint off first (D-147). Benchmarks with 5 runs each:

| Rule | Last save of the snapshot run | Slowest save of the control run |
|---|---|---|
| D-146 | 44.7 to 45.4 ms | 10.9 to 12.8 ms |
| Hand off, wait when the checkpointer is busy | 52.0 to 55.3 ms, 5 of 5 failed | 23.2 to 24.2 ms |
| Hand off, wait when the checkpointer falls behind | 10.5 to 23.0 ms in the diagnosis, 0.9 to 23.9 ms in the test | 1.1 to 27.1 ms |

`.build/Runs/F-handoff-1.xcresult`, `F-handoff-2.xcresult`, and `F-behind-1.xcresult` hold the runs. In the second rule, the checkpointer was busy with the backlog that it had just started, so the save waited for it (own checkpoint 1, busy before yes, in `F-handoff-2.xcresult`).

The one slow save of the control run, 25 to 27 ms at about save 75, is the bound of D-147 working (`.build/Runs/F-early-1.xcresult`). The 20 prefill saves of 1,000 strokes leave the checkpointer busy with a WAL of 7,000 to 9,000 pages, and the first control saves add 1,000 pages during that checkpoint. Under the artificial disk stress, the same save took 98 to 195 ms in 3 of 5 runs.

`RepositoryCheckpointTests` has two more tests: an idle checkpointer gets the checkpoint past the hard limit after a pinned WAL, and a save does not wait for a checkpoint that just started past the hard limit. All 108 Persistence tests pass, and the line coverage of `Persistence` is 90.94 %.

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
