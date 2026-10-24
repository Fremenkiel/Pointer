# M9 work plan: backup and restore

This document breaks milestone M9 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on STO-02 to STO-07, D-14, D-20, D-21, D-32, D-51, D-97, and D-146 to D-165.

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

## 1. How to work

### 1.1 Device and build

1. Use only the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator, and never make one (learned rule 1 of `AGENTS.md`).
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. If it prints `passcodeRequired: true`, stop and ask the product owner to unlock the iPad.
3. Run one device suite with the command of section 1.1 of [m8-plan.md](m8-plan.md). Give each run that you compare a `-resultBundlePath` under `.build/Runs`, with the prefix `M9-`.
4. Compare two builds only with alternating runs (section 1.3 of [m6-fix-plan.md](m6-fix-plan.md)).
5. Read `os_proc_available_memory` every 0.25 ms for a memory measure. Start it after 1.5 s of steady memory (`OnScreenCanvas.waitForSteadyMemory()`). Make sure that each budget holds in a full run.

### 1.2 What a test can and cannot do

1. Package tests of `Persistence` run on the Mac. They can make libraries, snapshots, damaged files, and restores in a temporary folder.
2. The tests of `BackupFeature`, of the app target, and of the device measures run in `PointerDeviceTests` (D-77).
3. A test cannot pick a file in the document picker or a target in the share sheet. Keep the handlers thin. Test the code behind them: the copy of a picked URL, the checks, the restore, and the item of the share sheet.
4. A test can run Metal API validation with `TEST_RUNNER_MTL_DEBUG_LAYER=1` (section 3.4 of [review-2026-10-24.md](review-2026-10-24.md)).
5. Only the product owner can copy a snapshot to a Mac, open it with `sqlite3`, and delete and install the app.

## 2. Facts from the code and the research

Read on 2026-10-24 on branch `review-m8` at commit 6e21511. Paths are under `Packages/` unless they start with `PointerApp/` or `docs/`.

### 2.1 Persistence

1. `SQLiteLibraryRepository` has no close. `open(snapshot:)` has the precondition `connection == nil`. A failed open leaves `connection` and `statements` set ([review-2026-10-24.md](review-2026-10-24.md) section 3.2, items 1 and 2).
2. The type body of `SQLiteLibraryRepository` has 229 lines of the 250 of SIZE-03. New code goes into extension files.
3. `SQLiteConnection` opens `.readWrite` or `.readOnly`. It has no hardened mode for a file of unknown source.
4. `SnapshotWriter` writes daily and pre-migration snapshots with `VACUUM INTO` into `tmp/`, then renames the file into `Backups/`. `SnapshotFiles.dailyNameLength` is 32, so a daily name with a counter does not parse as daily today.
5. A failed snapshot keeps its partial file until the next launch (storage.md section 7.1).
6. `DeviceStateStore.save(lastWorkspace:navigationPath:)` can clear the path. The cameras are keyed by canvas ID.
7. `PreviewStore.removeAll()` exists and has no caller.

### 2.2 The app

1. `SceneDelegate` makes one `AppComposition` and calls `start()`. `start()` opens the device state, the snapshot writer, and the library, makes the clock (`makeClock`), and starts the selector. `CanvasLifetimeTests` proves that a composition can go away.
2. `HybridClock` continues after a `last` value at its start. It has no operation to move forward later.
3. `PointerApp/Info.plist` declares no type for `.sqlite`.
4. `BackupFeature` holds an empty namespace and depends on `DesignSystem`, `Model`, and `Persistence`. It has no tests.
5. `WorkspaceFeature` cannot import `BackupFeature` (ARCH-02). The app composes the two.

### 2.3 SQLite, measured on the Mac with SQLite 3.51

The iPad SDK has SQLite 3.54, so phase 0 measures again on the iPad.

1. `sqlite3_backup_init` refuses a destination with an open read ("destination database is in use").
2. During the copy, another connection can read and run a passive checkpoint, and a write gets `SQLITE_BUSY`.
3. A stop of the process at any point of the copy, and a full disk (`SQLITE_FULL`), keep the old content. `integrity_check` passes after each.
4. After the copy, the destination stays in WAL mode, and takes `user_version` and `auto_vacuum` from the source.
5. The copy does not call the WAL hook. The WAL then holds the whole library. A `TRUNCATE` checkpoint shrinks the `-wal` file to 0 bytes. `PASSIVE`, `FULL`, and `RESTART` do not shrink it.
6. Cached statements prepare again by themselves, but `SELECT *` can change its columns, and a statement on a table that the source lacks fails. All statements of the destination must go after a restore.
7. A WAL file without its `-wal` file loses the rows of the WAL, with each way to open it. The snapshots of the app are in rollback mode: header bytes 18 and 19 are 1.
8. On a full disk, `VACUUM INTO` leaves a target file of 0 bytes. The next run with that name fails with "output file already exists".
9. For 98.6 MB: `integrity_check` 0.02 s, the copy 0.12 to 0.24 s, the `TRUNCATE` checkpoint 0.14 to 0.18 s, `VACUUM INTO` 0.13 to 0.21 s.

Sources: <https://www.sqlite.org/c3ref/backup_finish.html>, <https://www.sqlite.org/howtocorrupt.html>, <https://www.sqlite.org/security.html>, <https://www.sqlite.org/lang_vacuum.html#vacuuminto>, <https://www.sqlite.org/pragma.html#pragma_wal_checkpoint>.

### 2.4 Apple

1. `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)` gives a security-scoped URL. Read it with `startAccessingSecurityScopedResource()` and a coordinated read of `NSFileCoordinator`. The coordinated read downloads a file of a provider first.
2. A `.sqlite` file has no type that the system declares. A `UTImportedTypeDeclarations` entry that conforms to `public.data` and `public.database` lets the picker show only such files.
3. On iPad, `UIActivityViewController` shows in a popover with an anchor (`sourceItem`, or `sourceView` and `sourceRect`).
4. `beginBackgroundTask` gives about 30 s. The expiration handler must end within about 1 s.

Sources: <https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller>, <https://developer.apple.com/documentation/foundation/nsfilecoordinator>, <https://developer.apple.com/documentation/uniformtypeidentifiers/defining-file-and-data-types-for-your-app>, <https://developer.apple.com/documentation/uikit/uiactivityviewcontroller>, <https://developer.apple.com/forums/thread/85066>.

## 3. Decisions

The product owner decided these on 2026-10-24. [decisions.md](decisions.md) gives the facts and the reasons.

| ID | Decision | Tasks |
|---|---|---|
| D-148 | Restore in place with the backup API, then build the app composition again, as at launch. | 1.4, 2.1, 2.2 |
| D-149 | End the text edit, place a pending card, and save before the restore. A failed save stops the restore. | 2.3 |
| D-150 | Drop all undo histories and navigation paths of the run. | 2.1 |
| D-151 | Keep all rows of the device state. The checks of the launch handle rows that no longer fit. | 2.2 |
| D-152 | The new clock continues after the larger of the old clock and the restored `lastTimestamp`, with the device ID of this iPad. | 2.2 |
| D-153 | Refuse a snapshot with a newer schema version, with a message. | 1.3 |
| D-154 | The snapshot before a restore has its own name, outside the 7 daily snapshots. Only the newest one stays. | 1.2 |
| D-155 | "Back up now" writes a daily snapshot. If the name exists, a counter joins it. A failed snapshot deletes its partial file. | 1.2 |
| D-156 | Open the picked file in place, copy it into `tmp/` in `Persistence`, and declare the `.sqlite` type. | 0.3, 1.3 |
| D-157 | Clear the preview cache at a restore. Cut the offscreen preview to its region, with an arena of a bounded size. | 1.6, 2.1 |
| D-158 | A named bound on the grid cells of one item. The load refuses a larger item as a damaged row. | 1.5 |
| D-159 | Moved to M10. | none |
| D-160 | The commands go into the list of the workspace selector. An alert asks before a restore. | 3.1, 3.2 |
| D-161 | Acceptance 3 runs on the same iPad: delete the app, install it again, and restore. | 5.2 |
| D-162 | Check the header in Swift, open the file read-only with the hardened settings of SQLite, run a full `integrity_check`, and compare the schema. | 1.3 |
| D-163 | No `application_id` in M9. | 1.3 |
| D-164 | `beginBackgroundTask` for the copy. At the expiry, stop and roll back. | 2.3 |
| D-165 | Measure in phase 0, then the product owner sets the budgets. Set on 2026-10-24: "Back up now" of D-56 under 0.5 s, a restore of D-56 under 1.5 s, each under 50 MB of peak memory growth. | 0.2, 4.3 |
| D-166 | The settings of D-162 that need `sqlite3_db_config` come from pragmas, an immutable read-only connection, and the refusal of views and triggers by the schema compare. Decided on 2026-10-24. | 1.3 |

## 4. Tasks

### Phase 0: preparation

#### 0.1 Baseline

1. Run `make check` with the iPad and `make coverage`.
2. Run the full `PointerDeviceTests` once, with a result bundle.
3. Record in section 6: erase, undo, and redo, the open of the D-56 canvas and its memory, the frame loops, the allocation counts, `SnapshotPerformanceTests`, and `PreviewMakerPerformanceTests`.

Done when: section 6 holds the baseline. Phase 6 compares against it (code-of-code.md section 5, item 10).

#### 0.2 The measures for the budgets

1. Add a temporary device test in `Persistence/Tests/PersistenceDeviceTests` with raw SQLite on a library of D-56 content: `VACUUM INTO`, a file copy of the snapshot, `integrity_check`, the backup with `step(-1)`, and the `TRUNCATE` checkpoint. Take 5 runs. Record the time and the peak memory growth of each step.
2. Repeat with a library of 200,000 handwriting strokes, about 1 GB of points, the largest library that the limits allow.
3. Give the measures to the product owner, with a recommended budget for "Back up now" and for a restore (D-165). Continue with phase 1 while the product owner decides.
4. Delete the temporary test.

Done when: section 6 holds the measures, and the product owner set the budgets.

Rules: PERF-03, D-165.

#### 0.3 The package, the tests, the type, and the checks

1. Add the test targets `BackupFeatureTests` and `BackupFeatureSnapshotTests` to `BackupFeature/Package.swift`.
2. Add their folders as synchronized groups of `PointerDeviceTests` in `Pointer.xcodeproj`, as `WorkspaceFeature` has them.
3. Add a String Catalog `BackupFeature/Sources/BackupFeature/Resources/Localizable.xcstrings`.
4. Add a `UTImportedTypeDeclarations` entry to `PointerApp/Info.plist`: identifier `dk.saarikivi.pointer.snapshot`, extension `sqlite`, conforms to `public.data` and `public.database` (D-156). Extend `make plist` to make sure that the entry exists.
5. Update the context map of `AGENTS.md` (AGENT-07).

Done when: `make build`, `make lint`, `make layers`, `make plist`, and `make self-test` pass, and an empty suite in each new test target runs on the iPad.

Rules: ARCH-02, AGENT-07, STYLE-05, D-77.

### Phase 1: Persistence and the renderer

#### 1.1 The close of the repository

1. Add `SQLiteLibraryRepository.close()`. It ends the scheduled save, waits for the running checkpoint, and drops the statements, the checkpointer, and the connection. Pending rows are a programmer error at the close: a precondition.
2. After a close, `open(snapshot:)` can run again.
3. A failed `open` drops its connection and statements, so the repository is closed again (review section 3.2, item 2).
4. Use the close in the test helpers that delete a library folder: `D56Library.remove()`, `LibrarySavePerformanceTests`, `SQLiteSpeedTests`, and the helpers of the app tests (review section 3.2, item 1).

Done when:

1. Mac tests show an open, a close, and a second open.
2. A Mac test shows a failed open that leaves the repository closed.
3. A Mac test shows a close during a running checkpoint.
4. A full device run logs no "vnode unlinked while in use".

Rules: TEST-03, TEST-04, CONTRACT-01, D-148.

#### 1.2 Snapshot names and failed snapshots

1. `SnapshotWriter.writeSnapshotNow()` writes a daily snapshot at once, for "Back up now" (D-155). If the name exists, it adds a counter: `Pointer-<yyyy-MM-dd-HHmmss>-2.sqlite`. The parser of daily names accepts the counter, so the rotation of 7 counts these files too.
2. A failed `VACUUM INTO` or a failed rename deletes the partial file at once (D-155). A stop of the process still leaves the file for the launch cleanup.
3. `SnapshotWriter.writePreRestoreSnapshot()` writes `Pointer-pre-restore-<yyyy-MM-dd-HHmmss>.sqlite` and deletes the older pre-restore snapshots after the new one exists (D-154). The daily rotation does not count it.
4. Update storage.md sections 7.1 and 7.4.

Done: Mac tests show these four cases.

1. Two snapshots in the same second.
2. A full disk that leaves no file. A `VACUUM INTO` into a folder that refuses the write stands in for it.
3. The rotation with counter names.
4. One pre-restore snapshot after two restores.

Rules: TEST-03, DOC-06, D-154, D-155.

#### 1.3 The import and the checks of a picked file

1. Add `SnapshotImport` in `Persistence`. It takes the security-scoped URL, calls `startAccessingSecurityScopedResource()`, copies the file with a coordinated read into `tmp/<uuid>.sqlite.partial`, and calls `stopAccessingSecurityScopedResource()` (D-156). It runs off the main actor.
2. It checks the 100 header bytes in Swift (D-162). The header must hold the SQLite magic and page size 4096. Bytes 18 and 19 must be 1. The `user_version` must be from 1 to `Schema.currentVersion`. The file size must be a multiple of the page size. A newer version gives its own error, so that the app shows the message of D-153.
3. Add the mode `.untrustedReadOnly` to `SQLiteConnection`: `SQLITE_OPEN_READONLY` with `immutable=1`, `SQLITE_DBCONFIG_DEFENSIVE` on, `SQLITE_DBCONFIG_TRUSTED_SCHEMA` off, triggers and views off, `cell_size_check` on, and `mmap_size` 0 (D-162).
4. It runs a full `PRAGMA integrity_check` and needs the single row `ok`.
5. It compares the tables, columns, and indexes of the file with the schema of its version. The expected schema comes from the migrations up to that version, run in a database in memory. No `application_id` (D-163).
6. Add one error case per refusal reason to `PersistenceError`, so that the app can name the reason.
7. Add fixtures to `Persistence/Tests/PersistenceTests/Fixtures`: a good snapshot, a wrong magic, page size 8192, a WAL file, a newer `user_version`, a damaged page, a missing column, an extra trigger.

Done when: each fixture gives its error, and the good snapshot passes. Line coverage of `Persistence` stays at or above 90 %.

Rules: SAFE-04, SAFE-05, SAFE-09, SAFE-10, TEST-02, TEST-08, D-153, D-156, D-162, D-163.

#### 1.4 The restore in the repository

1. Add `SQLiteLibraryRepository.restore(from:)`, which takes the checked file of task 1.3. It needs an empty pending set. It waits for the running checkpoint and makes sure that no statement holds a read.
2. It copies with `sqlite3_backup_step` in chunks of 1,024 pages, with a bounded retry on `SQLITE_BUSY` (FLOW-03). Between two chunks, it reads a stop flag. A stop calls `sqlite3_backup_finish`, which rolls the copy back (D-164).
3. After the copy, it runs a `TRUNCATE` checkpoint, drops all statements, and closes. The new composition opens the library again with its migrations (D-148).
4. The C calls live in `SQLiteConnection+Unsafe.swift` or a new `SQLiteBackup+Unsafe.swift` (SAFE-09).
5. Update storage.md section 7.5: the import of task 1.3, the steps here, and the clear of the preview cache.

Done: these Mac tests pass.

1. A restore of a snapshot over a different library gives the rows of the snapshot (storage.md section 9, M9 acceptance 2).
2. A stop in the middle keeps the old library.
3. A restore of an older `user_version` migrates at the next open.
4. The `-wal` file has 0 bytes after the restore.
5. A restore works while the checkpointer connection is open.

Rules: SAFE-09, SAFE-10, FLOW-03, TEST-09, D-148, D-164.

#### 1.5 Bounds of the items of a load

1. Add `Limits.maxGridCellsPerItem`. Its value comes from the largest legitimate item plus a margin: a stroke of 16,384 points drawn at zoom 0.25 across the 13-inch screen, and the largest card. Record the derivation in a source comment (DOC-03).
2. `SpatialGrid.insert` and `remove` get a precondition on the bound (FLOW-03).
3. The row readers of strokes, cards, and text boxes refuse an item past the bound as a damaged row. The load reports it with `rowsSkipped`, as for other damaged rows.

Done when: a Mac test loads a stroke row 10,000,000 points wide and gets one skipped row in milliseconds. Before, the same row took 96 s on the Mac.

Rules: FLOW-03, TEST-03, TEST-06, D-158.

#### 1.6 The bounded offscreen preview

1. `PreviewMaker.render` draws only the items in the region of its placement, from the grids of the content.
2. Its point arena has a byte budget from `RendererConfiguration`. A preview whose points do not fit draws the strokes in more than one pass.
3. It uses one `InkResources` for all previews instead of a new one per preview.
4. Benchmark the old and the new code with `PreviewMakerPerformanceTests` in alternating runs.

Done when: the time and the peak memory growth of the preview of a D-56 child drop, and the preview snapshot tests pass. The baseline is 0.184 s and 206 MB.

Rules: PERF-01, PERF-03, TEST-07, D-157.

### Phase 2: the app composition

#### 2.1 The close of the composition

1. Add `AppComposition.close() async`. It stops the idle timer and waits for a running daily snapshot. It cancels the load task, the open or the leave, and the preview renders. It drops the canvas screen, `sessions`, `paths`, `launchPath`, and `launchCamera` (D-150). It closes the repository (task 1.1) and the device state store.
2. After the close, it clears the preview cache with `PreviewStore.removeAll()` (D-157).

Done when: a device test closes a composition during a card open and with a pending card. The composition, its canvas screen, and its renderer then go away, as `CanvasLifetimeTests` shows them.

Rules: TEST-04, D-150, D-157.

#### 2.2 A new composition after a restore

1. `SceneDelegate` replaces the composition after a restore and calls `start()` on the new one.
2. The new composition takes the last value of the old clock. `makeClock` continues after the larger of that value and the restored `lastTimestamp`, with the device ID of this iPad (D-152).
3. The device state keeps all rows (D-151).
4. If the open of the restored library fails, the app restores the pre-restore snapshot through the same path and shows a message. A wrong restore can thus be undone (D-20).

Done: these device tests pass.

1. The clock after a restore of an older snapshot and of a newer one.
2. The fallback to the first workspace.
3. The cut of the stored path (D-112).
4. The way back after a failed open.

Rules: TEST-03, D-20, D-112, D-151, D-152.

#### 2.3 The restore flow

1. The order: end the text edit, place a pending card, save (D-149). If the save fails, stop with a message.
2. Write the pre-restore snapshot (task 1.2). Begin a background task. Run the restore (task 1.4). End the background task. Replace the composition (task 2.2).
3. At the expiry of the background task, set the stop flag of task 1.4 (D-164). At the next activation, the app shows that the restore did not run.
4. A refusal of task 1.3 shows its reason (D-153, D-162).

Done: these device tests pass.

1. The flow with a canvas, a text edit, and a pending card on the screen.
2. The flow with a refused file.
3. The flow with a stop at the expiry.

Rules: STO-06, STO-07, D-149, D-164.

#### 2.4 The "Back up now" flow

1. The order: end the text edit, place a pending card, save, and write the snapshot (task 1.2).
2. Open the share sheet with the URL of the snapshot in `Documents/Backups/`, anchored at the command (D-160).
3. The rotation can delete the shared file only after the completion handler of the share sheet runs. The new snapshot is the newest, so the rotation keeps it.

Done when: a device test makes the snapshot through the flow and checks the item of the share sheet.

Rules: STO-04, D-155.

### Phase 3: the interface

#### 3.1 The commands

1. `WorkspaceSelectorView` takes a list of library commands from the app, without a type of `BackupFeature` (ARCH-02). The list of the selector shows them below the workspaces.
2. `BackupFeature` gives two commands, "Back up now" and "Restore from a snapshot", with texts from its String Catalog and icons from `DesignSystem`.

#### 3.2 The question before a restore, the picker, and the messages

1. An alert asks before a restore. It says that the restore replaces all workspaces and that Pointer first saves the current library as a pre-restore snapshot in `Backups` (D-160).
2. The document picker opens with the type of task 0.3 and `asCopy: false` (D-156).
3. Add one message for each of these cases:
   - The file is not a Pointer library.
   - The file is damaged.
   - The file comes from a newer version of Pointer.
   - The file is an incomplete copy (WAL mode).
   - The disk is full.
   - The restore stopped.
   - The save failed.

#### 3.3 The snapshot tests

1. Snapshot tests of the list with the commands, of the alert, and of each message (TEST-07, D-114).
2. Add the new snapshot suites to the `snapshots` target of the `Makefile`.

Done when: the snapshot tests pass on the iPad, and `make snapshots` runs them.

Rules: STYLE-03, STYLE-05, TEST-07, D-160.

### Phase 4: device tests and measures

#### 4.1 The restore of the D-56 library

1. A device test makes the D-56 library and writes a snapshot. It changes the library and restores the snapshot. Then it compares all rows with the snapshot (M9 acceptance 2).

#### 4.2 The restore with a busy screen

1. A device test restores while a child canvas is open, a card flies, and a text edit runs. The screen after the restore shows the last workspace of the restored library, or the first one.

#### 4.3 The budgets

1. A device test measures "Back up now" and the restore of the D-56 library against the budgets of task 0.2 (D-165). It records the peak memory growth.
2. A device test measures the previews of a screen full of cards right after a restore (task 1.6).
3. Add the budgets to architecture.md section 12.

#### 4.4 Metal validation

1. Run the render suites with Metal API validation (section 1.2, item 4). Zero validation errors.

Done when: each test passes in a full run.

Rules: PERF-03, TEST-07, D-157, D-165.

### Phase 5: manual acceptance

#### 5.1 The manual tests for the product owner

1. Acceptance 1: tap "Back up now", save the file to a Mac (AirDrop or Files), and run `sqlite3 <file> "PRAGMA integrity_check"`. It prints `ok`.
2. Pick a snapshot in iCloud Drive that is not downloaded yet. The restore waits for the download and then runs.
3. Pick a file that is not a Pointer library. The app names the reason, and the library stays as it was.
4. Start a restore and move the app to the background at once. The app ends the restore or rolls it back, and the library opens.
5. Undo a restore with the pre-restore snapshot.

#### 5.2 Acceptance 3 on the same iPad (D-161)

1. Make two workspaces with ink, text, and cards, two levels deep. Tap "Back up now", and save the file to iCloud Drive or to a folder outside the Pointer folder.
2. Delete the app. Install it again. The app makes a new library and a new device ID.
3. Restore the file. The app shows the same workspaces and canvases.
4. Draw a stroke, and make sure that it saves and stays after a force quit.

Done when: the product owner reports a pass of each test.

### Phase 6: close

1. Run `make check` with the iPad, and `make coverage`.
2. Run the full `PointerDeviceTests` 5 times in a row (D-79). Compare each measure with the baseline of task 0.1. A measure can be at most 10 % slower.
3. Fill in section 6 of this plan, and the M9 status in [plan.md](plan.md).
4. Update storage.md sections 7.1, 7.4, and 7.5, architecture.md sections 11 and 12, and the context map of `AGENTS.md`.

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, D-79.

## 5. Facts to keep in mind

- `Persistence` is Tier A: it imports only `Foundation`, `os`, `SQLite3`, and other Tier A packages (ARCH-03). Its line coverage stays at 90 % or more.
- Only `Persistence` touches the file system (ARCH-04). The copy of the picked file and the clear of the preview cache run there. `BackupFeature` passes URLs only.
- Each package is at exactly 2.00 contract checks per function (CONTRACT-02). Each new function of `Persistence` and `Rendering` needs two real checks.
- The SQLite calls of the backup use unsafe pointers. They go into a file named `SQLite*+Unsafe.swift`, with a comment that says why each use is safe (SAFE-09).
- A repository test that deletes its folder must close the repository first (task 1.1). Else SQLite logs "vnode unlinked while in use", and a late checkpoint runs into the next test.
- A test that keeps a canvas screen in a local constant keeps it alive until the end of the scope. Put the steps in a function of their own.
- A new file in a synchronized group joins the next device build. Do not add files while `make check` runs.

## 6. Results

The tasks fill in this section.

### 6.1 Baseline (task 0.1)

Measured on 2026-10-24 on the iPad Pro 11-inch (M4) in Release, with the code of commit c420681 in the worktree `.build/Base/tree`.

1. `make check` failed in 7 minutes 53 seconds (`M9-check-base.log`). All steps before `make test` passed: build, analyze, and the Tier A tests on the Mac. In `PointerDeviceTests`, `StrokeStoreMemoryTests.testStoreOfTwoHundredThousandHandwritingStrokes` failed: "store 80.7 MB" against the limit of 75 MB. This is the fault of review section 1.7: the test reads the heap of the whole process, and a library that an earlier test deleted while SQLite held it still ran work. Up to 14 test cases still delete a library folder without a close (review section 3.2, item 1). Task 1.1 removes that cause, and the run at the end of phase 1 must show the test pass.
2. The full run of `PointerDeviceTests` passed: 398 tests, one of them the expected failure of D-137 (`M9-base-full.xcresult`). The store test measured 69.1 MB in this run.
3. `make coverage` passed: Geometry 90.88 %, Model 90.80 %, InkEngine 92.67 %, Persistence 90.87 %, Rendering 86.94 %, and Export 87.20 % (`M9-coverage-base.log`). In the instrumented run, `EraseUndoPerformanceTests` failed, as the `coverage` target expects.

The measures of the full run:

| Measure | Baseline |
|---|---|
| Erase, median and slowest of 5 | 24.66 ms, 25.67 ms |
| Undo, median and slowest of 5 | 18.76 ms, 19.91 ms |
| Redo, median and slowest of 5 | 17.78 ms, 25.23 ms |
| Open of D-56 to the first frame, median and slowest of 10 | 257.6 ms, 269.4 ms (load 71.9 to 84.7 ms) |
| Memory of the open D-56 canvas | held 337 MB, peak 350 MB |
| Transition between two D-56 canvases | parent 223 MB, open peak 354 MB, after the open 297 MB, leave peak 435 MB, parent freed |
| Store of 200,000 handwriting strokes | 69.1 MB |
| `SnapshotPerformanceTests`, snapshot with saves | 95 MB in 196 ms; 654 saves, median 0.25 ms, p99 0.79 ms, slowest 11.18 ms |
| `SnapshotPerformanceTests`, saves without a snapshot | 640 saves, median 0.28 ms, p99 0.63 ms, slowest 25.83 ms |
| `PreviewMakerPerformanceTests`, preview of D-56 | 0.189 s, peak memory growth 148 MB |
| `LibrarySavePerformanceTests` | 10 strokes: median 0.11 ms; 240 strokes: median 2.25 ms, slowest 3.58 ms |
| Export of D-56 | 6.90 s, 146 MB |
| Export of 200,000 handwriting strokes | 14.76 s, 277 MB |
| Eraser frame | CPU p50 0.14 ms, max 0.30 ms; GPU p50 0.41 ms, max 1.55 ms |
| Text layout of 5,000 boxes | median 57.4 ms |
| Text pass of 300 boxes | median 0.839 ms |

| Card flight | Time | Frames | Late |
|---|---|---|---|
| Open of the D-56 card | 467 ms to the child | 56 | 0 |
| Leave of the D-56 card | 590 ms | 2 child, 42 parent | 0 |
| Open of the empty card | 472 ms to the child | 56 | 0 |
| Leave of the empty card | 493 ms | 2 child, 43 parent | 1, the accepted late frame of D-137 |

| Frame loop | fps | Late | Render ms p50 / max | GPU ms p50 / max | Allocations p50 / p99 / max |
|---|---|---|---|---|---|
| few pan | 120.0 | 0 | 0.18 / 0.29 | 0.35 / 1.55 | 17 / 29 / 37 |
| dense 20k pan | 120.0 | 0 | 0.20 / 2.82 | 0.35 / 2.35 | 17 / 2,455 / 2,641 |
| dense 20k fast pan | 120.0 | 0 | 0.21 / 2.85 | 0.35 / 2.59 | 17 / 2,198 / 2,609 |
| dense 20k zoom | 120.0 | 0 | 0.20 / 2.88 | 0.35 / 2.09 | 17 / 2,103 / 2,678 |
| handwriting 200k pan | 120.0 | 0 | 0.20 / 2.18 | 0.35 / 5.01 | 17 / 2,167 / 2,168 |
| handwriting 200k zoom | 120.0 | 0 | 0.19 / 2.65 | 0.35 / 4.33 | 23 / 2,160 / 2,169 |
| D-56 text pan | 119.5 | 2 | 2.23 / 3.54 | 0.83 / 2.51 | 50 / 2,160 / 4,432 |
| D-56 text zoom | 119.7 | 1 | 2.18 / 3.46 | 0.84 / 3.24 | 50 / 4,368 / 5,662 |
| D-56 cards pan | 120.0 | 0 | 0.50 / 3.97 | 0.64 / 4.99 | 242 / 8,586 / 9,859 |
| D-56 cards pan at zoom 1 | 120.0 | 0 | 0.13 / 2.45 | 0.78 / 7.33 | 89 / 2,613 / 2,621 |
| D-56 cards zoom | 120.0 | 0 | 0.43 / 3.32 | 0.65 / 5.55 | 221 / 6,413 / 8,065 |

The D-56 preview render of `FrameLoopTests` took 37.7 ms.

| Allocation test | Count |
|---|---|
| `FrameAllocationTests` | frame p50 15, bare Metal frame p50 15 |
| `TransitionAllocationTests` | flight frame p50 15, open frame p50 15, bare frame p50 15 |
| `PreviewAllocationTests` | card pass p50 2, bare pass p50 2 |
| `TextPassAllocationTests` | text pass p50 2, bare pass p50 2 |
| `TextMoveAllocationTests` | move step median 6 |
| `EditAllocationTests` | `FrameRenderer.apply`: erase 14, undo 2, redo 1 |
| `HoverSampleAllocationTests` | pen and eraser: hover 0, bare move 0 |
| `TextEditFrameAllocationTests` | glide: Pointer max 0; spring: 0 before the last frame |
| `ZoomFrameAllocationTests` | spring median 0, max 140; glide max 0 |

### 6.2 The measures for the budgets (task 0.2)

Measured on 2026-10-24 on the iPad in Release with a temporary test in `PersistenceDeviceTests`, 5 runs per library, with raw SQLite calls (`M9-budget-2.xcresult`). Each step ran in a detached task after 1.5 s of steady memory, and the test read `os_proc_available_memory` every 0.25 ms. The iPad reports SQLite 3.51.0, not 3.54 as section 2.3 expected. The first run (`M9-budget-1.xcresult`) does not count: it closed the destination after the backup, and that close moved the WAL before the `TRUNCATE` step.

| Step | D-56 library, 97 MB | 200,000 strokes of 300 points, 949 MB |
|---|---|---|
| `VACUUM INTO` | 0.153 to 0.167 s | 1.719 to 1.851 s |
| File copy of the snapshot | 0.019 to 0.023 s | 0.016 to 0.023 s |
| `integrity_check` on the untrusted connection | 0.311 to 0.335 s | 2.945 to 3.077 s |
| Backup in steps of 1,024 pages | 0.120 to 0.135 s, WAL 98 MB | 1.041 to 1.055 s, WAL 954 MB |
| `TRUNCATE` checkpoint | 0.055 to 0.057 s, WAL 0 bytes after | 0.539 to 0.551 s, WAL 0 bytes after |
| Peak memory growth of each step | at most 11 MB | at most 11 MB |

The file copy on one APFS volume is a clone, so it costs no time for its size. A file of a provider that is not on the iPad yet adds its download.

The parts of the flows, from these measures:

- "Back up now" is a save and a `VACUUM INTO`: about 0.17 s for D-56 and 1.8 s for the largest library.
- A restore is the copy, the checks, the pre-restore snapshot, the backup, and the checkpoint: about 0.7 s for D-56 and 6.5 s for the largest library. The open of the new composition comes after it.
- Both stay far below the 30 s of `beginBackgroundTask`, so option (a) of D-164 holds.

Recommended budgets, for the product owner (D-165):

| Measure | Recommended budget |
|---|---|
| "Back up now" of the D-56 library, from the tap to the item of the share sheet | under 0.5 s, peak memory growth under 50 MB |
| Restore of the D-56 library, from the tap of the alert to the close of the repository | under 1.5 s, peak memory growth under 50 MB |
| "Back up now" and restore of 200,000 strokes | recorded, no budget, as D-145 does for the export of the same content |

The temporary test is deleted. The product owner set the recommended budgets on 2026-10-24 (D-165), and decided D-166 with its recommendation on the same day.

### 6.3 Persistence and the grid (tasks 1.1 to 1.5)

Measured on 2026-10-24, on the Mac for the package tests and on the iPad in Release for the device run.

1. Task 1.1 (commit 1c52107): `SQLiteLibraryRepository.close()` and the close of each test helper that deletes a library folder. `RepositoryCloseTests` shows an open, a close, and a second open, a failed open that leaves the repository closed, and a close during a running checkpoint. `failedOpenWritesNothing` failed with the old code: "an error was expected but none was thrown", and the stroke count was 1. A full run of `PointerDeviceTests` after task 1.5 logged "vnode unlinked while in use" 0 times, against 187 times in the baseline run (`M9-full-11.xcresult`). All 400 tests passed. `StrokeStoreMemoryTests` measured 63.1 MB.
2. Task 1.2 (commit 5d4629a): `writeSnapshotNow()`, the counter names, `writePreRestoreSnapshot()`, and the delete of a failed partial file. `SnapshotNameTests` covers two snapshots in one second, a `VACUUM INTO` into a folder that refuses the write, the rotation of 7 with counter names, and one pre-restore snapshot after two. With the old code, the second snapshot of a second failed with "output file already exists". The first form of the counter took the lowest free name. After the rotation deleted the oldest name of a second, the next snapshot took it, sorted as the oldest, and the rotation deleted it at once. The counter now follows the highest one of the second.
3. Task 1.3 (commit f2e5ed0): `SnapshotImport`, `SnapshotHeader`, the mode `untrustedReadOnly`, and the fixtures of `make-snapshot-fixtures.sh`. Each fixture gives its error, and the good snapshot passes. `sqlite3_db_config` is a C variadic function that Swift does not import, so the untrusted mode sets its settings through pragmas (D-166, open). Persistence line coverage: 90.44 %.
4. Task 1.4 (commit b9895b9): `restore(from:stop:)`, `SQLiteBackup+Unsafe.swift`, and `RestoreStop`. `RepositoryRestoreTests` passes: the rows of the snapshot after a restore over another library, the old library after a stop in the middle and before the first step, the migration of an older version at the next open, a `-wal` file of 0 bytes, and a restore with the checkpointer connection open. Without the `TRUNCATE` checkpoint, the `-wal` test fails.
5. Task 1.5 (commit bde5c5a): `Limits.maxGridCellsPerItem` is 4,096 cells of 512 points. The largest item that the app can make is a text box of 10,000 line breaks: 10,001 lines of 20.02 points, at most 393 rows by 3 columns, 1,179 cells. The readers of strokes and cards refuse a larger item. A text box needs no check at the load, because its text length and `TextStyle.maxWidth` bound it, so the plan item for the text box reader is not needed. A stroke row 10,000,000 points wide is one skipped row: the load took under 1 s on the Mac, and the test passes in 0.03 s. With the old code, the stroke loaded and the test failed at `content.strokes.isEmpty`.
6. Task 1.6: `PreviewMaker` is an actor that the app keeps once, with one `FrameRenderer` and one `InkResources` for all previews. It draws only the items in the region of the placement, and the strokes in passes whose arena keeps `RendererConfiguration.previewArenaByteBudget` (32 MB). Alternating runs of `PreviewMakerPerformanceTests` for the preview of a D-56 child:

| Run | Time | Peak memory growth |
|---|---|---|
| Base 1 (`M9-preview-base-1.xcresult`) | 0.187 s | 202 MB |
| New 1 (`M9-preview-new-1.xcresult`) | 0.029 s | 90 MB |
| Base 2 (`M9-preview-base-2.xcresult`) | 0.189 s | 202 MB |
| New 2 (`M9-preview-new-2.xcresult`) | 0.029 s | 96 MB |
| New 3, first preview of a maker (`M9-preview-new-3.xcresult`) | 0.037 s | 90 MB |
| New 3, second preview of the same maker | 0.032 s | 66 MB |

`PreviewRenderTests` passes, with the compare of the offscreen preview and the preview of the screen. `PreviewPassesTests` covers no stroke, one pass, a stroke of the point limit per pass at the smallest budget, and the budget of each pass. In run new 1, the budget test failed, because its strokes fit one pass at twice the smallest budget. The test now uses the smallest budget.

### 6.4 The app composition (tasks 2.1 to 2.4)

Measured on 2026-10-24 on the iPad in Release (`M9-phase2-5.xcresult`). All tests of this section pass, with `CanvasLifetimeTests`.

1. Task 2.1: `AppComposition.closeScreens()` ends the idle timer, waits for a running daily snapshot, cancels the load and an open or a leave, drops the session of the screen, removes the canvas, and drops the sessions, the paths, and the camera of the launch. `close()` then saves, closes the repository and the device state, and clears the preview cache. A closed `PreviewStore` refuses each later write, so a render that ends after the close cannot put a preview of the old library into the cleared cache. `CanvasViewController.flushRows()` waits until the library took the rows that the canvas sent. `CompositionCloseTests` closes a composition during a card open with a pending card: the composition, the canvas, its renderer, and its engine go away, and the pending card is in the library.
2. Task 2.2: `SceneDelegate` makes a new root view and a new composition after a restore, and `start(after:)` takes the handoff: the last clock value, a message, and the pre-restore snapshot. The device state keeps all rows (D-151). If the restored library does not open, the new composition restores the pre-restore snapshot through the same path and hands over to a third composition with a message. A closed repository takes a restore for this case. `RestoreFlowTests` covers the clock after an older and a newer snapshot, the first workspace when the last one is not in the snapshot, the cut of the stored path, and the way back after a snapshot whose `lastTimestamp` row does not decode.
3. Task 2.3: `restore(from:)` copies and checks the picked file, saves the work on the screen, writes the pre-restore snapshot, closes the screens, and copies with extra time in the background. `RestoreFlowTests` covers the flow with a text edit and a pending card on the screen (both are in the pre-restore snapshot), a refused file (the screen stays and takes edits, and the message shows), and a stop at the end of the extra time (the old library opens with the message of the stop).
4. Task 2.4: `backUpNow()` saves the work and writes a daily snapshot. `share(_:at:)` opens the share sheet in a popover, and no idle snapshot starts until it closes. `BackUpNowTests` makes the snapshot through the flow, checks it with `integrity_check`, and finds the share sheet on the screen.

The test harness first showed its container from a view of the test host, without a parent controller. UIKit then refused the popover of the share sheet: "Attempt to present <UIActivityViewController> ... whose view is not in the window hierarchy". The harness now makes a window of its own with the container as the root, as `SceneDelegate` does. The share sheet shows after UIKit loads its activities, so the test waits for it.

The changes of tasks 2.1 to 2.4 share `AppComposition`, so they are two commits: the parts in `Persistence` and `CanvasFeature`, and the app composition with its tests.

### 6.5 The interface (tasks 3.1 to 3.3)

Measured on 2026-10-24 on the iPad in Release.

1. Task 3.1: `WorkspaceSelectorView` takes a list of `LibraryCommand` values from the app and shows them below the workspaces. `LibraryCommand` is a type of `WorkspaceFeature` with a title, an SF Symbol, and an action, so the selector knows no type of `BackupFeature` (ARCH-02). `BackupCommand` gives "Back up now" and "Restore from a snapshot" with texts from the String Catalog of `BackupFeature` and the icons `DesignSystem.Icon.backUp` and `.restore`. The app composes the two in `AppComposition+Commands.swift`.
2. Task 3.2: `RestoreAlert` asks before a restore and names the pre-restore snapshot in `Backups`. `SnapshotPicker` opens the type `dk.saarikivi.pointer.snapshot` with `asCopy: false`. `BackupMessage` has the seven messages of the plan and one more, `restoreUndone`, for the way back of task 2.2, item 4. `BackupFeatureTests` covers the message of each refusal reason, the texts, the alert, the picker, and the share sheet.
3. Task 3.3: `BackupFeatureSnapshotTests` compares the alert and the 8 messages with reference images, and `WorkspaceSelectorSnapshotTests` the list with the commands (`M9-snap-1.xcresult`, `M9-snap-2.xcresult`). The references are images of the iPad, reviewed before the copy into `References`. `make snapshots` runs the new suite and passes (`M9-snapshots-phase3.log`). An XCTest class keeps no attachment of Swift Testing, so the alert test adds an XCTest attachment that stays only on a failure.

### 6.6 Device tests and measures (tasks 4.1 to 4.4)

Measured on 2026-10-24 on the iPad in Release (`M9-phase4-1.xcresult`).

1. Task 4.1: `D56RestoreTests` makes the D-56 library, writes a snapshot, adds 1,000 strokes, and restores the snapshot. After the restore, 0 rows differ from the snapshot in each table, and the library holds 20,000 strokes (M9 acceptance 2).
2. Task 4.2: `BusyRestoreTests` restores while a child canvas is open, the open of a card in it flies, and a text edit runs. The new composition shows the first workspace of the restored library at level 0, with its card, and holds no undo history.
3. Task 4.3: `BackupBudgetTests` measured "Back up now" of the D-56 library at 0.165 s with a peak memory growth of 11 MB, and a restore at 0.601 s with 8 MB. Both stay under the budgets of D-165 (0.5 s, 1.5 s, and 50 MB). `PreviewsAfterRestoreTests` rendered 100 previews of children with 2,000 strokes each in 0.30 s, 3.0 ms each, with a peak memory growth of 109 MB. architecture.md section 12 holds the budgets.

4. Task 4.4: a full run of `PointerDeviceTests` with `TEST_RUNNER_MTL_DEBUG_LAYER=1` logged "Metal API Validation Enabled" and 0 validation errors (`M9-validation-1.xcresult`). Three allocation tests failed in that run only: `FrameAllocationTests` (128 against a bare frame of 121) and the two tests of `TransitionAllocationTests` (132 against 121). Each compares a frame with a bare Metal frame, and the debug layer allocates for each Metal call: the bare frame took 121 allocations with validation and 15 without it. The frames of Pointer make more Metal calls than the bare frame. The same tests pass at 15 against 15 in each full run without validation.

The check at the end of phase 3 failed in `StrokeStoreMemoryTests` (82.7 MB against 75 MB), the fault of the baseline. Nine more full runs looked for the cause (`M9-probe-*`, `M9-relief-*`, `M9-reserve-*`, `M9-parts-*`). Other threads allocate nothing during the build, `malloc_zone_pressure_relief` gives back nothing, and the arrays of the store grew to capacities that depend on the blocks of libmalloc. `StrokeStore.add(contentsOf:)` reserves each list for the load, and `FrameRenderer.load` uses it. The collections then hold 50.9 to 51.7 MB in each run, but the heap growth stays at 66.4 to 76.9 MB, and one of six runs failed. D-167 holds the question of the measure for the product owner.

