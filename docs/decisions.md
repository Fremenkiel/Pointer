# Open decisions

This document lists each design point where the right choice was not certain. Each entry gives the options, the recommendation, the reason, and the decision of the product owner. The product owner decided D-01 to D-25 and D-33 on 2026-10-17.

Status values: Open, Decided.

## Summary

| ID | Question | Decision | Status |
|---|---|---|---|
| D-01 | Minimum iPadOS version | iPadOS 26 | Decided (2026-10-17) |
| D-02 | Custom Metal ink engine or PencilKit | Custom engine, with a latency test in M1 | Decided (2026-10-17) |
| D-03 | One database for the library or one per workspace | One database | Decided (2026-10-17) |
| D-04 | Third-party development tools | Allowed: linters, formatters, rule checkers. The app links none. | Decided (2026-10-17) |
| D-05 | Pressure changes the line width | No, fixed width | Decided (2026-10-17) |
| D-06 | Partial eraser or whole-stroke eraser | Partial | Decided (2026-10-17) |
| D-07 | Double tap and the system setting | Follow "Ignore", else toggle pen and eraser | Decided (2026-10-17) |
| D-08 | How to create a card | Long press on empty canvas, then "New card" | Decided (2026-10-17) |
| D-09 | How to open a card | Finger double tap on the card | Decided (2026-10-17) |
| D-10 | Move content and lasso selection | Move cards and text boxes in version 1, lasso later | Decided (2026-10-17) |
| D-11 | Delete a workspace | Yes, with a confirmation | Decided (2026-10-17) |
| D-12 | Scope and life of undo history | Per canvas, in memory | Decided (2026-10-17) |
| D-13 | PDF background and nested cards | White page, black ink and text, no cards | Decided (2026-10-17) |
| D-14 | Scheduled backup through Shortcuts | No App Intent | Decided (2026-10-17) |
| D-15 | Text font | SF Mono | Decided (2026-10-17) |
| D-16 | Layer order on a canvas | Cards, then ink, then text | Decided (2026-10-17) |
| D-17 | One ID type or one type per entity | One type per entity | Decided (2026-10-17) |
| D-18 | Content of deleted cards | Keep for 30 days. Undo brings it back. | Decided (2026-10-17) |
| D-19 | Text as one string or as paragraphs | One string | Decided (2026-10-17) |
| D-20 | Restore inside the app | Yes, in version 1 | Decided (2026-10-17) |
| D-21 | Snapshot interval and count | Daily, keep 7 | Decided (2026-10-17) |
| D-22 | Handwriting search with `PKStrokeRecognizer` | Not in version 1, keep the path open | Decided (2026-10-17) |
| D-23 | System haptics | System haptics are accepted. The app plays none, and drawing plays none. | Decided (2026-10-17) |
| D-24 | Load a canvas whole or by viewport | Whole canvas, R-tree later if needed | Decided (2026-10-17) |
| D-25 | SQLite or plain files | SQLite | Decided (2026-10-17) |
| D-26 | Store raw samples or subdivided points | Recommendation: raw samples | Open |
| D-27 | Save policy: debounce or throttle | Recommendation: throttle, 1 s | Open |
| D-28 | Renderer memory: shared arena or per-stroke buffers, and level of detail | Recommendation: arena, vertex pulling, cached texture while the camera moves | Open |
| D-29 | Text rendering: glyph atlas or texture per text box, and `maxTextLength` | Recommendation: glyph atlas, 10,000 characters | Open |
| D-30 | Erase records: flag or delete, and eraser commit at pencil lift | Recommendation: flag, commit at pencil lift | Open |
| D-31 | UUID version 4 or 7 | Recommendation: version 7 | Open |
| D-32 | Snapshot procedure: temporary file, second connection, time of the run | Recommendation: all three | Open |
| D-33 | Fallback after a failed M1 | PencilKit for input capture only, with the custom renderer | Decided (2026-10-17) |

## Details

### D-01 Minimum iPadOS version

- Decided by the product owner on 2026-10-17: iPadOS 26.
- Options: iPadOS 18 (`UIUpdateLink`, custom tool picker items), iPadOS 26 (Liquid Glass design), iPadOS 27 (newest PencilKit features).
- Recommendation: iPadOS 26. Pointer is a personal tool, so a wide device range has little value. The iPadOS 27 features stay optional behind `if #available`.
- Doubt: if you want the app on an older iPad, choose 18.

### D-02 Custom Metal ink engine or PencilKit

- Decided by the product owner on 2026-10-17: custom engine. The M1 latency test still runs. If the custom engine is more than 3 ms slower than PencilKit, the product owner decides again.
- Options: a custom Metal engine (the design in these documents), PencilKit, or PencilKit for capture with custom display.
- Recommendation: custom engine. PencilKit has a confirmed tile-render bug at zoom levels other than 1x. It needs one view per visible card. It stores data in a format that is not documented.
- Doubt: no published measurement shows that a custom engine reaches the latency of PencilKit. Press reports from 2019 say that Apple keeps part of the gain for itself. Milestone M1 measures both. If the custom engine is more than 3 ms slower, the team must decide again.

### D-03 One database or one per workspace

- Decided by the product owner on 2026-10-17: one database.
- Options: one database for the whole library, or one database file per workspace.
- Recommendation: one database. One snapshot is one complete backup, and one transaction can span workspaces (for example, a card move in a later version).
- Doubt: one database per workspace gives smaller backup files and lets you share or restore one workspace alone. A fault in one file then damages one workspace only.

### D-04 Development tools

- Decided by the product owner on 2026-10-17: third-party development tools that improve code quality are allowed, for example linters, formatters, and rule checkers. The app still links no third-party code (BUILD-03). The standard uses SwiftLint for pattern rules and size metrics.
- The request says "as few dependencies as possible". The app links no third-party code. The question is about development tools.
- Options: (a) SwiftLint, the de facto standard, used by Proton, Infomaniak, and Threema. (b) Only `swift format` from the toolchain plus scripts in the repository. Metrics such as function length then need `swift-syntax`, a package from the Swift project.
- Recommendation: (b). `swift-syntax` is used by the scripts only and never ships in the app.
- Doubt: (b) means about 300 lines of script code to maintain. SwiftLint gives the same rules with no code.

### D-05 Pressure and line width

- Decided by the product owner on 2026-10-17: fixed width.
- Options: fixed width, or width that changes with pressure.
- Recommendation: fixed width (a monoline pen). Diagrams look clean, the PDF is an exact copy of the screen (a stroked path), and Apple Pencil (USB-C) behaves like the other models. The app stores force anyway, so a later version can add pressure.
- Doubt: a fixed width looks less like a real pen. A fountain-pen look needs outline geometry, which makes the renderer and the PDF export more complex.

### D-06 Eraser behavior

- Decided by the product owner on 2026-10-17: partial.
- Options: partial (cuts the stroke where the eraser touches), whole stroke (removes the stroke that it touches), or both with a switch.
- Recommendation: partial. It behaves like a real eraser on paper.
- Doubt: a whole-stroke eraser is faster for diagrams (one touch removes an arrow) and is simpler to build. Allume added a stroke eraser in version 3.5.2, which shows that users ask for it.

### D-07 Double tap and the system setting

- Decided by the product owner on 2026-10-17: the recommendation.
- The request says that double tap switches between pen and eraser. Apple's guidelines say that apps must honor the user's choice in Settings.
- Recommendation: if the setting is "Ignore", do nothing. For every other value, switch between pen and eraser.
- Doubt: a user who chose "Switch to previous tool" can expect a switch back from text to the pen. The recommendation does this, because text then goes to the pen.

### D-08 How to create a card

- Decided by the product owner on 2026-10-17: option (a).
- The tool list is pen, eraser, and text only. A card needs a way in.
- Options: (a) long press on empty canvas, then "New card" in a menu. (b) a fourth tool. (c) draw a rectangle with the pencil and convert it.
- Recommendation: (a). It keeps the tool list at three.
- Doubt: (c) feels more natural with a pencil but needs shape recognition, which the product rules out.

### D-09 How to open a card

- Decided by the product owner on 2026-10-17: the recommendation.
- Options: finger double tap, pinch-zoom into the card past a threshold, or both.
- Recommendation: finger double tap only. Pinch-zoom on a card must stay free for a closer look at the preview.
- Doubt: zoom-in to open is the mirror of zoom-out to leave, and Muse used it. Try both in M6.

### D-10 Move content and lasso selection

- Decided by the product owner on 2026-10-17: the recommendation.
- The request lists no selection tool. Data-structure diagrams often need a change of layout.
- Recommendation: version 1 moves cards and text boxes with a long press and drag. Ink cannot move. A lasso can come later as a mode of the eraser or a fourth tool.
- Doubt: without a lasso, a wrong position for a drawn arrow means you erase and draw it again. This is the largest gap against the request "only three tools".

### D-11 Delete a workspace

- Decided by the product owner on 2026-10-17: allow delete, with a confirmation.
- The request names create and rename only.
- Recommendation: allow delete, with a confirmation. The workspace becomes a tombstone and stays on disk for 30 days (see D-18).

### D-12 Undo history

- Decided by the product owner on 2026-10-17: the recommendation.
- Options: per canvas or one history for the app. In memory or stored.
- Recommendation: per canvas, in memory. Undo then never changes a canvas that is not on the screen.
- Doubt: after you leave a card and come back, its history is still there. After a restart, all history is gone.

### D-13 PDF background and nested cards

- Decided by the product owner on 2026-10-17: a white page with black ink and black text. The PDF does not show cards: no frame, no title, and no child content.
- Options for the background: black (as on the screen), or white with black ink (for print).
- Options for cards: frame and title only, child content one level deep, or one extra page per card.
- Recommendation: black, and child content one level deep. A white "print" option can come later.
- Doubt: a black page uses a lot of toner on a printer.

### D-14 Scheduled backup through Shortcuts

- Decided by the product owner on 2026-10-17: no App Intent in version 1. The user backs up with "Back up now" or with a manual copy in Files.
- Recommendation: include the App Intent. It uses no provider API, so it fits "no integration".
- Doubt: it is not proven that a Shortcuts automation can run the intent while the iPad is locked. If it cannot, the automation runs at the next unlock.

### D-15 Text font

- Decided by the product owner on 2026-10-17: SF Mono.
- Recommendation: SF Mono, because the notes contain code.
- Doubt: a monospaced font is wider and harder to read for long prose.

### D-16 Layer order

- Decided by the product owner on 2026-10-17: the recommendation.
- Recommendation: fixed layers. Cards at the bottom, ink in the middle, text on top. Arrows drawn over a card then stay visible.
- Doubt: a fixed order does not let you put a card on top of ink.

### D-17 ID types

- Decided by the product owner on 2026-10-17: the recommendation.
- Recommendation: one wrapper type per entity (`CardID`, `StrokeID`, and so on) instead of type aliases. The compiler then refuses a `StrokeID` where a `CardID` is needed. The data model document shows aliases for brevity.

### D-18 Content of deleted cards

- Decided by the product owner on 2026-10-17: a deleted card stays on disk for 30 days. An undo brings it back. After 30 days, the repository removes the card and its subtree at launch.
- Recommendation: a deleted card and its subtree stay on disk as tombstones for 30 days. Then the repository removes them at launch. A future sync needs the tombstones longer, so this number can change.

### D-19 Text model

- Decided by the product owner on 2026-10-17: one string.
- Recommendation: one string per text box. Text boxes are short.
- Doubt: with a future sync, two devices that edit the same box will lose one edit. Paragraph lists or a text CRDT fix this, at a cost.

### D-20 Restore inside the app

- Decided by the product owner on 2026-10-17: yes, in version 1.
- Recommendation: yes, in version 1. With SQLite, a restore is a file pick, an integrity check, and the SQLite backup API (see [storage.md](storage.md) section 7.5). Without it, a user cannot restore at all, because the live database is not visible in Files.
- Doubt: a restore replaces the whole library. The app makes a snapshot of the current library first, so a wrong restore can be undone.

### D-21 Snapshot interval and count

- Decided by the product owner on 2026-10-17: daily, keep 7.
- Recommendation: a snapshot at most once per 24 hours, at the move to the background. Keep the newest 7.
- Doubt: each snapshot is the whole library. A library of 100 MB then uses 700 MB for snapshots. Fewer snapshots save space but give fewer restore points.

### D-22 Handwriting search

- Decided by the product owner on 2026-10-17: not in version 1.
- iPadOS 27 adds `PKStrokeRecognizer`, which recognizes handwriting on the device. The custom stroke format can convert to `PKDrawing` for it.
- Recommendation: not in version 1, because the request does not ask for search. The stroke format keeps the data that the recognizer needs.

### D-23 System haptic on squeeze

- Decided by the product owner on 2026-10-17: the default haptics of the system are accepted, for example on squeeze. The app plays no haptics itself, and drawing plays none, because the app does not imitate paper.
- The product owner wants no feedback in the pencil (PEN-06). The app plays no haptics.
- Fact (checked 2026-10-17): the system plays a haptic on squeeze and on double tap of Apple Pencil Pro. The user turns it off under Settings > Apple Pencil > Haptics. No public API turns it off. Milestone M7 tests this on a device.
- Options: accept the system haptic, or ignore squeeze. The user can also turn off Apple Pencil haptics in Settings.
- Recommendation: keep squeeze. If the system plays a haptic, tell the user about the Settings switch.

### D-24 Load a canvas whole or by viewport

- Decided by the product owner on 2026-10-17: load the whole canvas.
- Recommendation: load the whole canvas in version 1. It is simple, and the `SpatialGrid` in memory handles culling.
- Doubt: a canvas near the stroke limit holds about 1 GB of points. If the device test in M3 is slow, add an R-tree index on the stroke bounds and load only the strokes near the camera.

### D-25 SQLite or plain files

- Decided by the product owner on 2026-10-17: SQLite.
- Effects: backups are snapshot files, not a copy of a live folder. A future backup uploads the whole snapshot, or a change file built from the `modified` clock values (see [storage.md](storage.md) section 8).

### D-26 Store raw samples or subdivided points

- Open. Raised by the design review of 2026-10-17 ([review-2026-10-17.md](review-2026-10-17.md), A-01).
- Options: (a) store the filtered 240 Hz samples and define the shared geometry as the curve through them. (b) store the subdivided polyline, as the current design does.
- Recommendation: (a). Option (b) inflates stored points 3 to 27 times and ends a fast stroke after 3 to 4 seconds. It also ties the stored data to a rendering tolerance.
- Doubt: with (a), the renderer and the PDF exporter flatten the same curve with different tolerances. The curve is the same, the polylines are not identical.

### D-27 Save policy

- Open. Review A-02.
- Options: (a) throttle: write at most once per second while changes are pending, and at pencil lift. (b) debounce: write one second after the last change, as the current design does.
- Recommendation: (a). Option (b) breaks STO-06 during continuous drawing.

### D-28 Renderer memory and level of detail

- Open. Review A-03, A-04, A-05, A-06.
- Options: (a) one shared arena buffer per canvas with vertex pulling and a draw list per frame. While the camera moves, a cached committed texture and a stride per zoom band limit the work. (b) one buffer per stroke with `CapsuleInstance` arrays, as the current design does.
- Recommendation: (a). It stores the points once, removes the buffer build at pencil lift, and keeps pan and zoom within the GPU budget at the stroke limit.
- Doubt: (a) needs a slab allocator and a level-of-detail step in M2. Both are small, but M2 grows.

### D-29 Text rendering and text length

- Open. Review A-10.
- Options: (a) a glyph atlas per power-of-two scale, one quad per character. (b) one texture per text box, as the current design does.
- Recommendation: (a), and `maxTextLength = 10,000`. Option (b) exceeds the Metal texture limit at the current text limit.
- Doubt: (a) handles SF Mono well, because the font is monospaced. A later proportional font needs a layout step.

### D-30 Erase records and eraser commit

- Open. Review A-07, A-08, A-09.
- Options for the record: (a) an erase record gets `modified` and `is_deleted`, and an undo sets the flag. (b) an undo deletes the record, as the current design does.
- Options for the gesture: (a) a mask in memory during the gesture and one command at pencil lift. (b) a split at every sample, as the current design does.
- Recommendation: (a) in both. Option (b) for the record breaks the change-upload plan of data-model.md section 11. Option (b) for the gesture writes stroke rows 240 times per second.

### D-31 UUID version

- Open. Review A-16.
- Options: (a) UUID version 7, time-ordered, made in `Model`. (b) UUID version 4 from `UUID()`.
- Recommendation: (a). RFC 9562 states that random UUIDs have poor index locality. The change costs about 20 lines now and a migration later.

### D-32 Snapshot procedure

- Open. Review A-12, A-13.
- Options: (a) write to a temporary file and rename it after success. Run `VACUUM INTO` on a second read-only connection in its own actor. Run it at the first idle moment after 24 hours while the app is active. (b) run it on the repository connection at the background transition, as the current design does.
- Recommendation: (a). Option (b) can leave a corrupt file in `Backups/` and stops saves while it runs.

### D-33 Fallback after a failed M1

- Decided by the product owner on 2026-10-17: option (b). If the custom engine is more than 3 ms slower than PencilKit, PencilKit captures the pencil input and the custom renderer draws. M1 measures this setup as a third prototype.
- Review A-17.
- D-02 names PencilKit as the fallback. Apple confirmed in March 2026 that `PKCanvasView` flickers at zoom scales other than 1x, with no workaround. Pointer zooms from 0.25 to 8. The fallback also needs one `PKCanvasView` per visible card.
- Options: (a) accept the measured latency of the custom engine. (b) PencilKit for input capture only, with the custom renderer. (c) keep PencilKit as the fallback and accept the flicker.
- Recommendation: decide before M1 starts, so that M1 measures the right things.

## Points in the request that conflict or are not complete

1. "Only three tools" and "drawing data structures": cards need a way in (D-08), and diagrams need a way to move things (D-10).
2. "Double tap toggles pen and eraser" and Apple's rule to honor the user setting (D-07).
3. "Squeeze for tools": the request does not say which tools. The design shows a palette with pen, eraser, text, undo, and redo.
4. "Zoom out past the current card": the request does not give the minimum zoom. The design starts with 0.25 and a release threshold of 0.7 times that value. Both need tuning on a device.
5. "Standard zoom" in the parent: the design reads it as zoom 1.0, centered on the card that you left.
6. "Export of the current canvas": the request does not say what happens to cards on that canvas. The PDF does not show them (D-13).
