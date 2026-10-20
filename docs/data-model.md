# Data model

This document defines the data types of Pointer and the rules that they obey. The database schema for these types is in [storage.md](storage.md).

All types in this document live in the `Model` package. They are value types (`struct` or `enum`), except `InkPoints` (section 7.4). They are `Sendable` and immutable (ARCH-06). The storage uses its own row codecs, not `Codable`. They import Foundation and `Geometry` only.

## 1. Goals

1. The model holds only what the product needs (see [product-spec.md](product-spec.md)).
2. Each object has a stable identity that never changes. Thus a later sync or backup can compare objects across devices.
3. A change to one object changes one record. A move changes only the moved object.
4. A delete leaves a tombstone (a record that marks the object as deleted). Thus a merge or a restore does not bring deleted objects back.
5. The database carries a schema version. Each record carries a clock value that orders changes across devices.

## 2. Overview

```
Library
 └── Workspace (title, sortKey)
      └── root Canvas  (id == workspace.id)
           ├── Stroke ...            (immutable, ink)
           ├── TextBox ...           (text, position)
           └── Card                  (frame, title)
                └── Canvas  (id == card.id)
                     ├── Stroke ...
                     ├── TextBox ...
                     └── Card ...     (up to Limits.maxDepth levels)
```

A canvas is not a stored record. A canvas is the set of all strokes, text boxes, and cards with the same `canvasID`. The canvas of a workspace has the ID of the workspace. The canvas of a card has the ID of the card. Thus a canvas has no data of its own that two devices can change at the same time.

## 3. Identity

```swift
/// A stable, globally unique ID. Never reused, never changed.
struct EntityID: Hashable, Comparable, Codable, Sendable {
    let rawValue: UUID
}

typealias WorkspaceID = EntityID
typealias CanvasID = EntityID   // equal to a WorkspaceID or a CardID
typealias CardID = EntityID
typealias TextBoxID = EntityID
typealias StrokeID = EntityID
typealias DeviceID = EntityID
```

Rules:

- The app makes new IDs as UUID version 7 (decision D-31). A version 7 UUID starts with the wall-clock time in milliseconds, so new keys land at the end of the database index. Foundation has no version 7 function, so `Model` makes the UUID from an injected clock and random bytes (RFC 9562, section 5.7).
- An ID is never an array index, a row number (`rowid`), or a title.
- The database stores an ID as a 16-byte BLOB. File names (for previews) use the lowercase string form.

Each entity has its own wrapper ID type, not a type alias (decision D-17). The compiler then refuses a `StrokeID` where a `CardID` is needed. The code above shows aliases for brevity only.

## 4. Clock

Pointer uses a hybrid logical clock (HLC). An HLC value combines the wall-clock time, a counter, and the device ID. On one device, each new HLC value is greater than the last one. A change of the system time does not break this rule. Values from different devices sort in an order that is close to real time.

```swift
struct HybridTimestamp: Comparable, Codable, Sendable {
    let wallMillis: UInt64   // milliseconds since 1970, from the device clock
    let counter: UInt32      // breaks ties within one millisecond
    let device: DeviceID     // breaks ties between devices
}
```

`HybridClock` makes new values:

1. Read the current wall time in milliseconds.
2. If the wall time is greater than the last `wallMillis`, use it with `counter = 0`.
3. Otherwise, use the last `wallMillis` with `counter + 1`.
4. Store the last value in the `library` table, in the same transaction as the rows that use it (see [storage.md](storage.md) section 3.3). The clock then never goes back after a restart or a crash (review A-18).

The app has one clock, `AppClock` in `CanvasFeature`. The canvas and the workspace selector share it, so the clock values of one iPad grow across all records. At launch, `PointerApp` makes it from the `lastTimestamp` of the library, with the `DeviceID` of this iPad. After a restore from another iPad, the clock keeps the wall time and the counter of `lastTimestamp` and takes the device ID of this iPad.

Comparison order: `wallMillis`, then `counter`, then `device`.

Source: Kulkarni et al., "Logical Physical Clocks" (<https://www.cse.buffalo.edu/~demirbas/publications/hlc.pdf>).

## 5. Common record fields

Each stored record has these fields:

```swift
struct RecordMeta: Hashable, Sendable {
    let created: HybridTimestamp
    let modified: HybridTimestamp      // set on every change
    let isDeleted: Bool                // tombstone
}
```

Rules:

- Each change sets `modified` to a new clock value.
- A delete sets `isDeleted = true` and sets `modified`. The row stays in the database.
- An undo of a delete sets `isDeleted = false` and sets `modified`.
- Code that reads content ignores records with `isDeleted == true`. The repository is the only place that filters them. It does not load deleted records or erased strokes from the database (review A-07).

## 6. Order

Cards, text boxes, and workspaces have a `sortKey` of type `FractionalIndex`. A fractional index is a string key. To put an item between two others, you make a new key that sorts between their keys. No other item changes.

```swift
struct FractionalIndex: Hashable, Comparable, Sendable {
    let rawValue: String   // base-62 digits, compared as bytes
}
```

- `FractionalIndex.between(_:_:)` returns a key that sorts between two keys. Either argument can be `nil` for "start" or "end".
- If two devices make the same key, the record ID breaks the tie.
- The key length has a limit of 64 characters (`Limits.maxSortKeyLength`). If a new key needs more, `between` throws `ModelError.sortKeyNeedsRebalance`. A longer key triggers a rebalance of all keys on that canvas, in one command.
- A key never ends with the digit "0". Thus a key always fits between two different keys.
- Between two keys, `between` takes the midpoint of David Greenspan ("Implementing Fractional Indexing", 2020). At an end of the list, it adds one to the first digit that can grow, or takes one from the first digit above 1. A list that grows at one end then needs a new digit only every 60 keys.

Workspaces use the key for their order in the selector. Cards and text boxes use it for their drawing order within their layer.

Strokes do not need a key. Ink is opaque white, so the drawing order of strokes does not change the image.

## 7. Entities

Each initializer checks the limits of its type and throws `ModelError` for a value outside them. A length limit of a title or a text counts Unicode code points, the unit of the SQLite `length()` function (D-57). A title or a text must not hold U+0000, because `length()` stops at it.

### 7.1 Workspace

```swift
struct Workspace: Identifiable, Hashable, Sendable {
    let id: WorkspaceID
    let meta: RecordMeta
    let title: String          // 1...120 code points, trimmed
    let sortKey: FractionalIndex
}
```

### 7.2 Card

```swift
struct Card: Identifiable, Hashable, Sendable {
    let id: CardID             // also the ID of its child canvas
    let meta: RecordMeta
    let canvasID: CanvasID     // the parent canvas
    let frame: Rect            // in parent canvas space, Double
    let title: String?         // 0...120 code points
    let sortKey: FractionalIndex
}
```

Rules:

- `frame.size` is at least 64 by 48 canvas points.
- `canvasID` never equals `id`. A move of a card to a different parent must not make a cycle. The `Model` function that moves a card walks the parent chain with a depth limit of `Limits.maxDepth` and refuses a cycle.
- A delete of a card marks only the card. The child content stays on disk for 30 days and comes back with an undo (decision D-18). After 30 days, the repository removes the card and its subtree at launch.

### 7.3 Text box

```swift
struct TextBox: Identifiable, Hashable, Sendable {
    let id: TextBoxID
    let meta: RecordMeta
    let canvasID: CanvasID
    let origin: Point          // top-left corner, canvas space
    let text: String           // plain text, 1...Limits.maxTextLength code points
    let sortKey: FractionalIndex
}
```

The width and the height come from the text layout of `Rendering`: SF Mono at 17 points, word wrap at 640 canvas points (`TextStyle`, D-83, D-84). They are not stored.

The text is one value (decision D-19). One value is simple. A list of paragraphs makes merge conflicts smaller, as Muse found, and can come with a future sync.

### 7.4 Stroke

A stroke never changes after it is created. An eraser does not edit a stroke. It marks the stroke as erased and, for a partial erase, adds new strokes for the remaining parts.

```swift
struct Stroke: Identifiable, Sendable {
    let id: StrokeID
    let canvasID: CanvasID
    let created: HybridTimestamp
    let origin: Point          // Double, canvas space
    let width: Float           // canvas points
    let points: InkPoints      // control points, 2...Limits.maxPointsPerStroke, shared
    let bounds: Rect           // computed at creation, includes width
}

struct InkPoint: Sendable {
    let x: Float               // offset from origin, canvas points
    let y: Float
    let force: Float           // 0...1, or -1 if the pencil has no pressure
    let time: Float            // seconds since the first point
}

/// The points of one stroke. A copy of a `Stroke` copies one reference, never the points.
final class InkPoints: Sendable {
    let values: [InkPoint]
}
```

Rules:

- `origin` is the first point of the stroke. Thus all offsets are small, and `Float` precision is enough.
- `points` are the control points of the uniform cubic B-spline that PencilKit drew (decision D-26, see [architecture.md](architecture.md) section 4.3). They are not points on the curve. The curve does not depend on the zoom at which you drew it.
- `InkPoints` is the one reference type of `Model` (review A-03). It holds only `let` properties, so the compiler checks that it is `Sendable`. A copy of a `Stroke` or of a dictionary of strokes then costs one retain, not a copy of the points.
- A stroke with one sample (a dot) stores the point twice.
- The database stores the points as one binary BLOB per stroke (see [storage.md](storage.md) section 3.4).

### 7.5 Erase record

```swift
struct EraseRecord: Hashable, Sendable {
    let strokeID: StrokeID
    let erased: HybridTimestamp
    let modified: HybridTimestamp
    let isDeleted: Bool        // true after an undo of the erase
}
```

The set of live erase records of a canvas is the tombstone list for its strokes. An undo of an erase sets `isDeleted = true` on its erase records and sets `modified`. It also adds erase records for the new parts. No row is ever deleted, so a later change upload sees the undo (D-30, review A-09).

## 8. Content in memory

```swift
struct CanvasContent: Sendable {
    let canvasID: CanvasID
    var strokes: [StrokeID: Stroke]
    var erased: [StrokeID: EraseRecord]
    var cards: [CardID: Card]
    var textBoxes: [TextBoxID: TextBox]
}
```

`strokes` holds the live strokes only. An erase, or an undo of an added stroke, removes the stroke from `strokes`. The command keeps the `Stroke` value for a later undo or redo (D-68). `erased` holds only the erase records of the current session. A new load of a canvas reads no erase record, so the canvas takes the records of its session back with `adoptSessionRecords(_:)` (D-12). The repository loads live strokes only, so the erased strokes of earlier sessions never reach memory or the point arena (review A-07). An undo can only reach an erase of the current session, because the history lives in memory (D-12).

`CanvasContent` is the input and the output of commands. Only the canvas controller holds it (review A-03). The canvas also holds the `History` of the canvas while it shows. When it leaves, it gives the history and the erase records of its session to `CanvasSessions` in `PointerApp`, and the next open of the canvas takes them out again, so one holder at a time owns them (D-12, M-03). Swift copies a dictionary at the first change after a copy exists. With a second holder, the main actor then copies up to 200,000 entries at a pencil lift.

- The renderer receives deltas: the IDs of the removed strokes, the added `Stroke` values, and the area to redraw. It keeps its own GPU state.
- The repository receives the changed rows as `LibraryChange` values through the protocol `LibraryRepository` (see [storage.md](storage.md) section 4).
- The exporter takes a copy. Export is rare and the user starts it, so the cost of the copy is accepted.

## 9. Commands

```swift
protocol CanvasCommand: Sendable {
    func apply(to content: inout CanvasContent, clock: inout HybridClock) throws(CommandError)
        -> [LibraryChange]
    func revert(on content: inout CanvasContent, clock: inout HybridClock) throws(CommandError)
        -> [LibraryChange]
}
```

Both functions return the changed rows, so the canvas sends them to the repository without a second pass. A command checks the content before it changes it, so a thrown error leaves the content as it was. `AddStroke` holds the strokes of one pen path. `EraseStrokes` holds the removed strokes, the parts, and the area of the eraser path.

Rules:

- Each command makes the smallest change that does the job.
- `revert` after `apply` gives back live content that is equal to the live content before `apply`, except for `modified` clock values. The live content is the strokes, cards, and text boxes that are not erased or deleted. The erase records stay as tombstones and are not part of the comparison (D-67). A unit test for each command makes sure that this rule holds. A second test makes sure that each erase record after a revert is a tombstone.
- Commands never touch disk. The repository saves the changed records after the command (see [storage.md](storage.md)).

## 10. Device state

These values belong to one device. They are not part of the library, and a backup does not need them. They live in `device.sqlite` (see [storage.md](storage.md) section 10, D-53).

```swift
struct DeviceState: Hashable, Sendable {
    let deviceID: DeviceID
    let lastWorkspace: WorkspaceID?
    let navigationPath: [CardID]         // at most Limits.maxDepth
}
```

The last camera of each canvas is not part of `DeviceState`. `DeviceStateStore` reads the camera of one canvas when the canvas opens and writes it as one row. It keeps at most 1,000 cameras and drops the least recently used one. `Camera` is in `Geometry`.

## 11. Readiness for sync and backup

The model is ready for a future sync or an automatic backup. This version does not implement either. The table shows how each future need maps to the model.

| Future need | What the model already provides |
|---|---|
| Incremental backup | A `modified` clock value per row. A query for all rows after the last backup gives the changes (see [storage.md](storage.md) section 8). |
| Merge of two copies | Stable IDs. `modified` HLC per record for "last writer wins". Tombstones. |
| Move without conflict | `canvasID` lives on the child. A move changes one record. |
| Reorder without conflict | `FractionalIndex` keys. |
| Ink merge | Strokes never change. Erases are separate records. Two devices can only add. |
| Mixed app versions | `PRAGMA user_version` per database. An app refuses to write to a database with a newer schema than it knows. |

A conflict-free replicated data type (CRDT) for text is not part of this version. Decision D-19 covers the text model.

## 12. Schema changes

The schema version of the whole database is `PRAGMA user_version`. The rules for a change are in [storage.md](storage.md) section 6. In short:

1. A change to a stored field adds 1 to `user_version`.
2. Each change comes with a migration in `Persistence` that runs in one transaction.
3. Each change adds a fixture database of the old version to the test bundle.
4. If the database has a newer version than the app knows, the app opens the library read-only and shows a message. It never writes to that database.
