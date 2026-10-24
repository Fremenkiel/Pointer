# Storage and backup

This document describes where Pointer stores data, how it writes data safely, and how you back up the library. The data types are in [data-model.md](data-model.md).

## 1. Strategy

Pointer stores the whole library in one SQLite database. The app uses the SQLite library that ships with iPadOS (`import SQLite3`). It adds no third-party code and no wrapper library.

- The live database is private to the app. The Files app does not show it.
- Each card, text box, workspace, and stroke is one row. Ink points are a binary column (a BLOB) in the stroke row.
- Each save is one transaction. A transaction writes all of its rows or none of them.
- For backup, the app writes a complete copy of the database (a snapshot) into a folder that the Files app shows. You back up with a copy of a snapshot file.

Reasons:

1. Speed. SQLite reads 1,000 small records about 250 times faster than 1,000 files, and writes them about 250 times faster in one transaction. See [research.md](research.md) section 5.
2. Atomic changes across records. A command that changes several rows (for example, an erase that removes one stroke and adds two parts) is saved in one transaction.
3. One file to back up. A snapshot is one consistent file that you can copy, store, and restore.
4. Room to grow. SQLite has full-text search (FTS5) for a later search feature.

The costs:

1. A live SQLite database with its `-wal` and `-shm` files is not safe to copy while the app writes to it. Thus backups must use snapshots, never the live files.
2. A snapshot is the whole library. A backup uploads the whole file each time, not only the changes. Section 8 shows how a later version can upload only changes.
3. The SQLite C API needs unsafe pointers in Swift. A small wrapper keeps them in one place (see [code-of-code.md](code-of-code.md), `SAFE-09`).

## 2. Locations

```
<app container>/
  Library/
    Application Support/Pointer/
      library.sqlite                   the live database (with -wal and -shm files)
      device.sqlite                    device state (not part of the library, section 10)
    Caches/Pointer/
      previews/<canvas-id>.png         card previews, written when you leave the canvas (D-97, D-111)
  Documents/                           visible in Files as "On My iPad > Pointer"
    Backups/
      Pointer-2026-10-17-220000.sqlite snapshots, newest first
```

Rules:

- `Documents/` holds snapshots only. The app never reads from it, except for a restore that the user starts.
- The live database is in `Library/Application Support/`. Thus the user cannot move or delete it by accident in the Files app. iCloud backup and Finder backup still include it.

The library is one database for all workspaces (decision D-03).

## 3. Schema

### 3.1 Connection setup

The repository opens the database and runs these statements once per connection:

```sql
PRAGMA journal_mode = WAL;        -- readers do not block the writer
PRAGMA synchronous = NORMAL;      -- safe in WAL mode; a power loss can lose the last commit only
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL; -- set before the first table exists
PRAGMA busy_timeout = 2000;
```

`PRAGMA user_version` holds the schema version of the database (see section 6).

### 3.2 Clock values

Each `created`, `modified`, and `erased` column holds a `HybridTimestamp` (see [data-model.md](data-model.md) section 4) as a 28-byte BLOB:

```
wallMillis  8 bytes  UInt64, big-endian
counter     4 bytes  UInt32, big-endian
device     16 bytes  UUID
```

Big-endian order makes the byte order equal to the clock order. Thus `ORDER BY modified` and `WHERE modified > ?` work without decoding.

IDs are 16-byte BLOBs with the bytes of the UUID.

### 3.3 Tables

```sql
CREATE TABLE library (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;
-- rows: formatVersion  schema version at creation, decimal text, for example "1"
--       created        clock value of the creation, 56 lowercase hex digits
--       createdBy      device ID, lowercase UUID string
--       lastTimestamp  largest clock value of the library, 56 lowercase hex digits (D-58)

CREATE TABLE workspace (
    id         BLOB PRIMARY KEY,
    title      TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
    sort_key   TEXT NOT NULL,
    created    BLOB NOT NULL,
    modified   BLOB NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
) STRICT;

CREATE TABLE card (
    id         BLOB PRIMARY KEY,
    canvas_id  BLOB NOT NULL,          -- parent canvas: a workspace ID or a card ID
    x REAL NOT NULL, y REAL NOT NULL,
    width  REAL NOT NULL CHECK (width  >= 64),
    height REAL NOT NULL CHECK (height >= 48),
    title      TEXT CHECK (title IS NULL OR length(title) <= 120),
    sort_key   TEXT NOT NULL,
    created    BLOB NOT NULL,
    modified   BLOB NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
) STRICT;
CREATE INDEX card_canvas ON card (canvas_id);

CREATE TABLE text_box (
    id         BLOB PRIMARY KEY,
    canvas_id  BLOB NOT NULL,
    x REAL NOT NULL, y REAL NOT NULL,
    text       TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 10000),
    sort_key   TEXT NOT NULL,
    created    BLOB NOT NULL,
    modified   BLOB NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
) STRICT;
CREATE INDEX text_box_canvas ON text_box (canvas_id);

CREATE TABLE stroke (
    id          BLOB PRIMARY KEY,
    canvas_id   BLOB NOT NULL,
    created     BLOB NOT NULL,
    origin_x    REAL NOT NULL,
    origin_y    REAL NOT NULL,
    width       REAL NOT NULL,
    min_x REAL NOT NULL, min_y REAL NOT NULL,   -- bounds, including width
    max_x REAL NOT NULL, max_y REAL NOT NULL,
    point_count INTEGER NOT NULL CHECK (point_count BETWEEN 2 AND 16384),
    points      BLOB NOT NULL,                  -- see 3.4
    CHECK (length(points) = point_count * 16)
) STRICT;
CREATE INDEX stroke_canvas ON stroke (canvas_id);

CREATE TABLE stroke_erase (
    stroke_id  BLOB PRIMARY KEY REFERENCES stroke (id),
    erased     BLOB NOT NULL,
    modified   BLOB NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
) STRICT;
```

Rules:

- `STRICT` tables refuse values of the wrong type.
- `CHECK` constraints repeat the limits from `Limits`. The Swift code checks first. The database is the last line of defense.
- A canvas is not a table. A canvas is all rows with the same `canvas_id` (see [data-model.md](data-model.md) section 2).
- `canvas_id` has no foreign key, because it points to a workspace or to a card.
- Strokes never change. An erase adds a row to `stroke_erase`, and a partial erase also adds new stroke rows.
- An undo of an erase sets `is_deleted = 1` on the erase record and sets `modified`. It never deletes the row, so a later change upload sees the undo (D-30).
- The `library` row `lastTimestamp` holds the largest clock value that the library contains, as 56 lowercase hex digits of the 28-byte form of section 3.2. Each save writes it in the same transaction as its rows. At launch, the clock continues after its wall time and counter (review A-18).

### 3.4 Point BLOB

The `points` column holds `point_count` points of 16 bytes each, little-endian, without a header:

```
x      Float32   offset from origin, canvas points
y      Float32
force  Float32   0...1, or -1 if the pencil has no pressure
time   Float32   seconds since the first point
```

A stroke of 300 points takes 4.8 KB. The layout matches `InkPoint` in memory. Thus the decoder copies the bytes in one step after the length check.

## 4. Write path

`SQLiteLibraryRepository` is an actor. It owns the one connection that writes rows. It is the only code that runs SQL, together with its checkpointer.

1. A command changes `CanvasContent` on the main actor.
2. The canvas controller sends a value copy of the changed rows to the repository.
3. The repository adds the rows to its pending set.
4. The repository throttles the writes (D-27). If the pending set is not empty and the last write is older than 1 second, it writes all pending rows in one transaction (`BEGIN IMMEDIATE` ... `COMMIT`). It uses prepared statements and `INSERT ... ON CONFLICT (id) DO UPDATE`.
5. At pencil lift, the canvas asks the repository to save. If the last write is older than 1 second, the repository writes at once. Otherwise, the throttle of step 4 writes at the end of the second.
6. When the scene goes to the background, the repository writes all pending rows at once. It asks for extra time with `UIApplication.beginBackgroundTask` for this step.

A write never waits for a pause in the input. Thus the data loss after a crash is at most 1 second plus the time of one write, also while you draw without a pause (STO-06, review A-02).

The write connection runs no automatic checkpoint, because the commit that passes 1,000 pages of WAL would run the checkpoint and wait for its sync (D-146, <https://sqlite.org/wal.html>). A WAL hook counts the pages of the WAL after each commit:

- At 1,000 pages or more, the repository asks an idle `WALCheckpointer` for a passive checkpoint, also past 8,000 pages. The checkpointer owns a second connection on its own serial queue, so the save does not wait.
- The checkpointer falls behind if the WAL grows by 1,000 pages or more while one of its checkpoints runs. Then, at 8,000 pages or more, the write connection waits for the checkpointer and runs a passive checkpoint itself, for at most 2 s. This bounds the WAL, for example when saves come back to back under a heavy disk load. That save waits for the sync (D-147).
- The next commit after a checkpoint that copied all pages starts the WAL again from the beginning.

If a transaction fails, the repository rolls it back and keeps the rows in the pending set. It logs the error and tries again at the end of the throttle interval of 1 second. This holds also for the write at the move to the background (F-09 of [m4-fix-plan.md](m4-fix-plan.md)). After three failures in a row, the app shows a message and stops new edits until the next save works. It never drops changes in silence.

## 5. Read path

1. At launch, open the database. If it does not exist, create it with the current schema.
2. Read `PRAGMA user_version`. If it is newer than the app knows, open the library read-only and show a message.
3. If it is older, run the migrations (section 6).
4. Read all workspaces for the selector.
5. To open a canvas, first write the pending rows, so that the load holds them. If that write fails, the open fails with `storageFailed` and loads nothing (F-01 of [m4-fix-plan.md](m4-fix-plan.md)). Then read the live rows with its `canvas_id`: cards and text boxes with `is_deleted = 0`, and strokes without a live erase record (`LEFT JOIN stroke_erase ... ON ... AND stroke_erase.is_deleted = 0 WHERE stroke_erase.stroke_id IS NULL`). Do not load erase records or erased strokes (review A-07). The renderer builds the `SpatialGrid` of the strokes in memory.
6. For the previews of visible cards, `PreviewStore` reads the files in `Caches/Pointer/previews/` off the main actor (D-97, D-107). Read a child canvas only if its file is missing. Reading all children at each open cost about 72 MB for 300 typical children on the iPad.

The repository loads one canvas at a time. It never loads the whole library into memory.

At launch, the repository removes the tombstones that are older than 30 days (D-18). This covers deleted cards with their subtrees and erased strokes with their erase records (review A-07). Then it runs `PRAGMA incremental_vacuum`, which gives the free pages back to the file system (review A-21, item 6).

The load reads at most `Limits.maxStrokesAfterErase` (210,000) strokes, because an erase can pass the stroke limit (D-73). A canvas at the stroke limit (200,000 strokes of 300 points) holds about 1 GB of points. That is too much for one load. If tests on the device show a slow open for large canvases, the next step is a load by viewport: an R-tree index on the stroke bounds, and a query for the strokes near the camera only. Version 1 loads the whole canvas (decision D-24).

## 6. Schema changes

1. `PRAGMA user_version` is the schema version. Version 1 is the first release.
2. Each change is one migration: a numbered list of SQL statements plus optional Swift code for data changes.
3. Before the first migration step, the repository writes a snapshot to `Backups/Pointer-pre-migration-v<old>.sqlite`.
4. All steps of one migration run in one transaction, with the new `user_version` set at the end. If a step fails, the transaction rolls back and the old database stays as it was.
5. Each version has a fixture database in the test bundle. A test opens each fixture, runs the migrations, and compares the result with the expected rows.

## 7. Backup

### 7.1 Snapshots

A snapshot is a complete, consistent copy of the library in one file. `SnapshotWriter`, an actor with its own read-only connection and its own serial executor, makes it (D-32):

1. Run `VACUUM INTO` into a new file in `tmp/`:

   ```sql
   VACUUM INTO '<tmp>/Pointer-<yyyy-MM-dd-HHmmss>.sqlite.partial';
   ```

2. If the command succeeds, rename the file into `Documents/Backups/Pointer-<yyyy-MM-dd-HHmmss>.sqlite`. A rename in one volume is atomic, so `Backups/` never holds a partial file.
3. If the command or the rename fails, the writer deletes the partial file at once (D-155). On a full disk, `VACUUM INTO` leaves a file of 0 bytes, and a second run with that name fails with "output file already exists".
4. If the app stops during a snapshot, the partial file stays in `tmp/`. At launch, before it opens the database and before the pre-migration snapshot, the repository deletes each `*.sqlite.partial` file in `tmp/` (F-08 of [m4-fix-plan.md](m4-fix-plan.md)).

The name uses the local time of the iPad, because the user reads it in the Files app. If `Backups/` holds a snapshot of the same kind with the same second, a counter joins the name: `Pointer-<yyyy-MM-dd-HHmmss>-2.sqlite`, then `-3`, up to `-99` (D-155). The new name takes the counter after the highest one of that second, so it is always the newest. The change date of the file is the time of the snapshot. The writer uses it for the age and the order of the snapshots, and the counter orders the snapshots of one second. A pre-migration snapshot of a version that exists already stays as it is, because it holds the state before the first try of the migration.

The snapshot before a restore has its own name, `Pointer-pre-restore-<yyyy-MM-dd-HHmmss>.sqlite` (D-154). After the new one exists, the writer deletes the older pre-restore snapshots, so only the newest one stays. The daily rotation of section 7.2 does not count it.

`VACUUM INTO` reads one consistent view of the database and writes a compact copy. The copy has no `-wal` file and no free pages. In WAL mode, the read does not block the writer, so saves continue while the snapshot runs. If the target file exists, the command fails, so the name has seconds. The live database uses `synchronous = NORMAL`, so SQLite syncs the output file (review A-12).

### 7.2 Automatic snapshots (STO-02)

If the newest snapshot is older than 24 hours, the app makes a snapshot at the first idle moment while it is active (D-32). An idle moment is 5 seconds without input and with an empty pending set. The 5 seconds are a start value. Tune them on a device in M3. The app does not start a snapshot at the move to the background. The app keeps the newest 7 daily snapshots and deletes older ones. The pre-migration snapshots do not count, and the app never deletes them. These values come from decision D-21.

The `Info.plist` sets `UIFileSharingEnabled = YES` and `LSSupportsOpeningDocumentsInPlace = YES`. Thus the Files app shows `Documents/Backups/` under "On My iPad > Pointer". The Files app shows the "Pointer" folder only after `Documents/` holds a file. An empty `Documents/` gives no folder. The product owner saw this on the iPad Pro 11-inch (M4) on 2026-10-18. Thus the folder shows after the first snapshot.

### 7.3 Manual copy (STO-03)

To back up, the user copies the newest snapshot file from the Files app to any provider: iCloud Drive, Dropbox, Google Drive, OneDrive, or a server through SMB.

### 7.4 "Back up now" (STO-04)

1. The repository writes all pending rows.
2. The snapshot writer makes a new daily snapshot with `writeSnapshotNow()` (D-155). It counts in the 7 daily snapshots of section 7.2. It is the newest, so the rotation keeps it.
3. The app opens the share sheet with the snapshot file, in a popover at the workspace selector (D-160). The user picks a destination.
4. Until the share sheet closes, no idle snapshot starts, so the rotation cannot delete the shared file.

Before step 1, and before a restore, the app ends a running text edit, places a pending card, and waits until the canvas sent all its rows (D-149). If the save fails, nothing else runs, and the app shows a message.

### 7.5 Restore

1. The user picks a snapshot file with the document picker, which opens the file in place (`asCopy: false`). The picker shows only files of the type `dk.saarikivi.pointer.snapshot` that `Info.plist` declares for the extension `.sqlite` (D-156).
2. `SnapshotImport` in `Persistence` calls `startAccessingSecurityScopedResource()` on the URL. It copies the file with a coordinated read of `NSFileCoordinator` into `tmp/<uuid>.sqlite.partial`, and calls `stopAccessingSecurityScopedResource()`. The coordinated read downloads a file of a provider first. The launch deletes a copy that stays.
3. `SnapshotImport` checks the copy, in this order (D-162). A copy that fails a check goes at once, and the error names the reason:
   - The 100 header bytes, in Swift: the SQLite magic text, page size 4096, rollback mode (bytes 18 and 19 are 1, not 2 of WAL mode), a `user_version` from 1 to the current version, and a file size of whole pages. A newer version gives its own error (D-153).
   - An open with the mode `untrustedReadOnly`: `SQLITE_OPEN_READONLY` with `immutable=1`, `trusted_schema` off, `query_only` on, `cell_size_check` on, and `mmap_size` 0. The settings of `sqlite3_db_config` are open question D-166.
   - A full `PRAGMA integrity_check`, which must give the single row `ok`.
   - A compare of all rows of `sqlite_schema` (tables, columns, indexes, views, and triggers, with their SQL) with the schema that the migrations up to that version make in a database in memory. No `application_id` (D-163).
4. The app writes the pre-restore snapshot of section 7.1 (D-154).
5. `SQLiteLibraryRepository.restore(from:stop:)` needs an empty pending set. It waits for the running checkpoint and drops all statements, so that no read is open, because `sqlite3_backup_init` refuses a destination with an open read. Then it copies the checked file into the live database with the SQLite online backup API, in steps of 1,024 pages (`sqlite3_backup_init`, `sqlite3_backup_step`, `sqlite3_backup_finish`). A step that meets a lock tries again, at most 200 times, 10 ms apart.
6. Between two steps, the restore reads a stop flag. At the end of the extra time in the background, the app sets it, and `sqlite3_backup_finish` rolls the copy back, so the library keeps its old content (D-164).
7. The backup does not call the WAL hook, so after the copy the WAL holds the whole library. A `TRUNCATE` checkpoint copies it and cuts the `-wal` file to 0 bytes. Then the repository closes.
8. The app builds a new composition, as at launch (D-148). Its repository opens the library and runs the migrations of section 6, because the snapshot can have an older `user_version`. The app clears the preview cache (D-97, D-157) and reloads all workspaces.

The live database and each snapshot use a page size of 4,096 bytes. The repository sets `PRAGMA page_size = 4096` before the first table exists. If the page sizes of the source and the WAL destination differ, `sqlite3_backup_step` returns `SQLITE_READONLY` (review A-21, item 7). Thus the header check refuses a picked file with another page size.

Restore is part of version 1 (decision D-20).

### 7.6 Device backup

iCloud backup and Finder backup include `Library/Application Support/` and `Documents/`. They exclude `Library/Caches/`. This protects against the loss of the iPad, but it restores the whole device only.

## 8. Future: automatic backup to a provider

This version contains no integration. The design keeps these paths open:

1. A protocol `BackupDestination` in `BackupFeature` with one method: `upload(file: URL, name: String) async throws`. An iCloud Drive container, S3, or WebDAV destination can implement it later.
2. Full upload: upload each snapshot. This is simple, but a library of 100 MB uploads 100 MB each time.
3. Change upload: each row has a `modified` clock value (strokes have `created`, erases have `erased`). A later version can export all rows that changed after the last upload into a small change file, and upload that file. A restore then applies the last snapshot and the change files in order. The clock values and tombstones make this possible without a schema change.
4. Encryption: a destination can encrypt each file with CryptoKit `AES.GCM` before upload. The key lives in the Keychain.

## 9. Tests for storage

- Round-trip tests for every row type and the point BLOB: write, read, compare.
- Migration tests with one fixture database per schema version.
- Constraint tests: each `CHECK` refuses a value one past its limit.
- Corruption tests: a point BLOB with a wrong length, a damaged database file. The repository must report the fault, keep the rest of the library readable, and never overwrite the file.
- Message test: a fault message shows also while a popover, for example the palette, is open (F-12 of [m4-fix-plan.md](m4-fix-plan.md)).
- Crash tests: stop the process between `BEGIN` and `COMMIT` with an injected failure. Then open the database, and make sure that it holds the state before the transaction.
- Throttle test (M3 acceptance 1): add strokes without a pause for 10 seconds, stop the process, open the database again, and make sure that at most 2 seconds of strokes are missing (review A-02).
- Partial snapshot test: stop a snapshot before the rename. Make sure that `Backups/` holds no new file and that the next launch deletes the partial file.
- Snapshot test: make a library, run `VACUUM INTO`, open the snapshot, and compare all rows with the live database.
- Restore test: restore a snapshot over a different library, and compare all rows with the snapshot.
- Performance test on the device: open a canvas with 10,000 nodes and 20,000 strokes in under 300 ms.

## 10. Device state

The device state of [data-model.md](data-model.md) section 10 lives in its own SQLite file, `device.sqlite` (D-53). It is not part of the library, so a snapshot and a restore never carry it to another iPad. `DeviceStateStore`, an actor with its own connection and its own serial executor, owns the file. It uses the wrapper and the connection setup of section 3.1.

```sql
CREATE TABLE device (
    key   TEXT PRIMARY KEY,
    value BLOB NOT NULL
) STRICT;
-- rows: deviceID (16 bytes), lastWorkspace (16 bytes),
--       navigationPath (16 bytes per card ID, at most Limits.maxDepth IDs)

CREATE TABLE camera (
    canvas_id BLOB PRIMARY KEY,
    center_x  REAL NOT NULL,
    center_y  REAL NOT NULL,
    zoom      REAL NOT NULL CHECK (zoom BETWEEN 0.25 AND 8.0),
    used      INTEGER NOT NULL      -- grows by 1 with each camera write
) STRICT;
CREATE INDEX camera_used ON camera (used);
```

Rules:

- At launch, the store reads the `device` rows and the camera of the deepest canvas of the stored path only. A canvas reads its camera at a workspace switch. An open of a card, the up button, and a pinch-out use the cameras of architecture.md section 6 instead (D-99).
- The store writes at three events: the camera comes to rest, the workspace changes, and the app moves to the background. A camera write changes one row.
- `used` is a counter, not a clock value, so a change of the system time does not change the order.
- After a camera write, the store keeps the 1,000 rows with the largest `used` and deletes the others in the same transaction.
- `PRAGMA user_version` holds the schema version of this file. It has its own migrations, as in section 6.
- If the file is missing or damaged, the store renames a damaged file to `device.sqlite.damaged`, makes a new file with a new `DeviceID`, and logs the fault. The app does not stop. The camera positions are lost, but no work is lost (STO-06).
- At launch, the app cuts the stored path before the first card that is not valid (D-112). A valid card is live, and its `canvasID` is the canvas above it.
- A file with a newer schema, a row of a wrong length, or a navigation path above `Limits.maxDepth` counts as damaged. A camera row with a zoom outside the range or a center that is not finite reads as no camera.
