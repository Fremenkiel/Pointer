# Data model

This document defines the data types of Pointer and the rules that they obey. The file format of these types is in [storage.md](storage.md).

All types in this document live in the `Model` package. They are value types (`struct` or `enum`), `Sendable`, and `Codable` where the storage needs it. They import Foundation and `Geometry` only.

## 1. Goals

1. The model holds only what the product needs (see [product-spec.md](product-spec.md)).
2. Each object has a stable identity that never changes. Thus a later sync or backup can compare objects across devices.
3. A change to one object changes one record. A move changes only the moved object.
4. A delete leaves a tombstone (a record that marks the object as deleted). Thus a merge or a restore does not bring deleted objects back.
5. Each record carries a schema version. Each record carries a clock value that orders changes across devices.

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

- The app makes new IDs with `UUID()` (version 4, random).
- An ID is never an array index, a file path, or a title.
- File names use the lowercase string form of the ID.

Decision D-17 asks whether to use distinct wrapper types per entity instead of type aliases. Distinct types catch more mistakes at compile time, but they need more code.

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
4. Store the last value in the device state (see [storage.md](storage.md)), so that the clock never goes back after a restart.

Comparison order: `wallMillis`, then `counter`, then `device`.

Source: Kulkarni et al., "Logical Physical Clocks" (<https://www.cse.buffalo.edu/~demirbas/publications/hlc.pdf>).

## 5. Common record fields

Each stored record has these fields:

```swift
struct RecordMeta: Codable, Sendable {
    let schema: Int                    // schema version of this record type
    let created: HybridTimestamp
    var modified: HybridTimestamp      // set on every change
    var isDeleted: Bool                // tombstone
}
```

Rules:

- Each change sets `modified` to a new clock value.
- A delete sets `isDeleted = true` and sets `modified`. The record stays on disk.
- An undo of a delete sets `isDeleted = false` and sets `modified`.
- Code that reads content ignores records with `isDeleted == true`. The repository is the only place that filters them.

## 6. Order

Cards, text boxes, and workspaces have a `sortKey` of type `FractionalIndex`. A fractional index is a string key. To put an item between two others, you make a new key that sorts between their keys. No other item changes.

```swift
struct FractionalIndex: Comparable, Codable, Sendable {
    let rawValue: String   // base-62 digits, compared as bytes
}
```

- `FractionalIndex.between(_:_:)` returns a key that sorts between two keys. Either argument can be `nil` for "start" or "end".
- If two devices make the same key, the record ID breaks the tie.
- The key length has a limit of 64 characters. A longer key triggers a rebalance of all keys on that canvas, in one command.

Workspaces use the key for their order in the selector. Cards and text boxes use it for their drawing order within their layer.

Strokes do not need a key. Ink is opaque white, so the drawing order of strokes does not change the image.

## 7. Entities

### 7.1 Workspace

```swift
struct Workspace: Identifiable, Codable, Sendable {
    let id: WorkspaceID
    var meta: RecordMeta
    var title: String          // 1...120 characters, trimmed
    var sortKey: FractionalIndex
}
```

### 7.2 Card

```swift
struct Card: Identifiable, Codable, Sendable {
    let id: CardID             // also the ID of its child canvas
    var meta: RecordMeta
    var canvasID: CanvasID     // the parent canvas
    var frame: Rect            // in parent canvas space, Double
    var title: String?         // 0...120 characters
    var sortKey: FractionalIndex
}
```

Rules:

- `frame.size` is at least 64 by 48 canvas points.
- `canvasID` never equals `id`. A move of a card to a different parent must not make a cycle. The `Model` function that moves a card walks the parent chain with a depth limit of `Limits.maxDepth` and refuses a cycle.
- A delete of a card marks only the card. The child content stays on disk and comes back with an undo. Clean-up of orphaned content is decision D-18.

### 7.3 Text box

```swift
struct TextBox: Identifiable, Codable, Sendable {
    let id: TextBoxID
    var meta: RecordMeta
    var canvasID: CanvasID
    var origin: Point          // top-left corner, canvas space
    var text: String           // plain text, 1...Limits.maxTextLength characters
    var sortKey: FractionalIndex
}
```

The width and the height come from the text layout. They are not stored.

Decision D-19 asks whether the text is one value or a list of paragraphs. One value is simple. A list of paragraphs makes merge conflicts smaller, as Muse found.

### 7.4 Stroke

A stroke never changes after it is created. An eraser does not edit a stroke. It marks the stroke as erased and, for a partial erase, adds new strokes for the remaining parts.

```swift
struct Stroke: Identifiable, Sendable {
    let id: StrokeID
    let canvasID: CanvasID
    let created: HybridTimestamp
    let origin: Point          // Double, canvas space
    let width: Float           // canvas points
    let points: [InkPoint]     // 2...Limits.maxPointsPerStroke
    let bounds: Rect           // computed at creation, includes width
}

struct InkPoint: Sendable {
    let x: Float               // offset from origin, canvas points
    let y: Float
    let force: Float           // 0...1, or -1 if the pencil has no pressure
    let time: Float            // seconds since the first point
}
```

Rules:

- `origin` is the first point of the stroke. Thus all offsets are small, and `Float` precision is enough.
- `points` are the subdivided points that the user saw (see [architecture.md](architecture.md) section 4.3).
- A stroke with one sample (a dot) stores the point twice.
- Strokes use a binary format, not JSON (see [storage.md](storage.md)).

### 7.5 Erase record

```swift
struct EraseRecord: Codable, Sendable {
    let strokeID: StrokeID
    let erased: HybridTimestamp
}
```

The set of erase records of a canvas is the tombstone list for its strokes. An undo of an erase removes the erase record and marks the new parts as erased.

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

`CanvasContent` is the input and the output of commands. The renderer, the exporter, and the repository read it as a value. The canvas controller holds the current value and the `History`.

## 9. Commands

```swift
protocol CanvasCommand: Sendable {
    func apply(to content: inout CanvasContent, clock: inout HybridClock) throws(CommandError)
    func revert(on content: inout CanvasContent, clock: inout HybridClock) throws(CommandError)
}
```

Rules:

- Each command makes the smallest change that does the job.
- `revert` after `apply` gives back content that is equal to the content before `apply`, except for `modified` clock values. A unit test for each command makes sure that this rule holds.
- Commands never touch disk. The repository saves the changed records after the command (see [storage.md](storage.md)).

## 10. Device state

These values belong to one device. They are not part of the library, and a backup does not need them.

```swift
struct DeviceState: Codable, Sendable {
    let deviceID: DeviceID
    var lastTimestamp: HybridTimestamp
    var lastWorkspace: WorkspaceID?
    var cameras: [CanvasID: Camera]     // last camera per canvas, at most 1,000 entries
    var navigationPath: [CardID]         // at most Limits.maxDepth
}
```

## 11. Readiness for sync and backup

The model is ready for a future sync or an automatic backup. This version does not implement either. The table shows how each future need maps to the model.

| Future need | What the model already provides |
|---|---|
| Incremental backup | One file per record. A content hash per file in the manifest (see [storage.md](storage.md)). |
| Merge of two copies | Stable IDs. `modified` HLC per record for "last writer wins". Tombstones. |
| Move without conflict | `canvasID` lives on the child. A move changes one record. |
| Reorder without conflict | `FractionalIndex` keys. |
| Ink merge | Strokes never change. Erases are separate records. Two devices can only add. |
| Mixed app versions | `schema` per record and `formatVersion` per library. An app refuses to write records with a newer schema than it knows. |

A conflict-free replicated data type (CRDT) for text is not part of this version. Decision D-19 covers the text model.

## 12. Schema changes

1. Each record type has its own `schema` number, starting at 1.
2. A change to a stored field adds 1 to the number of that type.
3. Each change comes with a migration function `migrate(from: Int, data: Data) throws -> Data` in `Persistence`.
4. Each change adds a fixture file of the old version to the test bundle. A test loads each fixture and compares the result with the expected value.
5. If a record has a newer schema than the app knows, the app opens the workspace read-only and shows a message. It never overwrites the record.
