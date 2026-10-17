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
      device.json                      device state (not part of the library)
    Caches/Pointer/
      previews/<canvas-id>.png         card previews, rebuilt on demand
  Documents/                           visible in Files as "On My iPad > Pointer"
    Backups/
      Pointer-2026-10-17-2200.sqlite   snapshots, newest first
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
-- rows: formatVersion, created, createdBy

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
    text       TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 100000),
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
    stroke_id BLOB PRIMARY KEY REFERENCES stroke (id),
    erased    BLOB NOT NULL
) STRICT;
```

Rules:

- `STRICT` tables refuse values of the wrong type.
- `CHECK` constraints repeat the limits from `Limits`. The Swift code checks first. The database is the last line of defense.
- A canvas is not a table. A canvas is all rows with the same `canvas_id` (see [data-model.md](data-model.md) section 2).
- `canvas_id` has no foreign key, because it points to a workspace or to a card.
- Strokes never change. An erase adds a row to `stroke_erase`, and a partial erase also adds new stroke rows.

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

`SQLiteLibraryRepository` is an actor. It owns the one connection that writes. It is the only code that runs SQL.

1. A command changes `CanvasContent` on the main actor.
2. The canvas controller sends a value copy of the changed rows to the repository.
3. The repository adds the rows to its pending set.
4. One second after the last change, the repository writes all pending rows in one transaction (`BEGIN IMMEDIATE` ... `COMMIT`). It uses prepared statements and `INSERT ... ON CONFLICT (id) DO UPDATE`.
5. When the scene goes to the background, the repository writes all pending rows at once. It asks for extra time with `UIApplication.beginBackgroundTask` for this step.

The data loss after a crash is at most the one-second wait plus the time of one write (STO-06).

If a transaction fails, the repository rolls it back and keeps the rows in the pending set. It logs the error and tries again at the next save. After three failures in a row, the app shows a message and stops new edits until the next save works. It never drops changes in silence.

## 5. Read path

1. At launch, open the database. If it does not exist, create it with the current schema.
2. Read `PRAGMA user_version`. If it is newer than the app knows, open the library read-only and show a message.
3. If it is older, run the migrations (section 6).
4. Read all workspaces for the selector.
5. To open a canvas, read all rows with its `canvas_id` from `card`, `text_box`, `stroke`, and `stroke_erase`. Build the `SpatialGrid` in memory.
6. For the previews of visible cards, read their canvases one level deep.

The repository loads one canvas at a time. It never loads the whole library into memory.

A canvas at the stroke limit (200,000 strokes of 300 points) holds about 1 GB of points. That is too much for one load. If tests on the device show a slow open for large canvases, the next step is a load by viewport: an R-tree index on the stroke bounds, and a query for the strokes near the camera only. Version 1 loads the whole canvas (decision D-24).

## 6. Schema changes

1. `PRAGMA user_version` is the schema version. Version 1 is the first release.
2. Each change is one migration: a numbered list of SQL statements plus optional Swift code for data changes.
3. Before the first migration step, the repository writes a snapshot to `Backups/Pointer-pre-migration-v<old>.sqlite`.
4. All steps of one migration run in one transaction, with the new `user_version` set at the end. If a step fails, the transaction rolls back and the old database stays as it was.
5. Each version has a fixture database in the test bundle. A test opens each fixture, runs the migrations, and compares the result with the expected rows.

## 7. Backup

### 7.1 Snapshots

A snapshot is a complete, consistent copy of the library in one file. The repository makes it with:

```sql
VACUUM INTO '<path>/Pointer-<yyyy-MM-dd-HHmm>.sqlite';
```

`VACUUM INTO` reads one consistent view of the database and writes a compact copy. The copy has no `-wal` file and no free pages. Writes wait while it runs.

### 7.2 Automatic snapshots (STO-02)

When the scene goes to the background, the repository makes a snapshot if the newest snapshot is older than 24 hours. It keeps the newest 7 snapshots and deletes older ones. These values come from decision D-21.

The `Info.plist` sets `UIFileSharingEnabled = YES` and `LSSupportsOpeningDocumentsInPlace = YES`. Thus the Files app shows `Documents/Backups/` under "On My iPad > Pointer".

### 7.3 Manual copy (STO-03)

To back up, the user copies the newest snapshot file from the Files app to any provider: iCloud Drive, Dropbox, Google Drive, OneDrive, or a server through SMB.

### 7.4 "Back up now" (STO-04)

1. The repository writes all pending rows.
2. The repository makes a new snapshot.
3. The app opens the share sheet with the snapshot file. The user picks a destination.

### 7.5 Restore

1. The user picks a snapshot file with the document picker.
2. The app opens it read-only and runs `PRAGMA integrity_check` and `PRAGMA user_version`.
3. If the file passes, the app makes a snapshot of the current library first. Then it copies the picked file into the live database with the SQLite online backup API (`sqlite3_backup_init`, `sqlite3_backup_step`, `sqlite3_backup_finish`).
4. The app reloads all workspaces.

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
- Crash tests: stop the process between `BEGIN` and `COMMIT` with an injected failure. Then open the database, and make sure that it holds the state before the transaction.
- Snapshot test: make a library, run `VACUUM INTO`, open the snapshot, and compare all rows with the live database.
- Restore test: restore a snapshot over a different library, and compare all rows with the snapshot.
- Performance test on the device: open a canvas with 10,000 nodes and 20,000 strokes in under 300 ms.
