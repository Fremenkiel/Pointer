# Open decisions

This document lists each design point where the right choice was not certain. Each entry gives the options, the recommendation, the reason, and the decision of the product owner. The product owner decided D-01 to D-25 and D-33 on 2026-10-17, and decided D-02 again after M1 on the same day. The product owner decided D-26, D-28, D-31, and D-34 to D-38 on 2026-10-17. After the M2 code review on the same day, D-41 replaced D-39, and the product owner decided D-41 to D-43.

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
| D-27 | Save policy: debounce or throttle | Recommendation: throttle, 1 s | Open |
| D-28 | Renderer memory: shared arena or per-stroke buffers, and level of detail | Arena, vertex pulling, level of detail, cached texture while the camera moves | Decided (2026-10-17) |
| D-29 | Text rendering: glyph atlas or texture per text box, and `maxTextLength` | Recommendation: glyph atlas, 10,000 characters | Open |
| D-30 | Erase records: flag or delete, and eraser commit at pencil lift | Recommendation: flag, commit at pencil lift | Open |
| D-31 | UUID version 4 or 7 | Version 7 | Decided (2026-10-17) |
| D-32 | Snapshot procedure: temporary file, second connection, time of the run | Recommendation: all three | Open |
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
| D-46 | Unit of the GPU-time target of phase 3, task 1 | Recommendation: state the target as a ratio to the 0.5-pixel value | Open |

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

- Open. Review A-02.
- Options: (a) throttle: write at most once per second while changes are pending, and at pencil lift. (b) debounce: write one second after the last change, as the current design does.
- Recommendation: (a). Option (b) breaks STO-06 during continuous drawing.

### D-28 Renderer memory and level of detail

- Decided by the product owner on 2026-10-17: option (a). See [architecture.md](architecture.md) sections 5.2 and 5.3.
- Review A-03, A-04, A-05, A-06.
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

- Decided by the product owner on 2026-10-17: option (a), UUID version 7.
- Review A-16.
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

- Open. Raised by phase 0, task 6 on 2026-10-17.
- The benchmark timed single passes and waited for each one. The GPU clock then changed between passes, and the same pass gave 1.24 ms in one run and 5.11 ms in another. The permanent test runs its passes back to back and divides the span by the pass count. Its values repeat within 4 % between runs, but they are lower than the benchmark values.
- Dense content at zoom 0.25 in the permanent test: 3.07 ms at 0.5 pixels and 1.80 ms at 1.0 pixel. The benchmark gave 4.68 ms and 2.62 ms. The target of phase 3, task 1 is "at or under 2.7 ms" in the unit of the benchmark.
- Options: (a) state the target as a ratio: the GPU time at 1.0 pixel is at most 0.58 times the time at 0.5 pixels, the ratio of the benchmark. (b) state a new absolute target in the unit of the permanent test, for example 2.0 ms. (c) keep 2.7 ms in the new unit. This target is then much easier to meet than the benchmark target.
- Recommendation: (a), because a ratio does not depend on the clock state of the GPU.

## Points in the request that conflict or are not complete

1. "Only three tools" and "drawing data structures": cards need a way in (D-08), and diagrams need a way to move things (D-10).
2. "Double tap toggles pen and eraser" and Apple's rule to honor the user setting (D-07).
3. "Squeeze for tools": the request does not say which tools. The design shows a palette with pen, eraser, text, undo, and redo.
4. "Zoom out past the current card": the request does not give the minimum zoom. The design starts with 0.25 and a release threshold of 0.7 times that value. Both need tuning on a device.
5. "Standard zoom" in the parent: the design reads it as zoom 1.0, centered on the card that you left.
6. "Export of the current canvas": the request does not say what happens to cards on that canvas. The PDF does not show them (D-13).
