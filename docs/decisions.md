# Open decisions

This document lists each design point where the right choice was not certain. Each entry gives the options, the recommendation, the reason, and the decision of the product owner. The product owner decided D-01 to D-25 and D-33 on 2026-10-17, and decided D-02 again after M1 on the same day. The product owner decided D-26, D-28, D-31, and D-34 to D-38 on 2026-10-17. After the M2 code review on the same day, D-41 replaced D-39, and the product owner decided D-41 to D-43. On 2026-10-18, before M3, the product owner decided D-27, D-29, D-30, D-32, D-50, and D-51. The product owner decided D-52 to D-60 on the same day. The product owner decided D-61 on 2026-10-19.

Status values: Open, Decided, Replaced.

## Summary

| ID | Question | Decision | Status |
|---|---|---|---|
| D-01 | Minimum iPadOS version | iPadOS 26 | Decided (2026-10-17) |
| D-02 | Custom Metal ink engine or PencilKit | Hybrid after M1: PencilKit captures the pen input, the custom renderer draws (D-33) | Decided again (2026-10-17) |
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
| D-26 | Store raw samples or subdivided points | The control points of the PencilKit curve | Decided (2026-10-17) |
| D-27 | Save policy: debounce or throttle | Throttle, 1 s, and a write at pencil lift | Decided (2026-10-18) |
| D-28 | Renderer memory: shared arena or per-stroke buffers, and level of detail | Arena, vertex pulling, level of detail, cached texture while the camera moves | Decided (2026-10-17) |
| D-29 | Text rendering: glyph atlas or texture per text box, and `maxTextLength` | Glyph atlas, 10,000 characters | Decided (2026-10-18) |
| D-30 | Erase records: flag or delete, and eraser commit at pencil lift | Flag, commit at pencil lift | Decided (2026-10-18) |
| D-31 | UUID version 4 or 7 | Version 7 | Decided (2026-10-17) |
| D-32 | Snapshot procedure: temporary file, second connection, time of the run | All three | Decided (2026-10-18) |
| D-33 | Fallback after a failed M1 | PencilKit for input capture only, with the custom renderer | Decided (2026-10-17) |
| D-34 | Eraser and text tool input next to the live `PKCanvasView` | Turn off the PencilKit drawing gesture for these tools | Decided (2026-10-17) |
| D-35 | FEEL-02 and the PencilKit drawing gesture recognizer | FEEL-02 keeps only "Ink appears on the first touch sample" | Decided (2026-10-17) |
| D-36 | Camera movement during a pencil stroke | Ignore finger pan and pinch while the pencil draws | Decided (2026-10-17) |
| D-37 | Pen width | 2 canvas points, a start value | Decided (2026-10-17) |
| D-38 | Ink color and blending at the handoff | sRGB layer, `max` blending, white as close to `#FFFFFF` as possible | Decided (2026-10-17) |
| D-39 | Frame rate of pan and zoom in M2 | Replaced by D-41 | Replaced (2026-10-17) |
| D-40 | Measured pen latency against FEEL-01 | About 25 ms accepted for M2 | Decided (2026-10-17) |
| D-41 | Drawable count of the Metal layer | Three drawables | Decided (2026-10-17) |
| D-42 | Thread of the frame encoding | A render thread with `CAMetalDisplayLink`, off the main actor | Decided (2026-10-17) |
| D-43 | Scope of PERF-01 | No allocation in Pointer code, measured against a bare Metal frame | Decided (2026-10-17) |
| D-44 | Window access in the frame-loop test | One inline lint exception for `UIApplication.shared` | Decided (2026-10-17) |
| D-45 | Dense content of the performance tests | Two contents: the M2 content and the benchmark content | Decided (2026-10-17) |
| D-46 | Unit of the GPU-time target of phase 3, task 1 | A ratio: at most 0.58 times the GPU time at 0.5 pixels | Decided (2026-10-17) |
| D-47 | Texture margin of phase 2, task 4: 2x or 1.5x | Keep 2x | Decided (2026-10-17) |
| D-48 | Zoom 1 target of phase 3, task 3 | Accept the gain at zoom 8 only | Decided (2026-10-18) |
| D-49 | Memory target of phase 4, task 5 | Accept 68.7 MB for the store of 200,000 strokes | Decided (2026-10-18) |
| D-50 | Nodes in M3 acceptance 3 | M3 adds the card and text box types and tables, with no UI | Decided (2026-10-18) |
| D-51 | Pass of M3 acceptance 2 | Files shows the snapshot, and `sqlite3` on a Mac opens it. The second iPad moves to M9. | Decided (2026-10-18) |
| D-52 | First launch, and a delete of the current workspace | Make "Workspace" at the first launch, open the first workspace after a delete | Decided (2026-10-18) |
| D-53 | Store, write points, and camera limit of the device state | A separate `device.sqlite`. Write at camera rest, workspace change, and background. Drop the least recently used camera. | Decided (2026-10-18) |
| D-54 | Process stop in the crash test of M3 acceptance 1 | A Mac test stops a helper process with `SIGKILL` | Decided (2026-10-18) |
| D-55 | Saved strokes of the `-fillStrokes` launch argument | Not saved | Decided (2026-10-18) |
| D-56 | Content of M3 acceptance 3 | 20,000 strokes of 300 points, 5,000 cards, 5,000 text boxes, to the first frame | Decided (2026-10-18) |
| D-57 | The unit of the title and text length limits | Unicode code points, as SQLite `length()` counts | Decided (2026-10-18) |
| D-58 | Stored form of the `library` rows | Decimal version, hex clock value, lowercase device UUID | Decided (2026-10-18) |
| D-59 | Window access in the snapshot tests of SwiftUI views | The exception of D-44 in the snapshot helper | Decided (2026-10-18) |
| D-60 | File access in the open test of M3 acceptance 3 | One inline lint exception, as in D-44 | Decided (2026-10-18) |
| D-61 | The end of a fast stroke that PencilKit drops at the pencil lift | Accept the stroke that PencilKit gives | Decided (2026-10-19) |
| D-62 | Window access in the open and memory tests of the canvas | One inline lint exception, as in D-44 | Decided (2026-10-19) |
| D-63 | How to change the tool in M4 | A squeeze of the pencil opens the tool bar | Decided (2026-10-19) |
| D-64 | Tool change without a squeeze | A button in the top left shows the current tool and opens the palette | Decided (2026-10-19) |
| D-65 | Control points of the parts after a cut | Keep the outside control points and add the cut point as the new end | Decided (2026-10-19) |
| D-66 | Eraser feedback and the committed texture | A mask texture during the gesture, a redraw of the area at the lift | Decided (2026-10-19) |
| D-67 | The start state in the test of an erase command | Compare the live content | Decided (2026-10-19) |
| D-68 | Undo of an added stroke, and the strokes in memory | Commands hold `Stroke` values, `strokes` holds live strokes only | Decided (2026-10-19) |
| D-69 | What M4 acceptance 2 measures | The command on the Mac, and the lift to the first frame on the iPad | Decided (2026-10-19) |
| D-70 | A tool change during a pencil touch | The change takes effect at the next pencil down | Decided (2026-10-19) |
| D-71 | Short parts and the stroke limit after a cut | Drop parts shorter than the pen width. An erase can go past the stroke limit. | Decided (2026-10-19) |
| D-72 | The shape bound of D-65 after a cut | Keep the cut rule. The change is at most half the distance to the dropped point. | Decided (2026-10-19) |
| D-73 | The stroke count after an erase passes the stroke limit | Open. Recommendation: a hard bound of 210,000 strokes | Open (2026-10-19) |
| D-74 | The end point of the clock in M4 acceptance 2 | Open. Recommendation: the end of the GPU work of the first frame | Open (2026-10-19) |

## Details

### D-01 Minimum iPadOS version

- Decided by the product owner on 2026-10-17: iPadOS 26.
- Options: iPadOS 18 (`UIUpdateLink`, custom tool picker items), iPadOS 26 (Liquid Glass design), iPadOS 27 (newest PencilKit features).
- Recommendation: iPadOS 26. Pointer is a personal tool, so a wide device range has little value. The iPadOS 27 features stay optional behind `if #available`.
- Doubt: if you want the app on an older iPad, choose 18.

### D-02 Custom Metal ink engine or PencilKit

- Decided again by the product owner on 2026-10-17, after M1: the hybrid of D-33. PencilKit captures the pen input and draws the live stroke. The custom Metal renderer draws all finished ink. In M1, the custom input path trailed the pencil in every configuration. PencilKit and the hybrid showed no trail. See [research.md](research.md) section 3.5.
- First decision on 2026-10-17: custom engine, with the M1 latency test. If the custom engine is more than 3 ms slower than PencilKit, the product owner decides again.
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

- Decided by the product owner on 2026-10-17: option (a) in the form after M1. A stroke stores the control points of the `PKStrokePath`. Pointer draws the same uniform cubic B-spline (a smooth curve that is set by its control points) as PencilKit. See [architecture.md](architecture.md) sections 4.2 and 4.3.
- Raised by the design review of 2026-10-17 ([review-2026-10-17.md](review-2026-10-17.md), A-01).
- Options: (a) store the filtered 240 Hz samples and define the shared geometry as the curve through them. (b) store the subdivided polyline, as the current design does.
- Recommendation: (a). Option (b) inflates stored points 3 to 27 times and ends a fast stroke after 3 to 4 seconds. It also ties the stored data to a rendering tolerance.
- Doubt: with (a), the renderer and the PDF exporter flatten the same curve with different tolerances. The curve is the same, the polylines are not identical.
- Change after M1 (D-02): PencilKit gives the stroke, so the options change. (a) becomes the control points of the `PKStrokePath`. Pointer then needs its own curve that matches the curve of PencilKit. (b) becomes the points of `interpolatedPoints(by: .distance(0.5))`, which match the live stroke exactly.

### D-27 Save policy

- Decided by the product owner on 2026-10-18: option (a), throttle. [storage.md](storage.md) section 4 has the rule.
- Review A-02.
- Options: (a) throttle: write at most once per second while changes are pending, and at pencil lift. (b) debounce: write one second after the last change, as the current design does.
- Recommendation: (a). Option (b) breaks STO-06 during continuous drawing.

### D-28 Renderer memory and level of detail

- Decided by the product owner on 2026-10-17: option (a). See [architecture.md](architecture.md) sections 5.2 and 5.3.
- Review A-03, A-04, A-05, A-06.
- Options: (a) one shared arena buffer per canvas with vertex pulling and a draw list per frame. While the camera moves, a cached committed texture and a stride per zoom band limit the work. (b) one buffer per stroke with `CapsuleInstance` arrays, as the current design does.
- Recommendation: (a). It stores the points once, removes the buffer build at pencil lift, and keeps pan and zoom within the GPU budget at the stroke limit.
- Doubt: (a) needs a slab allocator and a level-of-detail step in M2. Both are small, but M2 grows.

### D-29 Text rendering and text length

- Decided by the product owner on 2026-10-18: option (a), a glyph atlas, and `maxTextLength = 10,000`.
- Review A-10.
- Options: (a) a glyph atlas per power-of-two scale, one quad per character. (b) one texture per text box, as the current design does.
- Recommendation: (a), and `maxTextLength = 10,000`. Option (b) exceeds the Metal texture limit at the current text limit.
- Doubt: (a) handles SF Mono well, because the font is monospaced. A later proportional font needs a layout step.

### D-30 Erase records and eraser commit

- Decided by the product owner on 2026-10-18: option (a) in both. An erase record has `modified` and `is_deleted`, and the eraser commits one command at pencil lift.
- Review A-07, A-08, A-09.
- Options for the record: (a) an erase record gets `modified` and `is_deleted`, and an undo sets the flag. (b) an undo deletes the record, as the current design does.
- Options for the gesture: (a) a mask in memory during the gesture and one command at pencil lift. (b) a split at every sample, as the current design does.
- Recommendation: (a) in both. Option (b) for the record breaks the change-upload plan of data-model.md section 11. Option (b) for the gesture writes stroke rows 240 times per second.

### D-31 UUID version

- Decided by the product owner on 2026-10-17: option (a), UUID version 7.
- Review A-16.
- Options: (a) UUID version 7, time-ordered, made in `Model`. (b) UUID version 4 from `UUID()`.
- Recommendation: (a). RFC 9562 states that random UUIDs have poor index locality. The change costs about 20 lines now and a migration later.

### D-32 Snapshot procedure

- Decided by the product owner on 2026-10-18: option (a). [storage.md](storage.md) sections 7.1 and 7.2 have the procedure.
- Review A-12, A-13.
- Options: (a) write to a temporary file and rename it after success. Run `VACUUM INTO` on a second read-only connection in its own actor. Run it at the first idle moment after 24 hours while the app is active. (b) run it on the repository connection at the background transition, as the current design does.
- Recommendation: (a). Option (b) can leave a corrupt file in `Backups/` and stops saves while it runs.

### D-33 Fallback after a failed M1

- Decided by the product owner on 2026-10-17: option (b). If the custom engine is more than 3 ms slower than PencilKit, PencilKit captures the pencil input and the custom renderer draws. M1 measures this setup as a third prototype.
- Review A-17.
- D-02 names PencilKit as the fallback. Apple confirmed in March 2026 that `PKCanvasView` flickers at zoom scales other than 1x, with no workaround. Pointer zooms from 0.25 to 8. The fallback also needs one `PKCanvasView` per visible card.
- Options: (a) accept the measured latency of the custom engine. (b) PencilKit for input capture only, with the custom renderer. (c) keep PencilKit as the fallback and accept the flicker.
- Recommendation: decide before M1 starts, so that M1 measures the right things.

### D-34 Eraser and text tool input with the live `PKCanvasView`

- Decided by the product owner on 2026-10-17: option (a).
- Raised by the hybrid of D-02.
- The `PKCanvasView` on top of the canvas gets the pencil touches through its drawing gesture recognizer. The eraser needs every sample while the pencil moves (architecture.md 4.4). PencilKit gives no samples before pencil lift. The PencilKit eraser erases only the `PKDrawing`, which holds no finished ink.
- Options: (a) turn off `drawingGestureRecognizer` while the eraser or the text tool is active. The canvas view then reads the pencil touches directly, as in the first design. (b) remove the `PKCanvasView` from the view tree while the eraser or the text tool is active.
- Recommendation: (a). It is one property change, and the eraser keeps the design of architecture.md section 4.4.
- Doubt: the M1 spikes did not test a tool switch during use. M2 or M4 must make sure that the first eraser sample is not lost after a switch.

### D-35 FEEL-02 and the PencilKit drawing gesture recognizer

- Decided by the product owner on 2026-10-17: option (a). [product-spec.md](product-spec.md) has the new text of FEEL-02.
- Raised by the hybrid of D-02.
- FEEL-02 says: "Ink appears on the first touch sample. No gesture recognizer delays the start of a stroke." PencilKit draws through its own gesture recognizer. In M1, the product owner saw no delay at the start of a PencilKit stroke.
- Options: (a) change FEEL-02 to "Ink appears on the first touch sample" and remove the sentence about gesture recognizers. (b) keep FEEL-02 as it is and accept the PencilKit gesture recognizer as an exception.
- Recommendation: (a). The requirement then states the effect that the user sees, and a test can measure it.

### D-36 Camera movement during a pencil stroke

- Decided by the product owner on 2026-10-17: option (a). Finger pan and pinch do nothing while the pencil draws.
- Raised by the hybrid of D-02.
- The `PKCanvasView` draws the live stroke at zoom 1 and does not follow the camera. A finger pan or pinch during a pencil stroke moves the finished ink but not the live stroke.
- Options: (a) ignore finger pan and pinch while the pencil is down. (b) end the stroke with a handoff when the camera starts to move. (c) move the `PKCanvasView` with a transform that follows the camera.
- Recommendation: (a). Option (b) splits one stroke into two. Option (c) scales the `PKCanvasView` and can bring back the tile flicker of PencilKit at zoom scales other than 1x.

### D-37 Pen width

- Decided by the product owner on 2026-10-17: 2 canvas points. This is a start value. Tune it on a device.
- The M1 spikes used 2 points. No document gave a value before.
- At zoom 0.25 the PencilKit tool width is 0.5 points, and at zoom 8 it is 16 points. M2 acceptance 5 tests these widths against `validWidthRange`.

### D-38 Ink color and blending at the handoff

- Decided by the product owner on 2026-10-17.
- Raised by the M1 hybrid spike, where the live stroke and the finished stroke looked different (FEEL-03).
- Color space: the Metal layer uses `.bgra8Unorm` with the sRGB color space. White and black are then exact on sRGB and on Display P3 screens, because both use the same white point. The anti-aliased edge is in gamma space, as in Core Graphics.
- Blending: the ink pipeline uses `MTLBlendOperation.max`. Overlapping parts of the ink do not get brighter. The "over" blend of the spike made the joints brighter.
- White: the ink is as close to `#FFFFFF` as possible, and exact if the platform allows it. The `PKCanvasView` uses the light interface style and the tool color `UIColor.white`, so PencilKit does not convert the color. A test makes sure that the center of a stroke reads 255 in each channel, both in PencilKit and in Metal. If PencilKit cannot give 255, the test records the value that it gives, and the Metal ink uses the same value.

### D-39 Frame rate of pan and zoom in M2

- Decided by the product owner on 2026-10-17: option (c). Pan and zoom at 60 Hz are accepted for now. The build budget stays at 250,000 draw instances per frame, and the layer keeps two drawables.
- Raised by the device test of M2 on an iPad Pro 11-inch (M4) with 20,000 strokes. Pan and zoom ran at a steady 60 Hz with zero hitches. The Settings app ran at 120 Hz in the same test. The ink pass took 5.7 ms of GPU time per frame (median), 7.8 ms at the 90th percentile. With two drawables, this work does not fit into one frame of 8.3 ms.
- Options: (a) three drawables, at the cost of up to one frame more display latency for the Metal ink. (b) less GPU work per draw instance: a cheaper shader and more level of detail. (c) keep the setup and accept 60 Hz while the camera moves. A budget of 80,000 instances was tried and rejected by the product owner after a look on the device.
- Recommendation: (a) now and (b) later.
- Effect: CAN-05 and M2 acceptance 2 and 10 ask for 120 Hz. With this decision, the M2 test checks for zero hitches at the rate that the system chooses. Option (b) stays open for a later milestone.
- Replaced on 2026-10-17 by D-41. The benchmarks of [m2-fix-plan.md](m2-fix-plan.md) showed that the drawable count, not the GPU time, set the 60 Hz.

### D-40 Measured pen latency against FEEL-01

- Decided by the product owner on 2026-10-17: the measured latency is accepted for M2 acceptance 1.
- Raised by the device test of M2 on an iPad Pro 11-inch (M4). In a 240 fps video of fast strokes, the ink reached the pencil tip after about 6 video frames, so about 25 ms. FEEL-01 sets 20 ms as the limit and 13 ms as the goal.
- PencilKit draws the live stroke alone (D-02, D-33), so Pointer cannot make this part faster with its own renderer. A comparison with Apple Notes, which also uses PencilKit, was not made.
- Effect: FEEL-01 keeps its numbers. M2 acceptance 1 counts as met with the measured value.

### D-41 Drawable count of the Metal layer

- Decided by the product owner on 2026-10-17: three drawables. This replaces D-39.
- Raised by the benchmarks of the M2 code review on an iPad Pro 11-inch (M4), section 2 of [m2-fix-plan.md](m2-fix-plan.md).
- With two drawables, a pan ran at exactly 60 Hz, also at 0.34 ms of GPU time per frame. `nextDrawable()` blocked the main thread for 16.3 ms in each frame.
- With three drawables, a pan ran at 120 Hz with zero late frames. This was also true with a build in every frame and 5.5 ms of GPU time.
- Cost: up to one frame more display latency for the Metal ink. The live pen stroke does not use this layer (D-02, D-33). The handoff must still pass FEEL-03.
- Effect: CAN-05 and M2 acceptance 2 and 10 test 120 Hz again.

### D-42 Thread of the frame encoding

- Decided by the product owner on 2026-10-17: the renderer encodes its frames on a render thread. A `CAMetalDisplayLink` on the run loop of that thread drives the frames and gives the drawable.
- Raised by the same benchmarks. With three drawables, `nextDrawable()` still blocked the main thread for 5.7 to 7.9 ms in each frame. Touches wait during that time. When no drawable is free, `nextDrawable()` waits up to one second, as Apple documents.
- The render thread owns `CommittedLayer`, `InkEncoder`, `StrokeStore`, and `DrawListRing`. The main actor sends the camera and the new strokes as values. The handoff callback returns to the main actor.
- Effect: architecture.md sections 5.1 and 11 change. The low-latency settings of `UIUpdateLink` for the eraser in M4 need a new design, because `UIUpdateLink` runs on the main thread only.

### D-43 Scope of PERF-01

- Decided by the product owner on 2026-10-17: PERF-01 covers the allocations of Pointer code only.
- Raised by the same benchmarks. A bare Metal command buffer with one render pass makes 33 to 36 heap allocations inside Metal. The rule "no allocation" cannot pass for any Metal frame.
- The test counts the allocations of a frame and subtracts the count of a bare frame with the same passes. The result must be 0.

### D-44 Window access in the frame-loop test

- Decided by the product owner on 2026-10-17: the frame-loop test reads the window of the host app through `UIApplication.shared`, with one `// swiftlint:disable:next arch_05_singletons` line and a comment that names this decision.
- Raised by phase 0, task 3 of [m2-fix-plan.md](m2-fix-plan.md). The test must draw on the screen of the device. Only `UIApplication.shared` reaches the window of the test host, and lint rule ARCH-05 bans it outside `PointerApp/`.
- Options: (a) one inline exception in the test. (b) a path exclusion in `.swiftlint.yml`. (c) no window test, Instruments only.
- Effect: the rule ARCH-05 and `.swiftlint.yml` stay as they are.

### D-45 Dense content of the performance tests

- Decided by the product owner on 2026-10-17: the tests use two dense contents with different names.
- Raised by phase 0, task 6. Section 1 of [m2-fix-plan.md](m2-fix-plan.md) called the benchmark content "the content of the M2 performance tests", but the two differ. The M2 content has a wave of 4 canvas points with a period of about 31 points, so its neighbor points are up to 0.8 canvas points apart. The benchmark content is a smooth curve, and its points are 0.08 canvas points apart. At zoom 0.25, the M2 content gives 3,000,000 draw instances, and the benchmark content gives 560,000.
- `PerformanceContent.m2Dense` keeps the content of the two M2 content-pass tests, so their baselines stay comparable with M2. `PerformanceContent.dense` is the benchmark content. The frame-loop and level-of-detail tests use it, so the targets of the fix plan stay comparable.

### D-46 Unit of the GPU-time target of phase 3, task 1

- Decided by the product owner on 2026-10-17: option (a), the ratio.
- Raised by phase 0, task 6 on 2026-10-17.
- The benchmark timed single passes and waited for each one. The GPU clock then changed between passes, and the same pass gave 1.24 ms in one run and 5.11 ms in another. The permanent test runs its passes back to back and divides the span by the pass count. Its values repeat within 4 % between runs, but they are lower than the benchmark values.
- Dense content at zoom 0.25 in the permanent test: 3.07 ms at 0.5 pixels and 1.80 ms at 1.0 pixel. The benchmark gave 4.68 ms and 2.62 ms. The target of phase 3, task 1 is "at or under 2.7 ms" in the unit of the benchmark.
- Options: (a) state the target as a ratio: the GPU time at 1.0 pixel is at most 0.58 times the time at 0.5 pixels, the ratio of the benchmark. (b) state a new absolute target in the unit of the permanent test, for example 2.0 ms. (c) keep 2.7 ms in the new unit. This target is then much easier to meet than the benchmark target.
- Recommendation: (a), because a ratio does not depend on the clock state of the GPU.
- Effect: phase 3, task 1 of [m2-fix-plan.md](m2-fix-plan.md) uses the ratio as its target.

### D-47 Texture margin of phase 2, task 4

- Decided by the product owner on 2026-10-17: option (a), keep 2x.
- Raised by phase 2, task 4 of [m2-fix-plan.md](m2-fix-plan.md) on 2026-10-17.
- Task 4 says: if 1.5x gives no uncovered frames at pan speeds up to 2,000 view points per second, use 1.5x. Task 2 asks for at most 20 builds and a mean GPU time under 1 ms in a 4-second pan of 20,000 dense strokes. At 1.5x, task 4 passes and task 2 fails.
- Measured on the iPad Pro 11-inch (M4), 4 seconds each, with the rebuild policy:

| Run | Builds at 2x | Builds at 1.5x | GPU ms mean at 2x | GPU ms mean at 1.5x | Uncovered frames |
|---|---|---|---|---|---|
| Dense pan, about 1,580 points per second | 16 | 33 | 0.91 | 1.37 | 0 at both |
| Dense pan, 2,000 points per second | 21 | 43 | 1.00 | 1.52 | 0 at both |
| Handwriting pan | 17 | 32 | 1.48 | 1.54 | 0 at both |

- Options: (a) keep 2x. Task 2 passes, and the textures keep 13.5 MB more on the 11-inch iPad and about 20 MB more on the 13-inch iPad. (b) use 1.5x and accept about twice the builds and about 0.5 ms more GPU time per frame. (c) use 1.5x with a smaller margin reserve than a quarter, which gives fewer builds but less room before a pan shows uncovered screen.
- Recommendation: (a). The memory saving is small against the 300 MB budget of a canvas, and the GPU time of a pan is the cost that the user feels.
- Effect: `CommittedLayer.textureScale` stays 2. Task 2 of phase 2 keeps its targets.

### D-48 Zoom 1 target of phase 3, task 3

- Decided by the product owner on 2026-10-18: option (a). Task 3 is done with the gain at zoom 8.
- Raised by phase 3, task 3 of [m2-fix-plan.md](m2-fix-plan.md). The task asks for at least 30 % fewer instances of handwriting at zoom 1 and 8, with a largest pixel difference of at most 17.
- A run has one piece count for all its segments. Zoom 8 met the target: 44 % fewer instances, difference 15. At zoom 1, 30 % fewer instances came only with a difference of 40, as in the benchmark. The table is in [m2-fix-plan.md](m2-fix-plan.md), phase 3.
- Options: (a) accept zoom 8 only. (b) accept a difference of 40 at zoom 1 and 58 at zoom 8. (c) give each segment its own piece count, with a per-segment instance table in the shader.
- Effect: `LevelOfDetail.maxPieceError` stays 0.125 pixels. Handwriting at zoom 1 keeps its instances, about 1 ms of GPU time for a full pass.

### D-49 Memory target of phase 4, task 5

- Decided by the product owner on 2026-10-18: option (a).
- Raised by phase 4, task 5 of [m2-fix-plan.md](m2-fix-plan.md). The task asks for at most 30 MB of heap for the renderer store of 200,000 handwriting strokes. The benchmark gave 77 MB.
- The three changes of the task took the store to 68.7 MB on the simulator: `DrawInfo` takes 48 bytes, the store keeps `InkPoints` references, and the arrays grow with the canvas. The rest is outside the task: the spatial grid takes 33 MB, and the map from stroke ID to slot takes 12 MB. Of the grid, the map from slot to bounds takes about 21 MB.
- Options: (a) accept 68.7 MB. (b) drop the bounds map of `SpatialGrid`, a change of a Tier A public API, for about 47 MB. (c) a renderer grid of 32-bit slots with `Float` bounds and a smaller ID map, for about 30 MB.
- Effect: `StrokeStoreMemoryTests` asserts at most 75 MB as a guard against a regression. The memory budget of 300 MB per canvas of architecture.md section 12 still holds.

### D-50 Nodes in M3 acceptance 3

- Decided by the product owner on 2026-10-18: option (a).
- Raised by the readiness review of M3 on 2026-10-18. M3 acceptance 3 opens a canvas with 10,000 nodes (cards plus text boxes), but cards and text boxes come in M5 and M6.
- Options: (a) M3 adds the `Card` and `TextBox` types, their tables, and their row codecs, with no UI. (b) M3 tests 20,000 strokes only, and the node part moves to M6.
- Effect: schema version 1 holds all tables, so M5 and M6 need no migration (GIT-04). The `text_box` table uses the limit of D-29.

### D-51 Pass of M3 acceptance 2

- Decided by the product owner on 2026-10-18: option (a).
- Raised by the readiness review of M3 on 2026-10-18. M3 acceptance 2 says that a snapshot "opens on a second iPad". Restore comes in M9, and iPadOS has no SQLite tool of its own.
- Options: (a) the snapshot shows in the Files app under `Backups`, and `sqlite3` on a Mac opens it with a clean `PRAGMA integrity_check`. The test on a second iPad moves to the restore of M9. (b) keep the second iPad in M3.
- Effect: [plan.md](plan.md) M3 acceptance 2 and M9 acceptance change.

### D-52 First launch, and a delete of the current workspace

- Decided by the product owner on 2026-10-18: option (a) in both. Raised by the M3 plan on 2026-10-18 ([m3-plan.md](m3-plan.md), tasks 3.8 and 3.9).
- WS-04 opens the last workspace at launch. At the first launch, no workspace exists. WS-03 allows a delete of the current workspace, but no document says what the app shows next.
- Options for the first launch: (a) make a workspace named "Workspace". (b) show an empty selector that asks for a name.
- Options after a delete of the current workspace: (a) open the first workspace of the list. If no workspace is left, make a new one named "Workspace". (b) open the workspace above the deleted one in the list.
- Recommendation: (a) in both. The canvas is never empty of a workspace, so the pen always has a place to draw.

### D-53 Store, write points, and camera limit of the device state

- Decided by the product owner on 2026-10-18: a separate SQLite file `device.sqlite` instead of `device.json`, and option (a) for the write and the limit. [storage.md](storage.md) section 10 has the design.
- Raised by the M3 plan on 2026-10-18 (task 3.7).
- `DeviceState` holds the last workspace and at most 1,000 cameras (data-model.md section 10). No document gives the times of the `device.json` writes. No document says which camera goes at the limit.
- Options for the write: (a) at three events: the camera comes to rest, the workspace changes, and the app moves to the background. (b) with the throttle of the library saves.
- Options at the limit: (a) drop the camera that was used least recently. (b) drop the oldest entry.
- Recommendation: (a) in both. A crash then loses at most the last camera movement, and a camera is not work under STO-06.
- Format: the product owner asked whether JSON fits. At the limit, the JSON file holds about 130 KB, and each read parses all of it, and each write rewrites all of it. The launch needs only the last workspace and its camera. Options: (a) a small SQLite file with one row per camera. (b) a binary property list, about a third of the size, but still a full parse and a full rewrite. (c) JSON. The product owner chose (a): the launch reads only the rows that it needs, a camera change writes one row, and the limit is one `DELETE`.

### D-54 Process stop in the crash test of M3 acceptance 1

- Decided by the product owner on 2026-10-18: option (a). Raised by the M3 plan on 2026-10-18 (task 3.10).
- M3 acceptance 1 asks for an automated crash test. A test cannot stop its own process and then check the result.
- Options: (a) a Mac test in `PersistenceTests` starts a helper process. The helper saves strokes through the repository for 10 seconds, and the test stops it with `SIGKILL`. Then the test opens the database and counts the strokes. (b) a UI test on the iPad adds strokes through a debug launch argument and stops the app with `XCUIApplication.terminate()`. Then it launches the app again and counts the strokes on the screen.
- Recommendation: (a). It tests the repository code that STO-06 depends on, runs in `make test`, and reads the database directly. Option (b) also covers the composition, but it runs only on a device or a simulator, and it cannot read the database.
- Doubt: (a) needs a small executable target in the `Persistence` package for the helper.

### D-55 Saved strokes of the `-fillStrokes` launch argument

- Decided by the product owner on 2026-10-18: option (a). Raised by the M3 plan on 2026-10-18 (task 3.9).
- The launch argument fills the canvas for performance tests. With storage, a canvas that saves the fill content puts it into the library.
- Options: (a) the fill content stays in memory and is never saved. (b) the fill content is saved like drawn strokes.
- Recommendation: (a). A performance run then does not add up to 200,000 strokes to the library of the device.

### D-56 Content of M3 acceptance 3

- Decided by the product owner on 2026-10-18: the recommendation. Raised by the M3 plan on 2026-10-18 (task 3.10).
- M3 acceptance 3 opens a canvas with 10,000 nodes and 20,000 strokes in under 300 ms. It does not give the size of a stroke or a text box, or the end point of the measurement.
- Recommendation: 20,000 strokes of 300 control points, 5,000 cards, and 5,000 text boxes of 200 characters each. The measurement ends at the first frame, as in architecture.md section 12.
- Doubt: 300 points per stroke is the size of the M2 dense content. Real handwriting has about 60 points per stroke, so this content is a hard case.

### D-57 Unit of the title and text length limits

- Decided by the product owner on 2026-10-18: option (a), Unicode code points. Raised by task 3.2 of [m3-plan.md](m3-plan.md).
- [data-model.md](data-model.md) section 7 gives the limits in characters: a workspace title has 1 to 120, a card title 0 to 120, and a text box 1 to `Limits.maxTextLength`. The `CHECK` constraints of [storage.md](storage.md) section 3.3 use the SQLite function `length()`. For a `TEXT` value, `length()` counts Unicode code points. Swift `String.count` counts the characters that the user sees (grapheme clusters). One emoji flag is one Swift character but two code points. A family emoji is one Swift character but up to seven code points.
- Storage.md says that the Swift code checks first and that the database is the last line of defense. If Swift counts grapheme clusters, a title of 100 flags passes the Swift check, but the `CHECK` refuses it. Then each save fails, and after three failures the app stops edits.
- Options: (a) Swift counts Unicode code points (`unicodeScalars.count`), the same unit as `length()`. The schema stays as it is. A title of emoji reaches the limit with fewer visible characters. (b) Swift counts grapheme clusters, and the `CHECK` constraints change to a larger code point limit, for example 8 times the limit. The schema changes before version 1 ships.
- Recommendation: (a). The two checks then use one unit, so a value that passes Swift always passes SQLite. The limits are generous for typed titles and notes.
- Addition by the product owner on 2026-10-18, raised by task 3.3: SQLite `length()` stops at the first U+0000. A title "\0abc" counts 4 in Swift and 0 in SQLite, and text after a U+0000 escapes the limit. Thus `Model` refuses U+0000 in titles and texts with `ModelError.nullCharacter`.

### D-58 Stored form of the `library` rows

- Decided by the product owner on 2026-10-18: the recommendation. Raised by task 3.5 of [m3-plan.md](m3-plan.md).
- [storage.md](storage.md) section 3.3 names four rows of the `library` table, but it gives the stored form of `lastTimestamp` only.
- Recommendation: `formatVersion` holds the schema version at creation as decimal text, for example "1". `created` holds the clock value of the creation in the 56-digit hex form of `lastTimestamp`. `createdBy` holds the device ID as a lowercase UUID string. The repository writes the four rows when it creates the library.

### D-59 Window access in the snapshot tests of SwiftUI views

- Decided by the product owner on 2026-10-18: option (a). Raised by task 3.8 of [m3-plan.md](m3-plan.md).
- TEST-07 asks for a snapshot test of each UI component, rendered with `UIGraphicsImageRenderer`. On iPadOS 26, a `UIHostingController` draws its SwiftUI content only inside a window. `UIWindow(frame:)` is deprecated, and warnings are errors (BUILD-02). `UIWindow(windowScene:)` needs the scene of the test host, and only `UIApplication.shared` reaches it. ARCH-05 bans `UIApplication.shared` outside `PointerApp/`.
- Tried on the simulator: `drawHierarchy` and `layer.render(in:)` without a window give black images. SwiftUI `ImageRenderer` needs no window, but it draws no content inside a `ScrollView`, so the workspace list shows no rows.
- Options: (a) extend D-44: the shared snapshot helper of a feature package reads the window scene through `UIApplication.shared`, with one `// swiftlint:disable:next arch_05_singletons` line that names D-59. (b) `ImageRenderer`, and the list leaves out its `ScrollView` in the test. The image then differs from the real view, and TEST-07 names another renderer. (c) Snapshot only the button, and leave the list without a snapshot.
- Recommendation: (a). It is the exception that D-44 already allows for one test, in one helper. The rule ARCH-05 and `.swiftlint.yml` stay as they are.

### D-60 File access in the open test of M3 acceptance 3

- Decided by the product owner on 2026-10-18: option (a). Raised by task 3.10 of [m3-plan.md](m3-plan.md).
- M3 acceptance 3 opens a canvas with the content of D-56 to the first frame. The test needs `Persistence` for the load and `Rendering` for the frame. ARCH-03 bans `Rendering` in the test folders of `Persistence`. So the test lives in the test folder of `CanvasFeature`, which `PointerDeviceTests` also compiles. There, the lint rule of ARCH-04 bans `FileManager`. The test must make a folder for a library of about 95 MB and delete it after the run.
- Options: (a) one `// swiftlint:disable:next arch_04_file_system` line for the make and one for the delete, with a comment that names D-60, as D-44 does for `UIApplication.shared`. (b) a public function in `Persistence` that makes and removes a library folder, for this test now and the restore of M9 later. (c) two tests: the load in the device tests of `Persistence` and the frame in the M2 test of `Rendering`, with the sum of the two times as the result.
- Recommendation: (a). It keeps the production code as it is and measures the open in one run. Option (b) adds API before M9 needs it. Option (c) does not measure one open.

### D-61 The end of a fast stroke that PencilKit drops at the pencil lift

- Decided by the product owner on 2026-10-19: option (a). Pointer keeps the stroke that PencilKit gives, as Apple Notes does. FEEL-03 does not hold for the end of a fast stroke. Raised by the open bug of [m3-plan.md](m3-plan.md) section 4.10.
- At the pencil lift, the final `PKStroke` of a fast stroke ends 18 to 60 points before the last pencil touch. The live PencilKit ink reaches the pencil, so its end vanishes at the lift. The product owner saw the end vanish while the overlay still showed the stroke. For a slow stroke, the gap is 2 to 11 points. Pointer stores and draws the final path exactly (D-26), so the renderer does not cause the loss.
- Apple Notes also drops the end of a fast stroke (product owner, 2026-10-19). So the setup of Pointer does not cause it.
- Options: (a) accept the end that PencilKit gives. FEEL-03 then fails for fast strokes, by the behavior of PencilKit. (b) add control points after the last control point from the pencil touches that the final path does not reach. The stored stroke then reaches the pencil, but the PencilKit overlay still drops the end at the lift for a moment. This changes D-26. (c) find a PencilKit setup that keeps the end, if the cause is in the setup of Pointer.
- Option (c) is not possible, because Apple Notes drops the end too. The choice is between (a) and (b).

### D-62 Window access in the open and memory tests of the canvas

- Decided by the product owner on 2026-10-19: option (a).
- The review of M3 on 2026-10-19 found that the open test of M3 acceptance 3 measured a stand-in path: the load and an offscreen image. The real open on the screen took 254 to 270 ms without nodes, not 197 ms. The memory budget of architecture.md section 12 had no test. Both tests must open the canvas in the window of the test host, so that its render thread runs. Only `UIApplication.shared` reaches that window, and the lint rule of ARCH-05 bans it in the test folder of `CanvasFeature`.
- Options: (a) one `// swiftlint:disable:next arch_05_singletons` line in the shared open code of the tests, with a comment that names D-62, as D-44 does. (b) a path exclusion for `Packages/CanvasFeature/Tests/` in `.swiftlint.yml`. (c) no window: the tests draw frames by hand on a `CAMetalLayer`, without the render thread and the display link.
- Effect: the rule ARCH-05 and `.swiftlint.yml` stay as they are.

### D-63 How to change the tool in M4

- Decided by the product owner on 2026-10-19: a squeeze of the pencil opens the tool bar. The tool bar of TOOL-07 is the palette of PEN-03.
- Raised by the review of M4 readiness on 2026-10-19. M4 adds the eraser, but no milestone before M7 gave a way to choose it.
- Effect: the squeeze palette moves from M7 to M4. Its text entry comes with the text tool in M5. Architecture.md section 4.5 gives the squeeze rules.
- Effect: a squeeze needs Apple Pencil Pro and a squeeze setting other than "Ignore". D-64 covers the other cases.

### D-64 Tool change without a squeeze

- Decided by the product owner on 2026-10-19: option (a).
- Raised by D-63 on 2026-10-19.
- PEN-05 says that the app works with every Apple Pencil model. Only Apple Pencil Pro has a squeeze. Apple Pencil (USB-C) has no squeeze and no double tap. If the squeeze setting is "Ignore" or "Run Shortcut", the app gets no squeeze. In these cases, the user cannot leave the pen tool. M7 acceptance 3 also requires that every feature that does not need tap or squeeze works with Apple Pencil (USB-C).
- Options:
  - (a) A small button in the top left corner shows the current tool. A finger tap on it opens the same palette. The squeeze stays the fast path.
  - (b) Move the double tap of PEN-01 from M7 to M4 as well. This helps Apple Pencil 2, but not Apple Pencil (USB-C).
  - (c) Support the tool change by squeeze only. Pencils without a squeeze then have the pen only. This breaks PEN-05.
- Recommendation: (a). It covers every pencil and every setting, and it matches the words of TOOL-07: "shows the current tool". It costs one small view.
- Doubt: (a) adds one more control to the screen.

### D-65 Control points of the parts after a cut

- Decided by the product owner on 2026-10-19: option (b). The two questions at the end of this entry moved to D-71.
- Raised by architecture.md section 4.4 and the review of M4 readiness on 2026-10-19.
- A stroke stores the control points of a uniform cubic B-spline (D-26). The eraser cuts the curve at a parameter value, not at a control point. Each end of a stroke uses a phantom point that mirrors the second point through the end point. Thus no part of the old curve can be stored exactly as a new stroke with the same rule.
- Options:
  - (a) Cut at control points. A part keeps the control points outside the eraser circle and nothing else. Simple, but a part can end up to one point spacing away from the eraser edge, inside or outside the circle.
  - (b) Add the cut point. A part keeps the control points outside the circle and gets the point of the curve at the cut as its new end point. The part ends exactly at the eraser edge. The shape changes only in the two segments next to the cut. The change is at most one sixth of the distance between the cut point and the dropped control point. D-72 corrects this bound to half the distance.
  - (c) Trim range. A part keeps all control points of the old stroke and stores a start and an end parameter. The shape stays exact. This changes D-26, `Stroke`, the schema (version 2 with a migration and a fixture), the shader, and the export.
  - (d) Refit. Sample the remaining curve and fit new control points within a tolerance. More points and more code than (b), with a shape that is only close.
- Recommendation: (b). It keeps D-26 and the schema, and the change of shape stays below a pixel at normal point spacing. A Tier A test measures the largest change against the old curve.
- The questions of short parts and of the stroke limit are in D-71.

### D-66 Eraser feedback and the committed texture

- Decided by the product owner on 2026-10-19: the recommendation: option (a) while the pencil moves, and option (d) at the lift.
- Raised by architecture.md sections 4.4 and 5.1 and the review of M4 readiness on 2026-10-19.
- The committed texture (the cached image of all finished ink) only adds strokes today. With `max` blending (D-38), the renderer cannot subtract a stroke. Architecture.md section 4.4 says that the renderer draws strokes with masks during the gesture, but no document defines a mask. `UIUpdateLink` cannot drive the render thread (D-42).
- Options for the feedback while the pencil moves:
  - (a) Mask texture. The render thread stamps the eraser circles into a second `.r8Unorm` texture. The composite pass removes the ink under the stamps. Each frame costs a few circles. At the lift, the real parts replace the stamps. The cut edges of (D-65) can differ from the circle by a fraction of a point, so a small change can show at the lift.
  - (b) Masked redraw. The render thread runs the hit test on each sample and keeps the removed parameter ranges per stroke. Each frame clears the dirty rectangle of the committed texture and draws the strokes there without their removed ranges. The picture matches the final parts, but the cost grows with the ink in the rectangle.
  - (c) Full build. After each change, the renderer starts the chunked build that exists now. No new code, but the erased ink stays on the screen until the build ends, which takes several frames on a large canvas.
- Options for the end of the gesture: (d) redraw the dirty rectangle once with the final parts, or (c) a full build.
- Recommendation: (a) with (d). It gives the shortest path from the pencil to the screen, and it changes the commit of D-30 only on the render side. If the change at the lift shows on the device, use (b).
- Effect: the steps of architecture.md section 4.4 change. The hit test and the split then run once at the lift, not on each sample.
- Effect: the redraw of an area also serves each undo and redo that removes ink.
- Effect: the mask must hide ink only. When text and cards join the committed layer in M5 and M6, the ink needs its own texture, or the mask must skip them.

### D-67 The start state in the test of an erase command

- Decided by the product owner on 2026-10-19: option (a).
- Raised by the review of M4 readiness on 2026-10-19.
- TEST-09 and data-model.md section 9 require that `revert` after `apply` gives content equal to the start state, except for `modified` values. Data-model.md section 7.5 says that an undo of an erase keeps the old erase records with `isDeleted = true` and adds erase records for the new parts. So after the revert, `erased` is not equal to the start state.
- Options:
  - (a) Compare the live content: the strokes, cards, and text boxes that are not erased or deleted. The test ignores `erased` and the `modified` values. A second test makes sure that each erase record after the revert is a tombstone of an erase.
  - (b) Compare all of `CanvasContent`. The revert then removes the session records from `erased`, and the canvas sends tombstone rows to the repository from another list. Memory and disk then differ, which data-model.md section 8 does not allow.
- Recommendation: (a). It tests what the user sees, and it keeps the rule of D-30 that no row is deleted.
- Effect: TEST-09 and data-model.md section 9 get one sentence each about the live content.

### D-68 Undo of an added stroke, and the strokes in memory

- Decided by the product owner on 2026-10-19: option (b).
- Raised by the review of M4 readiness on 2026-10-19.
- A stroke row never changes and has no tombstone. No document says how an undo of `AddStroke` hides the stroke. Review A-07 recommends that commands hold IDs only, and that the undo adds an erase record. No document took over that recommendation.
- Options:
  - (a) Commands hold IDs only. Erased strokes stay in `CanvasContent.strokes`, and every reader filters them with `erased`. This matches review A-07.
  - (b) Commands hold `Stroke` values. An erase or an undo of an add removes the stroke from `strokes` and writes an erase record. A redo puts the same value back. `InkPoints` is a shared reference (review A-03), so the command costs one reference per stroke and never copies points.
- Recommendation: (b). `strokes` then holds the live strokes only, as the renderer, the export, and the limit check expect. The memory cost equals the cost of (a), because the points live once.
- Effect: the undo of `AddStroke` writes an erase record for the stroke, and its redo sets `isDeleted = true` on that record.

### D-69 What M4 acceptance 2 measures

- Decided by the product owner on 2026-10-19: option (c), with the device and the content of the recommendation.
- Raised by the review of M4 readiness on 2026-10-19.
- M4 acceptance 2 asks for "under 16 ms per step". The steps are an erase of 1,000 strokes in one gesture, its undo, and its redo. It does not give the start and the end of the measurement, the content, or the device.
- Options:
  - (a) The command only: `apply` and `revert` of `EraseStrokes` on `CanvasContent`, on the Mac and on the iPad.
  - (b) From the pencil lift or the button tap to the end of the first frame that shows the result. The test runs on the iPad in Release. The save runs off the main actor and has its own budget of 50 ms.
  - (c) Both, with (a) as a Tier A test and (b) as the acceptance test.
- Recommendation: (c), on the iPad Pro 11-inch (M4), in Release. The content: 1,000 parallel strokes of 300 points on top of the 20,000 strokes of D-56. One eraser line crosses all 1,000 strokes and cuts each in two parts.

### D-70 A tool change during a pencil touch

- Decided by the product owner on 2026-10-19: option (a).
- Raised by the doubt of D-34 and the review of M4 readiness on 2026-10-19.
- D-34 turns off the drawing gesture of PencilKit for the eraser. A tool change while the pencil touches the screen can lose the first eraser sample, or cut a pen stroke. The code also uses the same flag for a second purpose: `CanvasViewController.isEditingEnabled` turns off drawing when the library cannot save. Thus a switch to the eraser looks like a failed library, and the eraser does not stop when saves fail.
- Options for the change:
  - (a) A tool change takes effect at the next pencil down. The current stroke or erase ends with the old tool.
  - (b) A tool change ends the current stroke or erase at once and starts the new tool.
- Recommendation: (a). A squeeze or a tap on the palette comes while the pencil is up in normal use, so (a) costs nothing. A device test changes the tool and erases at once, and checks the first sample.
- Effect: `isEditingEnabled` gets its own stored value. The drawing gesture is on only for the pen tool while editing is allowed. The eraser also checks `isEditingEnabled`.

### D-71 Short parts and the stroke limit after a cut

- Decided by the product owner on 2026-10-19: option (a) in both.
- Raised by D-65 on 2026-10-19.
- A cut can leave a part that is only a fraction of a point long. On the screen, such a part is a speck that the user did not want.
- A cut can make two strokes from one, so an erase can raise the stroke count. `CanvasContent.add(_:)` refuses a stroke at `Limits.maxStrokesPerCanvas`.
- Options for short parts: (a) drop a part whose curve is shorter than the pen width. (b) keep every part.
- Options for the limit: (a) an erase can go past the limit. The pen then refuses new strokes with the limit message. (b) an erase at the limit fails with the limit message.
- Recommendation: (a) in both. A speck is never what the user wants. An erase must never fail, and the parts of one gesture can only pass the limit by a small amount.

### D-72 The shape bound of D-65 after a cut

- Decided by the product owner on 2026-10-19: option (a).
- Raised by M4 task 3.2 on 2026-10-19.
- D-65 and architecture.md section 4.4 say that a cut changes the curve by at most one sixth of the distance between the new end point and the dropped control point. Task 3.2 makes a test of this bound a "Done when" target.
- The test fails. The cut rule of D-65 works as written, but the bound is too small. Near a cut close to a control point, the largest change is up to 2.4 times the bound, so about 0.4 times the distance.
- The cause: the bound holds for the second segment of a part. There, only the dropped control point changes, and its weight is at most one sixth. In the first segment, the phantom point at the new end also changes, and the new end point has a weight of up to four sixths.
- The change stays small in absolute terms. With control points 1.7 to 3 points apart, a smooth wave, a tight circle with a radius of 10 points, and a noisy line gave a largest change of 0.012, 0.032, and 0.043 canvas points. At zoom 8, 0.043 canvas points are 0.34 pixels.
- Options:
  - (a) Keep the cut rule of D-65. Change the bound in D-65, architecture.md section 4.4, and the test to "at most half the distance between the new end point and the dropped control point".
  - (b) Keep the bound of one sixth for the second segment only. Add a test that the first segment changes by less than 0.1 canvas points at normal point spacing.
  - (c) Change the cut rule to option (c) or (d) of D-65: a trim range or a refit.
- Recommendation: (a). It keeps the code, and it states a bound that the test can check for every segment.
- Effect: D-65, architecture.md section 4.4, and the task 3.2 target state the bound of half the distance. The test checks it for each part.

### D-73 The stroke count after an erase passes the stroke limit

- Open. Raised by M4 task 3.3 on 2026-10-19.
- D-71 lets an erase take a canvas past `Limits.maxStrokesPerCanvas` (200,000), because an erase never fails. The pen then refuses new strokes. M4 task 3.1 implements this in `Model`.
- Three other parts of the code stop at the limit:
  - The load of a canvas in `Persistence` reads at most 200,000 strokes. It skips the other rows and reports a fault (storage.md section 5). After a new launch, the strokes above the limit do not show, and the app reports damaged data.
  - `CanvasViewController` stops with a precondition failure if the loaded strokes do not fit the limit.
  - `StrokeStore.add` in `Rendering` stops with a precondition failure at the limit. The parts of an erase at the limit thus stop the app.
- No document gives a bound for the count above the limit. Each erase can add parts, so the count can grow with each erase. FLOW-03 needs a named bound for each collection.
- Options:
  - (a) Add `Limits.maxStrokesAfterErase`, for example 210,000, 5 % above the limit. The load, the canvas, and the renderer accept up to this bound. An erase whose parts would pass it removes the strokes that it touches whole, without parts. Thus an erase never fails and never passes the bound.
  - (b) Same bound as (a), but an erase whose parts would pass it fails with the limit message. This breaks "an erase never fails" of D-71 at the bound only.
  - (c) Change D-71: an erase at the limit removes the strokes that it touches whole, so the count never passes 200,000.
- Recommendation: (a). It keeps D-71 for each normal case, and every part of the code has one named bound. The load reads at most 210,000 strokes, so its time and memory grow by at most 5 % at the bound.
- Effect: the pen keeps its limit of 200,000. The load, `CanvasViewController`, the renderer, and `EraseStrokes` use the new bound. Architecture.md section 10 and storage.md section 5 get the new limit.
- Tasks that wait: M4 task 3.5 sends the parts of an erase to the renderer. Tasks 3.3 and 3.4 do not depend on the decision.

### D-74 The end point of the clock in M4 acceptance 2

- Open. Raised by M4 task 3.8 on 2026-10-19.
- D-69 runs the clock from the pencil lift, or from the undo or redo call, to the end of the first frame that shows the result. The budget is 16 ms per step. The test takes the presented callback of that frame as its end.
- On the iPad Pro 11-inch (M4) in Release, an empty change takes 13 to 16 ms from the call to its presented callback. The frame loop sleeps when idle, so a change waits for the next display frame. With a frame latency of 2 (architecture.md section 5.1), the frame shows about two display frames later. Thus the pipeline alone uses the whole budget, and no step with work can pass.
- The steps after the fixes of task 3.8, medians of 5 rounds: erase 37.5 ms, undo 29.6 ms, redo 29.8 ms. The work in them: the main thread takes 24 to 27 ms for an erase and 6 to 10 ms for an undo or a redo. The render thread takes 6 to 14 ms of CPU and 1 to 3 ms of GPU for the frame of the change.
- Options:
  - (a) End the clock when the GPU completes the first frame that holds the change, not at its presentation. The budget of 16 ms then covers the work of the main thread, the render thread, and the GPU, and the wait for the display frame. The pipeline latency stays covered by the pen latency budget of FEEL-01.
  - (b) Keep the presented end and raise the budget to the pipeline floor plus 16 ms, about 32 ms.
  - (c) Keep D-69 as written. The acceptance then cannot pass on this iPad.
- Recommendation: (a). It measures the work that the code controls. The erase then still needs a faster split, about 14 ms on the iPad today. Undo and redo are close.
- Effect: task 3.8 waits for this decision.

## Points in the request that conflict or are not complete

1. "Only three tools" and "drawing data structures": cards need a way in (D-08), and diagrams need a way to move things (D-10).
2. "Double tap toggles pen and eraser" and Apple's rule to honor the user setting (D-07).
3. "Squeeze for tools": the request does not say which tools. The design shows a palette with pen, eraser, text, undo, and redo.
4. "Zoom out past the current card": the request does not give the minimum zoom. The design starts with 0.25 and a release threshold of 0.7 times that value. Both need tuning on a device.
5. "Standard zoom" in the parent: the design reads it as zoom 1.0, centered on the card that you left.
6. "Export of the current canvas": the request does not say what happens to cards on that canvas. The PDF does not show them (D-13).
