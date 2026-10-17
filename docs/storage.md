# Storage and backup

This document describes where Pointer stores data, how it writes data safely, and how you back up the library. The data types are in [data-model.md](data-model.md).

## 1. Strategy

Pointer stores the library as plain files in a folder tree. The folder is the data. It is not an export of a database.

- Each card, text box, and workspace is one small JSON file.
- Ink is in binary chunk files. The app adds chunk files but never edits them.
- Each write replaces a whole file atomically (write to a temporary file, then rename).
- The library folder shows in the Files app. You back it up with a copy of the folder.

Reasons:

1. A copy of the folder is a valid backup at any time, because each file is complete on its own.
2. A small edit changes a small file. A future incremental backup uploads only the changed files.
3. A conflict covers one object, not the whole library.
4. No third-party code is necessary. Foundation and CryptoKit do all the work.

SwiftData, Core Data, and SQLite were rejected. See [research.md](research.md) section 5.

## 2. Folder layout

```
<app container>/
  Documents/                                   visible in Files as "On My iPad > Pointer"
    PointerLibrary/                            the library: the unit of backup
      library.json
      workspaces/
        <workspace-id>/
          workspace.json
          canvases/
            <canvas-id>/                       one folder per canvas, flat (never nested)
              nodes/
                <node-id>.json                 one card or one text box
              ink/
                index.json                     list of chunks and erase records
                <chunk-id>.ink                 binary strokes, write-once
  Library/
    Application Support/Pointer/
      device.json                              device state (not part of the backup)
    Caches/Pointer/
      previews/<canvas-id>.png                 card previews, rebuilt on demand
```

Rules:

- All names are lowercase UUID strings plus an extension. Thus names are safe in every file system and in zip files.
- Canvas folders are flat under `canvases/`. The folder tree never follows the card tree. Thus the path length stays fixed at any tree depth.
- A card record lives in the folder of its parent canvas. Its child content lives in the folder with the card ID.
- Nothing in `Documents/` can be rebuilt from other data. Caches go to `Library/Caches/`.

Decision D-03 asks whether each workspace is a plain folder or a document package (a folder that the Files app shows as one file).

## 3. File formats

### 3.1 `library.json`

```json
{
  "formatVersion": 1,
  "createdBy": "Pointer 1.0 (100)",
  "created": { "wallMillis": 1792224000000, "counter": 0, "device": "4f1c..." }
}
```

Only a change of the folder layout changes `formatVersion`.

### 3.2 Record files

`workspace.json` and each file in `nodes/` hold one record as JSON, encoded with `JSONEncoder` and `outputFormatting = [.sortedKeys, .prettyPrinted]`. Sorted keys give stable files, so a diff shows only real changes. A `"type"` field (`"card"` or `"textBox"`) tells the decoder which type to use.

```json
{
  "type": "textBox",
  "id": "9b2e...",
  "canvasID": "4a77...",
  "meta": { "schema": 1, "created": { ... }, "modified": { ... }, "isDeleted": false },
  "origin": { "x": 1204.5, "y": -310.0 },
  "sortKey": "a0V",
  "text": "struct Node {\n  let next: Node?\n}"
}
```

### 3.3 Ink index

`ink/index.json` lists the chunks of the canvas in order, and the erase records.

```json
{
  "schema": 1,
  "chunks": [
    { "id": "c01d...", "strokeCount": 412, "sha256": "e3b0..." }
  ],
  "erased": [
    { "strokeID": "77aa...", "erased": { ... } }
  ]
}
```

A chunk file that is not in the index is an orphan. At load time, the repository deletes orphans that are older than 60 seconds.

### 3.4 Ink chunk (`.ink`)

All numbers are little-endian. The format has no padding.

```
Header (32 bytes)
  magic          4 bytes   "PINK"
  version        UInt16    1
  flags          UInt16    0 (reserved)
  strokeCount    UInt32
  reserved       20 bytes  zero

Stroke (repeated strokeCount times)
  id             16 bytes  UUID
  created        28 bytes  wallMillis UInt64, counter UInt32, device UUID (16 bytes)
  originX        Float64
  originY        Float64
  width          Float32
  pointCount     UInt32    2...Limits.maxPointsPerStroke
  points         pointCount * 16 bytes: x Float32, y Float32, force Float32, time Float32

Footer
  sha256         32 bytes  SHA-256 of all bytes before the footer
```

A stroke of 300 points takes about 4.9 KB. Delta encoding and compression (Apple `Compression` framework, LZFSE) can make chunks about 3 to 5 times smaller. They are not part of version 1. A new chunk version can add them.

The decoder must reject a chunk with one of these faults: a wrong magic, an unknown version, or a count over a limit. It must also reject a size that does not match the counts, and a wrong hash. A rejected chunk does not stop the load. The canvas opens without those strokes, the app shows a message, and the file stays on disk unchanged.

## 4. Write path

`FileLibraryRepository` is an actor. It is the only code that touches the library folder.

### 4.1 Records

1. A command changes `CanvasContent` on the main actor.
2. The canvas controller sends the IDs of the changed records and a value copy of them to the repository.
3. The repository marks the records as dirty.
4. One second after the last change, the repository writes each dirty record with `Data.write(to:options: [.atomic])`. All writes go through `NSFileCoordinator.coordinate(writingItemAt:options:)`.
5. When the scene goes to the background, the repository writes all dirty records at once. It asks for extra time with `UIApplication.beginBackgroundTask` for this step.

### 4.2 Ink

1. At the end of each stroke, the repository adds the stroke to the pending chunk of the canvas.
2. One second after the last stroke, the repository writes the pending strokes as a new chunk file.
3. After the chunk file is on disk, the repository writes the new `index.json`.
4. Erase records go into the next `index.json` write.

Order matters: the chunk first, the index last. If the app stops between the two writes, the index does not list the new chunk. The chunk becomes an orphan, and the data loss is at most one second (STO-06).

### 4.3 Compaction

Many small chunks slow down the load. At the close of a canvas, the repository compacts its ink if one of these conditions is true:

- The canvas has more than 64 chunks.
- More than 25% of its strokes are erased.

Compaction writes one new chunk with all strokes that are not erased. Then it writes a new index that lists only that chunk. The index keeps all erase records, because a future merge needs them. Then the repository deletes the old chunk files.

## 5. Read path

1. At launch, read `library.json`. If its `formatVersion` is newer than the app knows, open the library read-only and show a message.
2. Read every `workspace.json` for the workspace selector.
3. To open a canvas, read its `nodes/` folder and its `ink/` folder. Read the canvases of visible cards one level deep for their previews.
4. Read each record and run the migrations (see [data-model.md](data-model.md) section 12).

The repository loads the content of a canvas at the time of first use. It never loads the whole library into memory.

## 6. External changes

The app owns the library folder while it runs. The Files app can still change files in it. The rules:

- At each launch and each return to the foreground, the repository reads the modification dates of the `canvases/` folders. It reloads a canvas whose files changed.
- The app does not watch the folder (`NSFilePresenter`) in version 1. Decision D-21 covers this.
- The app never deletes a file that it cannot decode. It skips the file and shows a message.

## 7. Backup

### 7.1 Manual copy (STO-03)

The `Info.plist` sets `UIFileSharingEnabled = YES` and `LSSupportsOpeningDocumentsInPlace = YES`. Thus the Files app shows `Documents/` as "On My iPad > Pointer". To back up, the user copies the `PointerLibrary` folder to any provider in the Files app: iCloud Drive, Dropbox, Google Drive, OneDrive, or a server through SMB.

### 7.2 "Back up now" (STO-04)

1. The repository writes all dirty records.
2. `BackupService` calls `NSFileCoordinator().coordinate(readingItemAt: libraryURL, options: .forUploading)`. The system makes a zip of the folder.
3. Inside the block, the service copies the zip to a temporary file with the name `Pointer-Backup-<yyyy-MM-dd-HHmm>.zip`. The system deletes its own zip after the block.
4. The app opens the share sheet with that file. The user picks a destination.

The coordinated read waits for coordinated writes. Thus the zip never holds a half-written file.

### 7.3 Scheduled backup through Shortcuts

`BackupFeature` provides an App Intent named "Back Up Pointer Library". It returns the zip as an `IntentFile`. The user can build a Shortcuts automation, for example "every day at 22:00, run Back Up Pointer Library, then save the file to Dropbox". This is not an integration with a provider. The user picks the provider in Shortcuts.

The library files use the data protection class `completeUntilFirstUserAuthentication` (the system default). Thus the intent can read them after the first unlock since the last restart. Whether the automation runs while the iPad is locked must be tested on a device (decision D-14).

### 7.4 Device backup

iCloud backup and Finder backup include `Documents/` and `Library/Application Support/`. They exclude `Library/Caches/`. This protects against the loss of the iPad, but it restores the whole device only.

### 7.5 Restore

To restore, the user replaces the `PointerLibrary` folder in the Files app with the copy from the backup, while Pointer is closed. An in-app restore is decision D-20.

## 8. Future: automatic backup to a provider

This version contains no integration. The design keeps these paths open:

1. A protocol `BackupDestination` in `BackupFeature` with one method: `upload(file: URL, relativePath: String) async throws`. An iCloud Drive container, S3, or WebDAV destination can implement it later.
2. Incremental upload: the service computes SHA-256 per file with CryptoKit and compares the hashes with the last upload. Only changed files go up. Write-once chunks never change, so they upload once.
3. Encryption: a destination can encrypt each file with CryptoKit `AES.GCM` before upload. The key lives in the Keychain.
4. iCloud Drive: the same folder layout works in a ubiquity container. Then all access must go through `NSFileCoordinator`, which the repository already does.

## 9. Tests for storage

- Round-trip tests for every record type and the chunk format: encode, decode, compare.
- Fixture tests: one file per schema version in the test bundle, loaded and migrated.
- Corruption tests: a truncated chunk, a wrong hash, a wrong magic, an over-limit count. The loader must reject each one and keep the rest of the canvas.
- Crash tests: stop the write sequence after each step with an injected failure. Then load, and make sure that no stroke older than the debounce interval is lost.
- Backup test: make a library, run the zip step, unzip it with `/usr/bin/ditto` in a macOS test, and compare the trees.
