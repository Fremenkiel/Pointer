# M3 work plan: storage and workspaces

This document breaks milestone M3 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on D-27, D-29, D-30, D-32, D-50, and D-51, which the product owner decided on 2026-10-18. Do the tasks in the order of section 3. Section 2 lists the questions D-52 to D-56. The product owner decided all five on 2026-10-18.

## 1. Step 0: show the Backups folder in the Files app

STO-02 puts the snapshots in a folder that the Files app shows under "On My iPad > Pointer > Backups". [storage.md](storage.md) section 7.2 names the two `Info.plist` keys that make the folder visible. `PointerApp/Info.plist` does not have them yet.

1. Add these keys to `PointerApp/Info.plist`:

   ```xml
   <key>UIFileSharingEnabled</key>
   <true/>
   <key>LSSupportsOpeningDocumentsInPlace</key>
   <true/>
   ```

2. Add a `plist` target to the `Makefile`, and add it to `check`. If a key is missing or is not `true`, the target fails:

   ```
   plutil -extract UIFileSharingEnabled raw PointerApp/Info.plist | grep -qx true
   plutil -extract LSSupportsOpeningDocumentsInPlace raw PointerApp/Info.plist | grep -qx true
   ```

3. Add the `plist` target to the command list of `AGENTS.md`.
4. Install the app on the iPad and open the Files app. Make sure that "On My iPad" shows a "Pointer" folder. If the folder shows only after the app writes a file into `Documents/`, record this fact in [storage.md](storage.md) section 7.2. The `Backups/` folder itself comes with the snapshot task.

Done when: `make check` passes with the new target, and the Files app on the iPad shows the "Pointer" folder.

Requirement and rules: STO-02, STO-03, ARCH-01 (the keys belong to the app target), AGENT-07.

## 2. Open questions

These questions are in [decisions.md](decisions.md). Each one names the task that waits for it.

| ID | Question | Decision or recommendation | Task |
|---|---|---|---|
| D-52 | What the app shows at the first launch, and after a delete of the current workspace | Make a workspace named "Workspace" at the first launch. After a delete, open the first workspace of the list. If no workspace is left, make a new one. | 3.8, 3.9 |
| D-53 | Store, write points, and camera limit of the device state | A separate `device.sqlite` with one row per camera. Write at three events: the camera comes to rest, the workspace changes, and the app moves to the background. Drop the camera that was used least recently. | 3.7 |
| D-54 | How the automated crash test of acceptance 1 stops the process | A Mac test starts a helper process that saves strokes through the repository and stops it with `SIGKILL`. A UI test on the iPad is slower and cannot see the database. | 3.10 |
| D-55 | Whether the `-fillStrokes` launch argument saves its strokes | No. The fill content stays in memory, so a performance run does not fill the library. | 3.9 |
| D-56 | The content of acceptance 3 | 20,000 strokes of 300 control points, 5,000 cards, and 5,000 text boxes of 200 characters, opened to the first frame. | 3.10 |

## 3. Tasks

### 3.1 Step 0

Section 1.

Status: done on 2026-10-18 in commit 5ffd059. `make check` passes with the `plist` target. On the iPad Pro 11-inch (M4), "On My iPad" showed no "Pointer" folder while `Documents/` was empty. After a test file was copied into `Documents/`, the "Pointer" folder showed with the file. [storage.md](storage.md) section 7.2 records this fact.

### 3.2 Model types (Tier A)

1. Add the ID types `WorkspaceID`, `CardID`, and `TextBoxID` (D-17).
2. Add `RecordMeta`, `Workspace`, `Card`, `TextBox`, and `EraseRecord` as [data-model.md](data-model.md) section 7 defines them. Each initializer checks the limits of its type. Examples are the title length of 1 to 120 characters after a trim and the card size of at least 64 by 48.
3. Add `FractionalIndex` with `between(_:_:)` (data-model.md section 6). A key has at most 64 characters.
4. Add `cards`, `textBoxes`, and `erased` to `CanvasContent` (data-model.md section 8). Add the node limit `Limits.maxNodesPerCanvas`.
5. Add `DeviceState` (data-model.md section 10). It holds the device ID, the last workspace, and the navigation path, but no cameras.
6. Add the protocol `LibraryRepository`: list the workspaces, create, rename, and delete a workspace, load the live content of a canvas, and send changed rows. Its errors are typed (SAFE-04).
7. Add parameterized tests at each limit: zero, one, the limit, and the limit plus one (TEST-06).

Done when: the line coverage of `Model` is at least 90 % (TEST-02), and `make check` passes.

### 3.3 SQLite wrapper (Tier A)

1. Add `SQLiteConnection` and `SQLiteStatement` in files named `SQLite*+Unsafe.swift` (SAFE-09). Their public API uses `Data`, `String`, `Double`, and `Int64` only.
2. Add `PersistenceError`, the one error enum of the package (SAFE-04).
3. Compare each SQLite result code with the expected code. A mismatch throws `PersistenceError` with the text of `sqlite3_errmsg` (SAFE-10).
4. Use prepared statements with bound parameters only (SAFE-10).
5. The connection runs the statements of [storage.md](storage.md) section 3.1 at open. A new database also gets `PRAGMA page_size = 4096` before the first table.
6. Each test uses its own temporary folder (TEST-04).

Done when: the tests cover the open, the pragmas, a bind and a read of each value type, and a failed statement that throws with its message.

### 3.4 Schema, codecs, and migrations (Tier A)

1. Add schema version 1 with all tables of [storage.md](storage.md) section 3.3, with the changes of D-29 and D-30.
2. Add the codecs of storage.md sections 3.2 and 3.4: the 28-byte clock value, the 16-byte ID, and the point BLOB. A wrong length throws. Integer conversions use `init(exactly:)` (SAFE-05).
3. Add the migration runner of storage.md section 6. Before the first step, it writes a pre-migration snapshot through the snapshot writer of task 3.6. If `user_version` is newer than the app knows, the repository opens the library read-only.
4. Add a fixture database of version 1 under `Packages/Persistence/Tests/PersistenceTests/Fixtures/`, and add the folder to the context map of `AGENTS.md` (TEST-08, AGENT-07).

Done when: a round-trip test passes for each row type and the point BLOB. Each `CHECK` refuses a value one past its limit. The fixture test opens version 1 and reads the expected rows.

### 3.5 Repository actor (Tier A)

1. Add `SQLiteLibraryRepository`, an actor with a custom serial executor on a `DispatchSerialQueue` (architecture.md section 11).
2. Read path of storage.md section 5: the workspaces, and the live rows of one canvas only.
3. Write path of storage.md section 4: the pending set, the throttle of 1 second, a save at pencil lift, and a save at the move to the background (D-27). The throttle takes an injected clock, so the tests use no real clock (TEST-04).
4. Write the `library` row `lastTimestamp` in each save transaction (storage.md section 3.3).
5. After a failed transaction, keep the rows and try again at the next save. After three failures in a row, report the fault to the main actor (storage.md section 4).
6. At launch, remove tombstones older than 30 days, run `PRAGMA incremental_vacuum`, and delete the `*.sqlite.partial` files in `tmp/` (storage.md sections 5 and 7.1).
7. Add an `OSSignposter` interval around each save. The budget is 50 ms off the main actor (architecture.md section 12).

Done when: the crash test with an injected failure between `BEGIN` and `COMMIT` passes. The throttle test passes with a clock that moves 10 seconds. A corrupt point BLOB gives a fault for that stroke, and the other strokes of the canvas still load (storage.md section 9).

### 3.6 Snapshot writer (Tier A)

1. Add `SnapshotWriter`, an actor with its own read-only connection and its own serial executor (D-32).
2. Write the snapshot to `tmp/` with `VACUUM INTO`, then rename it into `Documents/Backups/` (storage.md section 7.1).
3. Keep the newest 7 snapshots (D-21).
4. Start a snapshot at the first idle moment after 24 hours while the app is active (storage.md section 7.2). The writer takes the idle signal from the app. It does not watch the input itself.

Done when: the snapshot test compares all rows of the snapshot with the live database. A snapshot that stops before the rename leaves no file in `Backups/`. A save during a snapshot does not wait for the snapshot.

### 3.7 Device state (Tier A)

1. Add `DeviceStateStore`, an actor that owns `device.sqlite` in `Library/Application Support/Pointer/` (storage.md sections 2 and 10, D-53). It uses the wrapper of task 3.3.
2. At launch, read the `device` rows and the camera of the last workspace only. When another canvas opens, read its camera.
3. Write at the three events of storage.md section 10. A camera write changes one row and keeps the 1,000 most recently used cameras.
4. A missing or damaged file gives a new file with a new `DeviceID`. The store keeps the damaged file as `device.sqlite.damaged`, logs the fault, and does not stop.

Done when: a round-trip test passes for each row. A test with 1,001 cameras keeps the 1,000 most recent ones (TEST-06). A damaged file gives a new state. The time of the launch read on the iPad is in section 4.

### 3.8 Workspace selector (Tier C)

1. Add the selector of WS-01 to WS-03 in `WorkspaceFeature`: a SwiftUI view in the top left corner with the current name and a list.
2. Switch, create, and rename a workspace. A title has 1 to 120 characters after a trim.
3. Delete a workspace after a confirmation (D-11). The workspace becomes a tombstone.
4. At `Limits.maxWorkspaces`, the selector refuses a new workspace with a message.
5. The behavior at the first launch and after a delete of the current workspace follows D-52.
6. Add a snapshot test of the selector (TEST-07). Use tokens from `DesignSystem`.

Done when: the snapshot test passes, and tests cover create, rename, delete, and the limit.

### 3.9 Composition and canvas

1. `PointerApp` opens the repository and the device state. It makes the clock from the `lastTimestamp` of the library and the `DeviceID` of the device state.
2. At launch, the app opens the last workspace at its last camera (WS-04).
3. `CanvasFeature` loads the live strokes of the canvas from the repository. After each handoff, it sends the new stroke row to the repository. At pencil lift, it asks for a save.
4. At the move to the background, `PointerApp` asks for a final save with `UIApplication.beginBackgroundTask` (storage.md section 4).
5. `PointerApp` sends the idle signal to the snapshot writer.
6. The app shows a message for a library with a newer schema and for three failed saves in a row (storage.md sections 4 and 5).
7. The launch argument `-fillStrokes` follows D-55.

Done when: on the iPad, a drawing stays after a force quit and a new launch, and the app opens the last workspace at the last camera.

### 3.10 Acceptance tests

1. Acceptance 1: the crash test of D-54. Strokes arrive without a pause for 10 seconds, the process stops, and at most 2 seconds of strokes are missing.
2. Acceptance 2: on the iPad, wait for a snapshot or set the newest snapshot back by 24 hours in a debug build. Copy the file from the Files app to a Mac, and run `sqlite3 <file> 'PRAGMA integrity_check'`. The result must be `ok` (D-51).
3. Acceptance 3: a performance test in `PointerDeviceTests` opens the content of D-56 to the first frame on the iPad. The budget is 300 ms (architecture.md section 12). Record the baseline in this document (PERF-03).
4. Acceptance 4: all tests of storage.md section 9 pass.
5. Measure the read and write speed of SQLite on the iPad and record it in [research.md](research.md) section 5. Review B-4 left this measurement for M3.

Done when: all four acceptance criteria of M3 pass, and the results are in section 4 of this document.

### 3.11 Close of M3

1. The line coverage of `Persistence` is at least 90 % (TEST-02).
2. The documents in `docs/` match the code.
3. Run the full checklist of [code-of-code.md](code-of-code.md) section 5.
4. Rerun the M2 performance tests on the iPad. A change in `CanvasFeature` must not make them more than 10 % slower.

## 4. Results

### 4.1 Step 0

| Item | Target | Result |
|---|---|---|
| `make plist` with both keys `true` | passes | passes |
| `make plist` with a key `false` or missing | fails | fails (exit 1) |
| "Pointer" folder in the Files app | shows | shows after `Documents/` holds a file |
