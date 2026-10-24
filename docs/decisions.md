# Open decisions

This document lists each design point where the right choice was not certain. Each entry gives the options, the recommendation, the reason, and the decision of the product owner. The product owner decided D-01 to D-25 and D-33 on 2026-10-17, and decided D-02 again after M1 on the same day. The product owner decided D-26, D-28, D-31, and D-34 to D-38 on 2026-10-17. After the M2 code review on the same day, D-41 replaced D-39, and the product owner decided D-41 to D-43. On 2026-10-18, before M3, the product owner decided D-27, D-29, D-30, D-32, D-50, and D-51. The product owner decided D-52 to D-60 on the same day. The product owner decided D-61 to D-72 on 2026-10-19, and D-73 to D-80 on 2026-10-20. The M5 plan raised D-81 to D-91 on 2026-10-20, and the product owner decided them on the same day. Task 2.3 raised D-92 on the same day, and the product owner decided it on 2026-10-21. Task 2.3 raised D-93 on 2026-10-21, and the product owner decided it on the same day. The close of M5 raised D-94 on 2026-10-21, and the product owner decided it on the same day. The review of M5 raised D-95 to D-105 for M6 on 2026-10-21, and the product owner decided them with the recommendations on the same day. The product owner decided D-106 on the same day. The M6 plan raised D-107 to D-113 on 2026-10-21, and the product owner decided them with the recommendations on the same day. The product owner decided D-114 to D-119 on 2026-10-22. D-115 replaced D-09 and D-100, and D-117 replaced D-08. The M6 fix plan raised D-120 to D-122 on 2026-10-22, and the product owner decided them on the same day, then D-123 and D-124. The review before M7 raised D-125 to D-131 on 2026-10-22, and the product owner decided them on the same day. D-130 replaced the rule of D-07. The review after M7 raised D-138 to D-142 for M8 on 2026-10-23, and the product owner decided them with the recommendations on the same day. The M8 plan raised D-143 on the same day. Task 2.7 raised D-144 on the same day. The product owner decided D-143 and D-144 with the recommendations on the same day. The close of M8 raised D-145 on the same day, and the product owner decided it on 2026-10-24. The M8 fix plan raised D-146 on 2026-10-24, and the product owner decided it on the same day.

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
| D-07 | Double tap and the system setting | Replaced by D-130 | Replaced (2026-10-22) |
| D-08 | How to create a card | Replaced by D-117 | Replaced (2026-10-22) |
| D-09 | How to open a card | Replaced by D-115 | Replaced (2026-10-22) |
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
| D-73 | The stroke count after an erase passes the stroke limit | A hard bound of 210,000 strokes. An erase past it removes the strokes whole. | Decided (2026-10-20) |
| D-74 | The end point of the clock in M4 acceptance 2 | The GPU completes the first frame that holds the change | Decided (2026-10-20) |
| D-75 | M4 acceptance 2 still misses 16 ms | A budget of 33 ms for M4, 16 ms as a goal | Decided (2026-10-20) |
| D-76 | A memory bound for the undo history | 4,000,000 points per canvas and 16,000,000 points for all sessions, the oldest steps dropped first | Decided (2026-10-20) |
| D-77 | Snapshot tests while the simulator is banned | Move them into `PointerDeviceTests` with reference images made on the iPad | Decided (2026-10-20) |
| D-78 | When the eraser mask texture exists | Only while the eraser is the tool | Decided (2026-10-20) |
| D-79 | The pass rule of M4 acceptance 2 on the device | 5 full device runs in a row, each step under 33 ms | Decided (2026-10-20) |
| D-80 | Where the allocation test of the spatial grid runs | The test in `RenderingTests` on the iPad | Decided (2026-10-20) |
| D-81 | Text renderer: "Core Text texture cache" in plan.md or the glyph atlas of D-29 | Glyph atlas. plan.md and architecture.md section 3 change their words. | Decided (2026-10-20) |
| D-82 | Text and the eraser mask | A second channel: `.rg8Unorm` committed textures, ink in red, text in green | Decided (2026-10-20) |
| D-83 | Size of a text box | Width from the longest line up to 640 canvas points, then wrap. Nothing stored. | Decided (2026-10-20) |
| D-84 | Who lays out the text, and characters that SF Mono lacks | Core Text layout in `Rendering` with the attributes of the edit view | Decided (2026-10-20) |
| D-85 | Scale of the edit view | Font size 17 times the zoom, a scale transform only during a pinch | Decided (2026-10-20) |
| D-86 | Undo and redo during a text edit | One step per edit. During an edit, undo and redo act on the text view. | Decided (2026-10-20) |
| D-87 | The text tool in the palette, and the tool change of D-70 | A third tool. A tool change ends an edit at once. The tool stays text. | Decided (2026-10-20) |
| D-88 | Memory bound of text in the undo history | Each held code point counts as one point of the budgets of D-76 | Decided (2026-10-20) |
| D-89 | Delete of a text box through a long-press menu | A long-press menu with "Delete", and a requirement in product-spec.md | Decided (2026-10-20) |
| D-90 | The test of M5 acceptance 1 (Scribble) | A device test of the conditions of Scribble, and a manual test as the pass | Decided (2026-10-20) |
| D-91 | The pass rule of M5 acceptance 2 | Lit-pixel bounds and profiles of each line match within 1 pixel | Decided (2026-10-20) |
| D-92 | The open and the memory of the D-56 canvas with text pass their targets | Remove the extra peak at the open, and lay out the text after the first frame | Decided (2026-10-21) |
| D-93 | The memory of the open with text after D-92 | Correct the test, keep the second channel, target 380 MB on the 11-inch iPad | Decided (2026-10-21) |
| D-94 | Late frames of the zoom over the D-56 text in full device runs | Accept at most 2 late frames in a full run for M5. Glyph buffers on the GPU in a later milestone. | Decided (2026-10-21) |
| D-95 | What a level of the card tree is (CARD-09) | The root canvas is level 0, a path holds at most 32 cards | Decided (2026-10-21) |
| D-96 | Where the renderer draws cards | In the green channel of the committed textures, with the text | Decided (2026-10-21) |
| D-97 | Source of the card previews | A gray PNG per child canvas in `Caches`, written when you leave the child | Decided (2026-10-21) |
| D-98 | Open and leave a card without a visible jump | The card covers the screen, the parent layers fade, and the child replaces the preview with a crossfade | Decided (2026-10-21) |
| D-99 | Camera of a canvas: standard zoom or the stored camera | Standard zoom at an open by tap or up button, stored camera at launch and at a workspace switch | Decided (2026-10-21) |
| D-100 | Double tap on a card and the single tap on a text box | Replaced by D-115 | Replaced (2026-10-22) |
| D-101 | Size, place, and title of a new card | Replaced by D-117 (place) and D-118 (size). No title stays. | Replaced (2026-10-22) |
| D-102 | "Resize" in UNDO-03 | No card resize in version 1 | Decided (2026-10-21) |
| D-103 | The card commands and the node commands | `AddCard`, `RenameCard`, and a node value in `MoveNode` and `DeleteNode` | Decided (2026-10-21) |
| D-104 | Threshold of the pinch-out exit (CARD-05) | Test the threshold on the zoom of the fingers, start value 0.6 | Decided (2026-10-21) |
| D-105 | When the GPU glyph buffers of D-94 come | After M6, in M10 | Decided (2026-10-21) |
| D-106 | Color of the canvas | RGB(24, 24, 24), `#181818`, instead of black | Decided (2026-10-21) |
| D-107 | PNG code and the owner of the preview files | ImageIO in `Rendering` for the PNG bytes, `PreviewStore` in `Persistence` for the files | Decided (2026-10-21) |
| D-108 | The fade of the parent during the open | The whole parent composite fades, and the opened card draws on top | Decided (2026-10-21) |
| D-109 | The image of the parent during a leave | A frozen copy of the last parent frame, else a load of the parent below `minZoom` or at the up button | Decided (2026-10-21) |
| D-110 | The memory peak of a transition | The parent frees its committed textures at the start of the animation. A transition budget from a measure. | Decided (2026-10-21) |
| D-111 | The events that write a preview | Up button, pinch-out, workspace switch, and the move to the background | Decided (2026-10-21) |
| D-112 | A path that names a deleted card | Cut the path before the first card that is not valid | Decided (2026-10-21) |
| D-113 | What "an empty part of the canvas" is | No card and no text box under the finger. Ink does not count. | Decided (2026-10-21) |
| D-114 | Snapshot tests of the card menu and the rename alert | Test the content, and compare pixel snapshots of the menu and the alert too | Decided (2026-10-22) |
| D-115 | How a card opens | A single finger tap. Replaces the double tap of D-09 and D-100. | Decided (2026-10-22) |
| D-116 | The body of a card | A light gray fill, as in Allume. Changes "no fill" of D-96. | Decided (2026-10-22) |
| D-117 | How a new card comes | A card button next to the tool button. A drag places the pending card. The long press goes. | Decided (2026-10-22) |
| D-118 | The size of a new card | 320 by 224 canvas points | Decided (2026-10-22) |
| D-119 | No zoom inside a card | A canvas inside a card has the zoom range 1...1. A pinch-out there only drives the exit. | Decided (2026-10-22) |
| D-120 | Where the coverage check of TEST-02 runs | A separate target `make coverage`, named in the pull request checklist | Decided (2026-10-22) |
| D-121 | The render thread computes the camera of a card flight | Yes, from the closed form of the spring. The main thread keeps its camera for the logic. | Decided (2026-10-22) |
| D-122 | The renderer gets the change of a step before the model step | Yes, for `EraseStrokes` and `AddStroke`, with the reverse change if the model step throws | Decided (2026-10-22) |
| D-123 | A pending card at a leave | It joins the canvas where it shows, with one undo step | Decided (2026-10-22) |
| D-124 | The card menu snapshots as an XCTest class | Accepted exception to TEST-01 | Decided (2026-10-22) |
| D-125 | The accepted late frame of the empty card in `make check` | An expected failure that is not strict on that one check. A trace with Instruments in M10. | Decided (2026-10-22) |
| D-126 | Where the hover dot draws | A `CAShapeLayer` above the live `PKCanvasView`, not a Metal pass | Decided (2026-10-22) |
| D-127 | The hover shadow of PencilKit | A check on the device at the start of M7. If the shadow shows, accept it and keep the dot. | Decided (2026-10-22) |
| D-128 | The shape of the hover dot and when it shows | A gray dot for the pen and the text tool, the eraser circle for the eraser, hidden when "Show Hover Preview" is off | Decided (2026-10-22) |
| D-129 | The pencils of the M7 tests | Apple Pencil Pro only. Acceptance 3 runs with double tap and squeeze set to "Ignore". | Decided (2026-10-22) |
| D-130 | The double-tap settings that switch the tool | "Switch to eraser" and "Switch to previous tool" only. Replaces the rule of D-07. | Decided (2026-10-22) |
| D-131 | The findings of the review before M7 | Three fixes in phase 0 of M7, one in M7, the rest in M10 | Decided (2026-10-22) |
| D-132 | Warnings that `-warnings-as-errors` does not stop | Recommendation: `make build` fails on any warning line in the build output | Open |
| D-133 | The eraser circle of the hover dot: an outline or a filled disc | An outline ring with a line width token | Decided (2026-10-22) |
| D-134 | The measure of the frames in task 3.1 of M7 | The frames of the canvas screen in `ZoomFrameAllocationTests` decide. The `dense 20k zoom` loop is recorded only. | Decided (2026-10-23) |
| D-135 | A pencil down during a pinch past a zoom limit | The camera holds during the stroke and springs back after the lift | Decided (2026-10-23) |
| D-136 | Late frames at the start of card flights in full runs | Trace the late frame now, before M7 closes | Decided (2026-10-23) |
| D-137 | The wiring of new textures in the first frames of a leave | The late-frame checks of the leaves become expected failures that are not strict. M10 traces the rest. | Decided again (2026-10-23) |
| D-138 | The input of the PDF exporter | `CanvasContent`. The name `CanvasSnapshot` goes. | Decided (2026-10-23) |
| D-139 | The API that writes the PDF | A Core Graphics PDF context, not `UIGraphicsPDFRenderer` | Decided (2026-10-23) |
| D-140 | The text layout of the PDF | `TextLayout` of `Rendering` gives the font and the lines. Export draws each line with `CTLineDraw`. | Decided (2026-10-23) |
| D-141 | The page bounds of the PDF | A function in `Export`: strokes and full text boxes, no cards. `contentBounds` stays. | Decided (2026-10-23) |
| D-142 | An empty canvas, emoji, and pages over 14,400 points | A message and no PDF. Emoji as the system draws them. A uniform scale of the whole page. | Decided (2026-10-23) |
| D-143 | The file name of the shared PDF | The title of the card or of the workspace, through `NSItemProvider.suggestedName` | Decided (2026-10-23) |
| D-144 | A budget for the time and the memory of an export | D-56 at most 8.5 s, 200,000 handwriting strokes at most 17 s, checked by `ExportPerformanceTests`. The memory has no budget (D-145). | Decided again (2026-10-24) |
| D-145 | The memory measure of an export in a full run | Time budgets only. The test records the memory and does not fail on it. | Decided (2026-10-24) |
| D-146 | The checkpoint of the library database | No automatic checkpoint, a passive checkpoint on a second connection at 1,000 pages, and a checkpoint on the write connection at 8,000 pages | Decided (2026-10-24) |

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

- Replaced by D-130 on 2026-10-22: only "Switch to eraser" and "Switch to previous tool" switch the tool.
- Decided by the product owner on 2026-10-17: the recommendation.
- The request says that double tap switches between pen and eraser. Apple's guidelines say that apps must honor the user's choice in Settings.
- Recommendation: if the setting is "Ignore", do nothing. For every other value, switch between pen and eraser.
- Doubt: a user who chose "Switch to previous tool" can expect a switch back from text to the pen. The recommendation does this, because text then goes to the pen.

### D-08 How to create a card

- Decided by the product owner on 2026-10-17: option (a).
- The tool list is pen, eraser, and text only. A card needs a way in.
- Options: (a) long press on empty canvas, then "New card" in a menu. (b) a fourth tool. (c) draw a rectangle with the pencil and convert it.
- Recommendation: (a). It keeps the tool list at three.
- Replaced by D-117 on 2026-10-22: a card button in the chrome makes a card. The tool list stays at three.
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

- Decided by the product owner on 2026-10-20: option (a), with the bound of 210,000 strokes.
- Raised by M4 task 3.3 on 2026-10-19.
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

- Decided by the product owner on 2026-10-20: option (a).
- Raised by M4 task 3.8 on 2026-10-19.
- D-69 runs the clock from the pencil lift, or from the undo or redo call, to the end of the first frame that shows the result. The budget is 16 ms per step. The test takes the presented callback of that frame as its end.
- On the iPad Pro 11-inch (M4) in Release, an empty change takes 13 to 16 ms from the call to its presented callback. The frame loop sleeps when idle, so a change waits for the next display frame. With a frame latency of 2 (architecture.md section 5.1), the frame shows about two display frames later. Thus the pipeline alone uses the whole budget, and no step with work can pass.
- The steps after the fixes of task 3.8, medians of 5 rounds: erase 37.5 ms, undo 29.6 ms, redo 29.8 ms. The work in them: the main thread takes 24 to 27 ms for an erase and 6 to 10 ms for an undo or a redo. The render thread takes 6 to 14 ms of CPU and 1 to 3 ms of GPU for the frame of the change.
- Options:
  - (a) End the clock when the GPU completes the first frame that holds the change, not at its presentation. The budget of 16 ms then covers the work of the main thread, the render thread, and the GPU, and the wait for the display frame. The pipeline latency stays covered by the pen latency budget of FEEL-01.
  - (b) Keep the presented end and raise the budget to the pipeline floor plus 16 ms, about 32 ms.
  - (c) Keep D-69 as written. The acceptance then cannot pass on this iPad.
- Recommendation: (a). It measures the work that the code controls. The erase then still needs a faster split, about 14 ms on the iPad today. Undo and redo are close.
- Effect: the clock of acceptance 2 ends when the GPU completes the first frame that holds the change. The renderer reports this event to the canvas.

### D-75 M4 acceptance 2 still misses 16 ms

- Decided by the product owner on 2026-10-20: option (b).
- Raised by M4 task 3.8 on 2026-10-20.
- With the clock of D-74, an empty change takes 7.9 ms (median) from the call to the GPU end of its frame. The frame loop sleeps when idle, so a change waits for the next display frame of 8.3 ms at 120 Hz.
- After the optimizations of task 3.8, the steps take these times on the iPad Pro 11-inch (M4) in Release, medians of 5 rounds: erase 28.1 ms, undo 27.6 ms, redo 24.8 ms. The slowest steps take 32.0, 31.4, and 28.3 ms.
- The work in them: the main thread takes 13 to 15 ms for an erase and 5 to 8 ms for an undo or a redo. The rest is the wait for the display frame and the CPU of the render thread for the change of the store, about 9 to 12 ms.
- Options:
  - (a) Continue the optimization. The next steps: the renderer hides and shows strokes instead of a removal and a new add at an undo and a redo, and the content changes with fewer dictionary operations. The estimate is 13 to 18 ms for undo and redo and about 22 ms for the erase. The erase cannot reach 16 ms while its split takes 13 ms on the main thread and the frame waits up to 8 ms.
  - (b) Accept a budget of 33 ms per step for M4, four display frames at 120 Hz. All three steps pass it today. Keep 16 ms as a goal for a later milestone.
  - (c) Keep 16 ms. M4 then stays open.
- Recommendation: (b). An erase of 1,000 strokes in one gesture is rare, and the eraser mask shows the result at once while the pencil moves (D-66).
- Effect: M4 acceptance 2 has a budget of 33 ms per step. The goal of 16 ms moves to a later milestone.

### D-76 A memory bound for the undo history

- Decided by the product owner on 2026-10-20: option (a), with the example values.
- Raised by the M4 review on 2026-10-20 ([m4-fix-plan.md](m4-fix-plan.md) M-01 and M-02).
- `History` keeps at most 500 steps, but it has no memory bound. A step holds the `Stroke` values of the strokes it removes, and their points live only in the history. `CanvasSessions` keeps the history of up to 1,000 canvases.
- Measured on a Mac: 500 steps, each an erase of 1,000 whole strokes of 300 points, take 2,519 MB. That is about 16.8 bytes per point. The session erase records take about 192 bytes each, and the records of dropped steps stay.
- Options:
  - (a) Add a point budget per canvas and a point budget for all sessions. Past a budget, the oldest steps go first. For example, 4,000,000 points per canvas (about 67 MB) and 16,000,000 points for all sessions (about 270 MB).
  - (b) Keep the step bound of 500, and keep fewer sessions, for example 8, with the least recently used one dropped first.
  - (c) No change. Normal use stays small, but a worst case can make iPadOS stop the app.
- Recommendation: (a). It bounds the memory and keeps many short steps.
- Effect: `Limits` gets a budget of 4,000,000 points for the history of one canvas and 16,000,000 points for the histories of all sessions. Past a budget, `History` drops the oldest steps, and the session erase records of their strokes go with them.

### D-77 Snapshot tests while the simulator is banned

- Decided by the product owner on 2026-10-20: option (b).
- Raised by the M4 review on 2026-10-20 ([m4-fix-plan.md](m4-fix-plan.md) section 2.1).
- Learned rule 1 of `AGENTS.md` bans the simulator. The Rendering snapshot tests run only as package tests on a simulator, and the SwiftUI snapshot tests skip on the device (D-59). None of them ran since 2026-10-19, and the redraw changed after the last reference images. TEST-07 needs them, and M5 acceptance 2 is a snapshot test.
- Options:
  - (a) Allow the simulator for the snapshot tests only, as an exception of learned rule 1. `make snapshots` and the Rendering package tests use it.
  - (b) Move the snapshot tests into `PointerDeviceTests`, put the reference images into its bundle, and make the reference images again on the iPad.
  - (c) No snapshot tests until M10.
- Recommendation: (b). It tests the real GPU of the target device and keeps learned rule 1. The cost is one new set of reference images.
- Effect: the Rendering and SwiftUI snapshot tests run in `PointerDeviceTests` on the iPad and compare against reference images in the test bundle. This replaces the skip on the device of D-59. `make snapshots` and `make test` use the iPad. Learned rule 1 stays.

### D-78 When the eraser mask texture exists

- Decided by the product owner on 2026-10-20: option (c).
- Raised by the M4 review on 2026-10-20 ([m4-fix-plan.md](m4-fix-plan.md) M-06).
- The mask texture of D-66 always exists, also when nobody erases. It takes 16.1 MB on the 11-inch iPad and 22.7 MB on the 13-inch iPad, computed from the size of the committed texture. architecture.md section 5.2 does not count it.
- Options:
  - (a) Keep the texture always, and count it in architecture.md.
  - (b) Make the texture at the first eraser sample, and drop it at the end of the gesture. The first sample then waits for the allocation.
  - (c) Make the texture when the eraser becomes the tool, and drop it when another tool becomes the tool.
- Recommendation: (c). No gesture waits for the allocation, and the memory is used only while the eraser is the tool.
- Effect: the renderer makes the mask texture when the eraser becomes the tool and drops it when another tool becomes the tool. architecture.md section 5.2 gives the memory of the textures with and without the mask.

### D-79 The pass rule of M4 acceptance 2 on the device

- Decided by the product owner on 2026-10-20: option (a).
- Raised by the M4 review on 2026-10-20 ([m4-fix-plan.md](m4-fix-plan.md) section 2.1).
- Acceptance 2 failed in 2 of 4 runs on 2026-10-20, by 0.37 ms and 1.54 ms. One pass of the test does not show that the code meets the budget.
- Options:
  - (a) The slowest step of each kind is under 33 ms in 5 full runs of `PointerDeviceTests` in a row.
  - (b) The median of each kind is under 33 ms in 3 full runs, and no step takes 40 ms or more.
  - (c) One full run passes, as in M4 so far.
- Recommendation: (a). It asks for a margin and shows a noisy result.
- Effect: M4 acceptance 2 passes only when the slowest erase, undo, and redo are each under 33 ms in 5 full runs of `PointerDeviceTests` in a row. A failed run starts the count again.

### D-80 Where the allocation test of the spatial grid runs

- Decided by the product owner on 2026-10-20: option (a).
- Raised by task 3.2 of [m4-fix-plan.md](m4-fix-plan.md) on 2026-10-20.
- The "Done when" target of task 3.2 asks for "1,000 removals make 0 allocations in a Tier A test". `SpatialGrid` is in `Geometry`, a Tier A package. An exact allocation count needs the `malloc_logger` hook of `AllocationCounter+Unsafe.swift`, which uses `UnsafeMutableRawPointer` and `dlsym`. SAFE-09 and the lint rule `safe_09_unsafe_types` allow unsafe pointers only in `*+Unsafe.swift` files of `Rendering` and `Export`, and in the SQLite wrapper of `Persistence`. The counters of `malloc_zone_statistics` need no unsafe type in the source, but they count the live blocks, not the allocations, so a removal that allocates and frees shows 0.
- Options:
  - (a) Run the test of the grid in `RenderingTests`, where `AllocationCounter` lives. It runs on the iPad in `PointerDeviceTests`, with the `SpatialGrid<Int>` of the renderer. The Tier A tests keep the timing of the removal and the query.
  - (b) Allow one `AllocationCounter+Unsafe.swift` in `GeometryTests`, with a new exclusion in `safe_09_unsafe_types`. This changes a lint rule of SAFE-09 (AGENT-03).
  - (c) Count the live blocks with `malloc_zone_statistics` in a Tier A test. This misses an allocation that is freed in the same removal.
- Recommendation: (a). It counts each allocation and changes no rule. The grid of the renderer is the grid that the target is about.
- Effect: `GridAllocationTests` in `RenderingTests` is the allocation test of the grid. The Tier A tests keep no allocation counter, and SAFE-09 stays as it is.

### D-81 Text renderer: "Core Text texture cache" or glyph atlas

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20 ([m5-plan.md](m5-plan.md) section 1, item 11).
- plan.md M5 lists a "Core Text texture cache", and architecture.md section 3 lists a "text texture cache" in `Rendering`. D-29 decided a glyph atlas on 2026-10-18, and architecture.md section 5.4 describes the atlas. The documents conflict.
- Options:
  - (a) The glyph atlas of D-29. Core Text draws each glyph once into an atlas per scale. plan.md M5 and architecture.md section 3 change their words to "glyph atlas".
  - (b) A texture per text box, which Core Text draws. D-29 rejected it: a text box of 10,000 characters at zoom 8 passes the Metal texture limit of 16,384 pixels.
- Recommendation: (a). It is the decided design, and only the words of two documents change.
- Effect: tasks 0.1 and 2.2 of [m5-plan.md](m5-plan.md).

### D-82 Text and the eraser mask

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20, from effect 3 of D-66.
- The composite pass multiplies the coverage of the committed texture by `1 - mask` (`compositeMaskedFragment`). The eraser removes ink only (TOOL-04). Text in the same channel thus vanishes under the eraser during the gesture and comes back at the lift.
- The committed textures use `.r8Unorm`. Two textures take 32 MB on the 11-inch iPad and 45 MB on the 13-inch iPad (architecture.md section 5.2).
- Options:
  - (a) A second channel. The committed textures become `.rg8Unorm`: ink in red, text in green. The ink pipeline writes red only, and the text pipeline writes green only. The composite takes the larger of `red * (1 - mask)` and `green`. A build draws both. The redraw of an erase clears red only. The textures take 16.1 MB more each on the 11-inch iPad, so 32 MB more in total, and 45 MB more on the 13-inch iPad.
  - (b) A separate pair of `.r8Unorm` text textures. It takes the same memory as (a), and it needs a second build state and a second redraw path.
  - (c) Text stays in the one channel. While an eraser gesture runs, a pass draws the text boxes that touch the eraser path on top of the masked composite. At the lift, the redraw of the area also draws the text in it. No memory cost, but each eraser frame draws text, and the eraser frame budget (3 ms CPU, 4 ms GPU) covers more work.
- Recommendation: (a). It keeps one build and one redraw path, and it leaves the eraser frame as it is.
- Doubt: the open of the D-56 canvas took 235 to 253 MB in [m4-fix-plan.md](m4-fix-plan.md) section 5.3, against a budget of 300 MB. With 32 MB more, the margin is about 15 MB at the top value. If the memory test fails, (c) is the fallback.
- Effect: tasks 2.3 and 2.4 of [m5-plan.md](m5-plan.md), and architecture.md section 5.2.

### D-83 Size of a text box

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- architecture.md section 7 says: the width grows with the longest line up to 640 canvas points, longer lines wrap, and the height grows with the text. data-model.md section 7.3 stores no width and no height. UNDO-03 lists "resize" as an undoable action, and architecture.md section 8 lists a `ResizeTextBox` command. The documents do not agree on a size that the user sets.
- Options:
  - (a) The rule of architecture.md section 7. Nothing is stored. `ResizeTextBox` leaves architecture.md section 8. "Resize" in UNDO-03 stays for cards in M6.
  - (b) A fixed width of 640 canvas points. The height grows with the text. A short label then has a wide edit view and a wide tap area.
  - (c) The user sets the width with a handle. The `text_box` table gets a `width` column: schema version 2, a migration, and a fixture (GIT-04). `ResizeTextBox` and a handle come in M5.
- Recommendation: (a). It needs no schema change, and a label stays as small as its text.
- Doubt: a label that must wrap narrower than 640 points needs a manual line break.
- Effect: tasks 1.1, 2.1, and 3.2 of [m5-plan.md](m5-plan.md).

### D-84 Who lays out the text, and characters that SF Mono lacks

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- D-29 says that each character is one quad from the atlas, because SF Mono is monospaced. SF Mono has no glyphs for emoji, for Chinese, Japanese, and Korean characters, and for many symbols. For these, Core Text and TextKit use fallback fonts with other advances. A Chinese character is about twice as wide as a SF Mono character.
- The edit view (`UITextView`, TextKit 2) lays out the text with its own engine. M5 acceptance 2 needs the canvas and the edit view to match within one pixel. ARCH-03 keeps Core Text out of the Tier A packages.
- Options:
  - (a) Core Text lays out the text in `Rendering` (`CTTypesetter`), with the attributes of the edit view: SF Mono, a fixed line height, and word wrap at the width of D-83. The atlas keys each glyph by font and glyph ID, so fallback glyphs work. An emoji draws as a white shape, because the canvas has no color. `Rendering` gives the box size to the canvas, and later to the export.
  - (b) A grid layout in `Model` (Tier A). Each character takes one cell of the SF Mono advance, and lines wrap at the last whole cell. The layout is pure and runs on the Mac. But the edit view lays out wide characters and fallback fonts in another way. Thus each character outside SF Mono moves at the end of an edit.
  - (c) As (b), and the text box refuses characters that SF Mono lacks, with a message. Scribble and paste then fail for these characters.
- Recommendation: (a). It matches the edit view for every character, and Core Text is the layout engine under TextKit.
- Doubt: Core Text layout of the 5,000 text boxes of D-56 at the open costs time against the budget of 300 ms. Task 2.1 measures it. If it is too slow, the layout runs only for the boxes near the camera.
- Effect: tasks 1.1, 2.1, 2.2, and 4.2 of [m5-plan.md](m5-plan.md).

### D-85 Scale of the edit view

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- architecture.md section 5.4 says that the `UITextView` has "a transform that matches the camera". A scale transform scales the layer that the text view drew. At zoom 4, the text view then shows text drawn for zoom 1, four times larger and soft. The atlas draws at the power of two above the zoom, so the canvas stays sharp.
- Options:
  - (a) A scale transform, as architecture.md section 5.4 says.
  - (b) The font size is 17 points times the zoom, and the frame is in view space, without a scale transform. A camera change moves the view. A zoom change lays out the text again. During a pinch, the view uses a scale transform from its last layout. At the end of the pinch, it lays out the text at the new size.
  - (c) A scale transform, with the `contentScaleFactor` of the text view and its subviews set to the display scale times the zoom. Apple does not document this for the text layers of TextKit 2.
- Recommendation: (b). The text stays sharp at each zoom, and it uses only documented API.
- Doubt: a pinch during an edit shows soft text until the pinch ends.
- Effect: tasks 3.2 and 4.2 of [m5-plan.md](m5-plan.md), and architecture.md section 5.4.

### D-86 Undo and redo during a text edit

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- architecture.md section 7 says that the text view has its own undo during an edit. The end of an edit records one `EditText` command. Section 8 says that the undo and redo buttons go to the text view during an edit. An empty new text box records no command.
- No document says what a new box with text records, or what an edit records that leaves an existing box empty. `TextBox` needs at least one code point.
- Options:
  - (a) One step per edit. A new box with text records one `AddTextBox`. A changed box records one `EditText`. An existing box that ends empty records one `DeleteNode`. An unchanged box records nothing. The buttons, the palette, and Command-Z act on the undo manager of the text view during the edit. If that undo manager has no step, they are off.
  - (b) One step per change. Each typed character or Scribble word is a step of `History`. The 500 steps of `Limits.maxHistoryDepth` fill fast, and each step sends a row.
  - (c) As (a), but during the edit, the buttons end the edit first and then act on the history of the canvas.
- Recommendation: (a). It follows architecture.md sections 7 and 8, and one edit is one step that the user can undo.
- Effect: tasks 1.2 and 3.3 of [m5-plan.md](m5-plan.md), and architecture.md sections 7 and 8.

### D-87 The text tool in the palette, and the tool change of D-70

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20, from D-63, D-64, and D-70.
- D-63 says that the text entry of the palette comes with the text tool in M5. D-70 says that a tool change takes effect at the next pencil down. architecture.md section 7 says that a tool change ends an edit. An edit is not a pencil touch. Thus D-70 does not say when an edit ends.
- The questions, each with its recommendation:
  1. The palette and the current-tool button get a third tool, text, with the SF Symbol `character.cursor.ibeam`. Recommendation: yes.
  2. A tool change during an edit: (a) ends the edit at once, or (b) ends it at the next pencil down. Recommendation: (a), because the user sees the change of tool and expects the edit to end.
  3. After a pencil tap makes a box, the tool: (a) stays text, or (b) goes back to the pen. Recommendation: (a), so that the user can make several labels in a row.
  4. With the text tool, a pencil tap on an existing box: (a) starts its edit, or (b) makes a new box on top of it. Recommendation: (a).
  5. With the text tool, a pencil movement that is not a tap: (a) does nothing, or (b) makes a box where the user writes, through `UIIndirectScribbleInteraction`. Recommendation: (a). TOOL-05 lists a tap only, and (b) adds a feature (AGENT-02).
- Effect: tasks 3.1 and 3.3 of [m5-plan.md](m5-plan.md), and architecture.md sections 4.5 and 7.

### D-88 Memory bound of text in the undo history

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20, from D-76.
- D-76 bounds the history by control points: 4,000,000 per canvas and 16,000,000 for all sessions. A text step holds no points. An `EditText` step holds two texts of up to 10,000 code points each, so up to about 80 KB. 500 steps take about 40 MB on one canvas. The sessions keep up to 1,000 canvases, so the history of text has no bound.
- Options:
  - (a) Count each code point of a held text as one point of the budgets of D-76. A point takes about 16.8 bytes and a code point at most 4, so the count is safe.
  - (b) A separate budget for text, for example 10,000,000 code points for all sessions.
  - (c) No bound. Normal use stays small, but a worst case can make iPadOS stop the app.
- Recommendation: (a). It needs no new limit, and one rule drops the oldest steps.
- Effect: task 1.3 of [m5-plan.md](m5-plan.md), and architecture.md section 8.

### D-89 Delete of a text box through a long-press menu

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20 ([m5-plan.md](m5-plan.md) section 1, item 11).
- architecture.md section 4.7 gives a long press on a text box a context menu with "Delete". product-spec.md has no requirement for this menu: CARD-08 covers cards only, and UNDO-03 lists "delete card". In architecture.md section 7, an edit that leaves a text box empty deletes it. AGENT-02 bans features that the specification does not list.
- Options:
  - (a) In M5, only an edit that leaves a text box empty deletes it. A long press without a drag does nothing on a text box. architecture.md section 4.7 drops "Delete" for text boxes.
  - (b) A long press without a drag opens a menu with "Delete", as architecture.md section 4.7 says. product-spec.md gets a requirement for it, and UNDO-03 gets "delete text box".
  - (c) As (b), but the menu comes in M6 with the menu of the cards.
- Recommendation: (b). M5 already recognizes the long press for the move of CARD-07, and `DeleteNode` already exists for an empty edit. Without the menu, a user must select all text and delete it to remove a box.
- Effect: task 3.4 of [m5-plan.md](m5-plan.md), and product-spec.md.

### D-90 The test of M5 acceptance 1 (Scribble)

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- M5 acceptance 1 says: "Scribble writes into a text box." No public API lets a test write with a pencil or give handwriting to Scribble. A UI test cannot draw pencil strokes either. Learned rule 1 of `AGENTS.md` bans the simulator.
- Options:
  - (a) A device test in `PointerDeviceTests` of the conditions that Scribble needs. With the text tool, the edit view is an editable `UITextView` and the first responder. The drawing gesture of PencilKit is off. `PencilTouchObserver` refuses touches on the edit view. No delegate of the edit view refuses Scribble. The test then inserts text through `UITextInput`, the protocol that Scribble uses for its result. At the end of the edit, the text is in the content, the rows, and the canvas. The product owner writes with the pencil into a text box on the iPad, and this manual test is the pass.
  - (b) The manual test only.
- Recommendation: (a). The device test catches a change that breaks Scribble, and the manual test shows the real handwriting.
- Effect: task 4.1 of [m5-plan.md](m5-plan.md).

### D-91 The pass rule of M5 acceptance 2

- Decided by the product owner on 2026-10-20: the recommendation. Raised by the M5 plan on 2026-10-20.
- M5 acceptance 2 compares text on the canvas with text in edit mode at zoom 0.5, 1, and 4. They must "line up to within one pixel". The acceptance does not say what the test measures.
- The canvas draws atlas glyphs at a power-of-two scale and samples them down. The edit view draws with TextKit at the exact size. Thus the anti-aliased edges differ by design. They differ also for glyphs at the same place.
- Options:
  - (a) A lit pixel has a coverage of 50 % or more. For each line of text, the bounds of the lit pixels of the two images differ by at most 1 pixel on each side. A column profile is the sum of the coverage in each pixel column. The column profiles and the row profiles of the two images match best at an offset of at most 1 pixel. Each image also has a reference PNG (TEST-07).
  - (b) The center of each glyph differs by at most 1 pixel. The test must then find each glyph in the two images.
  - (c) A pixel comparison with the tolerance of TEST-07, 0.5 % of the pixels. It measures the edges, not the place, so it can fail for text at the same place.
- Recommendation: (a). It measures the place of each line in both directions, and it does not depend on the edge shape.
- Effect: task 4.2 of [m5-plan.md](m5-plan.md).

### D-92 The open and the memory of the D-56 canvas with text

- Decided by the product owner on 2026-10-21: options (b) and (d). Raised by task 2.3 of [m5-plan.md](m5-plan.md) on 2026-10-20.
- The D-56 canvas holds 5,000 text boxes of 200 characters. Before M5, nothing drew them. With the text of M5, two tests on the iPad Pro 11-inch (M4) in Release fail their targets:

| Measure | Target | Baseline (section 5.1 of the plan) | M5 now |
|---|---|---|---|
| Memory of the open, peak | under 300 MB | held 253 MB, peak 284 MB | held 282 MB, peak 314 MB |
| Open to the first frame, median | under 300 ms, at most 10 % over the baseline (263 ms) | 238.9 ms | 273.6 ms, slowest 279.4 ms |

- The held memory grew by 29 MB. The second texture channel of D-82 adds 32 MB on the 11-inch iPad, so it is almost all of the growth. A glyph of the layout now takes 9 bytes. With 25 bytes, the open held 311 MB.
- The peak is about 31 MB over the held memory, in the baseline and now. The test asserts the peak.
- The open grew by about 35 ms. The layout of the 5,000 boxes takes 60 ms on one thread. It now runs in up to 8 chunks on several threads at the load.
- Options for the memory:
  - (a) Change to the fallback of D-82, option (c): text in the one channel of the committed texture, and a text pass over the masked composite during an eraser gesture. It saves the 32 MB, but the eraser frame draws text, and the redraw of an erase draws the text in its area.
  - (b) Keep the second channel, and remove the peak of about 31 MB over the held memory at the open. The cause is not yet found. It is in the baseline too, so it is outside the text work.
  - (c) Raise the memory target of the open to 320 MB.
- Options for the open:
  - (d) Lay out the text after the first frame with the strokes. The open then keeps its time, and the text shows a few frames later.
  - (e) Accept 273.6 ms. It is under the budget of 300 ms, but 14.5 % over the baseline.
- Recommendation: (b) and (d). They keep the design of D-82 and the time of the open. If (b) cannot find the cause of the peak inside one task, (a).

### D-93 The memory of the open with text after D-92

- Decided by the product owner on 2026-10-21: option (b). Raised by task 2.3 of [m5-plan.md](m5-plan.md) on 2026-10-21.
- D-92 decided: remove the extra peak of the open, and lay out the text after the first frame. If the cause of the peak cannot be found, fall back to option (a) of D-92, the single channel of D-82 option (c).
- The layout after the first frame works. The open of the D-56 canvas takes 234.9 to 239.8 ms (median), against 238.9 ms in the baseline.
- The cause of the extra peak is not found. A probe showed one committed layer per renderer, so a second layer is not the cause. The peak is not in every run. Four runs of the open on the iPad Pro 11-inch (M4), after D-92:

| Run | Held | Peak |
|---|---|---|
| Memory test alone | 299 MB | 299 MB |
| Memory test alone | 283 MB | 283 MB |
| Memory test alone | 271 MB | 271 MB |
| Full run of `PointerDeviceTests` | 299 MB | 315 MB |

- The baseline had the extra peak in 2 of 3 full runs: held 252 to 254 MB, peak 254 to 284 MB. The held memory of one open varies by about 28 MB between runs.
- The fallback of D-92 saves the 32 MB of the second channel. Then the held memory is about 255 to 270 MB, and the peak with the extra 31 MB is about 285 to 300 MB. The fallback can still fail the target of 300 MB in a run with the extra peak.
- Research on 2026-10-21, on the iPad Pro 11-inch (M4) in Release:
  - A canvas holds three drawables of 16.1 MB each. Core Animation releases them about 1 second after the last frame, and makes them again at the next frame.
  - The test host app shows a canvas of its own in the same process. Its drawables come and go during a measure. A probe saw it release 50 MB in the 3 seconds before a load. Thus each memory and open measure of a canvas since M3 holds an error of up to about 50 MB, in either direction. The extra peak of D-92 is this error, not a cost of the D-56 canvas.
  - With a corrected test, the views of the host app leave the window, and the measure starts after 1.5 seconds of steady memory. The results then repeat within 3 MB. Three alternating runs of each build:

| Build | Memory of the open of D-56, held = peak | Open to the first frame, median |
|---|---|---|
| M4, commit beb3608 | 315, 312, 315 MB | 251.3, 251.7, 256.1 ms |
| M5 now | 347, 350, 347 MB | 246.1, 257.3, 247.0 ms |

  - The target of 300 MB thus fails also for M4. The passes of M3 and M4 (236 to 254 MB) come from the error of the test. M5 adds 32 to 35 MB: the second channel of D-82 (32.3 MB). The open of M5 is as fast as the open of M4.
  - The parts of the open, from the sizes in the code: the control points in `Model` take 96 MB, and the point arena about 48 to 55 MB. The committed textures take 64.6 MB (32.3 MB in one channel), and the drawables 48.4 MB. The glyph buffers and draw lists take 9.4 MB, and the text layouts about 9 MB.
  - On the 13-inch iPad, the textures and the drawables are larger by about 46 MB. The estimate there is about 395 MB for M5 and about 350 MB for M4. No 13-inch iPad was measured.
- Options:
  - (a) The fallback of D-92: text in the one channel, and a text pass during an eraser gesture. It saves 32 MB, so the open takes about 315 MB, and the target of 300 MB still fails.
  - (b) Keep the second channel. Correct the test as above, and set the target of the open of D-56 to 380 MB on the 11-inch iPad. That is the measured 350 MB plus about 8 %. Architecture.md section 12 and the test change.
  - (c) Keep the target of 300 MB and save about 50 MB elsewhere. A texture margin of 1.5 instead of 2 saves about 28 MB, with twice the builds of D-47. Less memory per control point in `Model` (16 bytes now) saves the rest. Both change decided designs (D-47, D-26), and the second changes the data model.
  - (d) Correct the test, and keep the target of 300 MB as a goal for a later milestone, as D-75 did for 16 ms. The test then fails until that milestone.
- Recommendation: (b). The test error is fixed in every case. The target of 300 MB was set before the measure was correct, and M4 already needs 315 MB. The second channel costs 32 MB and keeps the eraser and the text apart (D-82). The 13-inch iPad needs its own measure before a target there.

### D-94 Late frames of the zoom over the D-56 text in full device runs

- Decided by the product owner on 2026-10-21: the recommendation, option (a) for M5 and option (b) for a later milestone. Raised by task 5 of [m5-plan.md](m5-plan.md) on 2026-10-21.
- The target of task 2.4 is 120 fps and 0 late frames in the frame loop tests over the 5,000 text boxes of D-56.
- The close ran 5 full runs of `PointerDeviceTests` in a row on the iPad Pro 11-inch (M4). The zoom over the text had 0, 1, 1, 2, and 2 late frames of 478 (119.5 to 120.0 fps). The pan over the text had 0 late frames in each run. The six frame loop tests of M2 had 0 late frames in each run.
- Run alone, `FrameLoopTests` gave 0 late frames in the zoom over the text in 6 of 6 runs.
- The GPU time of a frame of the zoom over the text reaches 4.97 ms, against 2.86 ms without text. A glyph budget of 32,768 quads per build frame gave no measurable gain in alternating runs, so it is not kept.
- The pan over the text shows uncovered screen at the edge in 159 to 187 of 480 frames. A texture with about a million glyphs at zoom 0.25 takes several frames to build. The target does not hold this measure.
- Options:
  - (a) Accept at most 2 late frames of 478 for the zoom over the text in a full run. Keep 0 late frames as the target of a run of `FrameLoopTests` alone.
  - (b) Move the glyph quads of each box into a GPU buffer that a build reuses, as the strokes do with the point arena. A build then writes one draw entry per box, not one quad per glyph. This is a larger change to the renderer, and it can also reduce the uncovered frames of the pan.
  - (c) Keep the target. M5 then stays open until (b) or another change meets it.
- Recommendation: (a) for M5, and (b) as a task of a later milestone. The late frames show only next to other tests in the same process. The D-56 content holds a million glyphs, far more than normal notes.

### D-95 What a level of the card tree is

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- CARD-09 gives a limit of 32 levels. M6 acceptance 2 says: "A tree of 32 levels works. Level 33 is refused." No document says if the root canvas is level 0 or level 1.
- The code counts cards, not canvases. `DeviceState` takes a navigation path of at most 32 card IDs (`DeviceState.swift`, line 20). The 30-day purge walks 32 card levels below a workspace (`LibraryMaintenance.swift`, line 110). Thus the code allows the root canvas and 32 card canvases below it, 33 canvases in all.
- Options:
  - (a) The root canvas is level 0. A path holds at most 32 cards. "New card" on a canvas at depth 32 is refused with a message. The code needs no change. CARD-09 and acceptance 2 get this wording.
  - (b) The root canvas is level 1. A path holds at most 31 cards. `Limits.maxDepth` stays 32, and three places in the code and the SQL subtract one.
- Recommendation: (a). It matches the code and the stored format. Option (b) adds an off-by-one rule to three places.

### D-96 Where the renderer draws cards

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- architecture.md section 5.2 puts cards in the committed layer. Since D-82, the committed textures are `.rg8Unorm`: ink in red, text in green. The composite shows `max(red, green)` as white on black. Section 5.5 gives a card a gray border, a title, and a preview. D-16 puts cards below the ink.
- The memory of the D-56 open is 342 to 350 MB, against the target of 380 MB (D-93). The headroom is 30 to 38 MB.
- Measured on 2026-10-21 on the iPad Pro 11-inch (M4): a glyph quad of the text pass costs 17 ns of CPU. At zoom 0.25, the D-56 grid shows about 3,000 nodes. A card needs about 10 quads: the frame, the preview, and about 8 title glyphs. That is about 30,000 quads, or 0.5 ms of CPU.
- Options:
  - (a) A third channel: `.rgba8Unorm` committed textures, because Metal has no three-channel 8-bit format. Two more bytes per pixel add 64.6 MB on the 11-inch iPad. The open then takes about 410 MB, over the target.
  - (b) A card pass each frame, into the drawable before the composite. The composite then blends with `max`. It needs no texture memory, but it adds about 0.5 ms of CPU to each frame of a pan at zoom 0.25.
  - (c) Cards in the green channel of the committed textures, with the text. The border writes a gray coverage value (`DesignSystem.Color.cardBorder`), the title uses the glyph atlas, and the preview is sampled into the channel. A build and a redraw draw cards as they draw text. It needs no texture memory, and the 0.5 ms falls into the build budget of D-28, not into each frame. The eraser mask hides red only, so the eraser never hides a card (D-82).
- With (c), the order of D-16 still holds on the screen. All content is gray on black and the layers join with `max`, so the image is the same as cards drawn below the ink. This holds while a card has no opaque fill. CARD-02 and section 5.5 give it none.
- Recommendation: (c). It keeps the memory of D-93 and the frame cost of D-94.

### D-97 Source of the card previews

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- The documents give two designs. architecture.md section 5.5 and storage.md section 5, step 6 read the child canvases one level deep at the open and draw each preview. storage.md section 2 has a file cache, `Caches/Pointer/previews/<canvas-id>.png`, "rebuilt on demand".
- Measured on 2026-10-21 on the iPad Pro 11-inch (M4) in Release, with a temporary benchmark:

| Measure | Result |
|---|---|
| Load of 3,000 empty child canvases, one after another | 67.1 ms, 0.022 ms each |
| Load of 300 child canvases with 50 strokes of 300 points and 5 text boxes each | 53.3 ms, 0.178 ms each, 4.5 million points |
| Gray PNG, 128 by 89 pixels | 2,330 bytes, decode 0.107 ms |
| Gray PNG, 256 by 179 pixels | 4,308 bytes, decode 0.112 ms |
| Gray PNG, 512 by 358 pixels | 9,202 bytes, decode 0.193 ms |

- The control points take 16 bytes each in `Model` (D-93), so the 300 loaded children hold about 72 MB. That is twice the headroom of D-93. The D-56 canvas has 5,000 cards, so the load of the empty children alone adds about 110 ms to an open of about 250 ms.
- A child canvas changes only while it is on the screen, because the library lives on one device and has no sync (STO-01, product-spec.md section 4). Thus the app knows the moment when a preview gets old: when you leave the child. The one other change is a restore of M9, which must clear the folder of the previews.
- Options:
  - (a) Read the children one level deep at each open, as storage.md section 5 says.
  - (b) A gray 8-bit PNG per child canvas in `Caches/Pointer/previews/`. The app writes it when you leave the child. The renderer reads the files of the visible cards off the main actor, after the first frame, as the text of D-92 does. The decoded previews live in a cache with a byte budget, a start value of 8 MB. The size comes in steps of 128, 256, and 512 pixels, from the size of the card on the screen. If a file is missing, for example after the system cleared `Caches`, the app loads that one child off the main actor and draws its preview.
- Recommendation: (b). It holds no child content in memory and adds nothing to the open. A file takes 2 to 9 KB. 8 MB of decoded previews hold about 175 previews of 256 pixels or 700 of 128 pixels.

### D-98 Open and leave a card without a visible jump

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- M6 acceptance 1 checks the open and the leave of a card frame by frame. architecture.md section 6.2 animates the camera "so that the card frame fills the screen" and then swaps in the child canvas.
- Three jumps can show at the swap:
  1. The aspect ratio of a card differs from the screen. If the card fits the screen, the parent canvas shows beside it, and the child replaces that part at the swap.
  2. The ink and the text of the parent lie on top of the card (D-16). At the swap, the parts of them inside the card vanish.
  3. A preview is a small image (D-97). Scaled to the full screen, it is soft, and the first frame of the child is sharp.
- Measured: the open of the D-56 canvas takes 246 to 258 ms to the first frame (m5-plan.md section 5.3). The open animation takes 0.35 s.
- Options:
  - (a) Fit the card into the screen, and swap at the end.
  - (b) Cover the screen with the card. The preview shows the region of the child that the open camera shows, cut to the card. During the animation, the ink and the text of the parent fade out. The child loads during the animation. When its first frame is ready, it replaces the preview with a crossfade of 0.1 s.
  - (c) As (b), but each card has the aspect ratio of the screen, so the cover cuts nothing.
- The geometry of (b): the child opens at zoom 1 and shows W by H view points. At the end of the animation, the card of w by h parent points covers the screen with the scale k = max(W / w, H / h). The preview then shows the child region of w × k by h × k points around the center of the open camera.
- The leave is the open in reverse. The up button first moves the child camera to the camera of the open. The pinch-out exit of CARD-05 crossfades from the child image to the preview while the card shrinks.
- Recommendation: (b), together with the default size of D-101, which gives a new card the aspect of the screen. Option (c) blocks a resize for good (D-102).

### D-99 Camera of a canvas: standard zoom or the stored camera

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- CARD-03 opens a card at the standard zoom. architecture.md section 6.2 centers it on the content bounds of the child. CARD-04 shows the parent at the standard zoom, centered on the card. WS-04 opens the last workspace at the last camera.
- storage.md section 10 says: "A canvas reads its camera when it opens." D-53 stores a camera for each canvas. This conflicts with CARD-03 and CARD-04.
- Options:
  - (a) The stored camera at each open.
  - (b) The rules of CARD-03 and CARD-04 at an open by a double tap, the up button, or a pinch-out. The stored camera is used only at launch and at a workspace switch, for the deepest canvas of the stored path (WS-04). The store still writes the camera of each canvas, so the launch finds it.
- Recommendation: (b). The open animation of D-98 needs a known camera in the child, and (a) gives a different camera at each visit.

### D-100 Double tap on a card and the single tap on a text box

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- A finger tap on a text box starts its edit (TOOL-06). A finger double tap on a card opens it (D-09). A tap beside a box ends an edit.
- If a single-tap recognizer waits for a double-tap recognizer to fail, each single tap waits for the double-tap interval of the system. This review did not measure that interval on the iPad.
- `UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRequireFailureOf:)` lets the app set the wait for each recognition, not once for all taps.
- Options:
  - (a) The finger tap always waits for the double tap. Each edit starts later.
  - (b) The double tap begins only on a card that no text box covers. The finger tap waits for it only when the touch is on such a card. A tap on a text box starts its edit at once, as in M5.
- In both options, a single tap on a card ends an edit and does nothing else. A pencil tap with the text tool on a card makes a text box on the parent canvas, above the card (D-16).
- Recommendation: (b). It keeps the edit start of M5 and the keyboard fixes of commits c77cf46 and 477f4bc. The plan of M6 measures the delay of a tap on a card.

### D-101 Size, place, and title of a new card

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- CARD-01 makes a card with a long press on empty canvas and "New card". No document gives its size, its place, or its title. A card is at least 64 by 48 canvas points (data-model.md section 7.2). CARD-02 makes the title optional. The workspace selector renames with an alert that holds a text field (`WorkspaceSelectorView.swift`, line 40).
- Changed by D-117 on 2026-10-22: the size and the title stay. The card button places the new card with its center on the left edge of the screen, and a drag moves it into place.
- Changed by D-118 on 2026-10-22: a new card has the fixed size of 320 by 224 canvas points at each zoom.
- Options for the size:
  - (a) A fixed size in canvas points, for example 320 by 224. It looks tiny at zoom 0.25 and fills the screen at zoom 4.
  - (b) A quarter of the screen width at the current zoom, with the aspect of the screen. On the 11-inch iPad in landscape at zoom 1, that is about 299 by 209 points. At zoom 8, the minimum size of 64 by 48 sets the size.
- Recommendation: (b), centered on the point of the long press, without a title. "Rename" opens an alert with a text field, as the workspace rename does. The aspect of the screen lets the open of D-98 cut nothing.

### D-102 "Resize" in UNDO-03

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- UNDO-03 lists "resize" as an undoable action. D-83 took it away from text boxes. No CARD requirement and no gesture in architecture.md section 4.7 resize a card.
- The `card` table stores the whole frame, so a later resize needs no schema change (GIT-04).
- Options: (a) no card resize in version 1, and "resize" leaves UNDO-03. (b) a resize handle and a `ResizeCard` command in M6.
- Recommendation: (a). No requirement asks for it (AGENT-02), and it can come later without a migration.

### D-103 The card commands and the node commands

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- architecture.md section 8 lists `AddCard`, `MoveNode`, `DeleteNode`, and `RenameCard`. UNDO-03 says "create card". In M5, `MoveNode` and `DeleteNode` hold a `TextBox` only, and `CanvasContent` has the changes of text boxes only.
- Options:
  - (a) `AddCard` and `RenameCard` as new commands. `MoveNode` and `DeleteNode` hold a node value: a text box or a card. `CommandError` gets the card cases.
  - (b) Separate `MoveCard` and `DeleteCard` commands next to the commands of M5.
- Recommendation: (a). It matches architecture.md section 8. A delete of a card marks the card only, and the child content stays (D-18). A move to another parent is not in version 1, because no requirement asks for it. Thus the cycle check of data-model.md section 7.2 waits for that requirement.

### D-104 Threshold of the pinch-out exit

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- Changed by D-119 on 2026-10-22: a canvas inside a card shows only zoom 1, so the threshold is `exitZoomRatio` times zoom 1, and the pinch shows no zoom.
- architecture.md section 6.3 leaves a card when the fingers lift at a zoom under `minZoom * 0.7`. The camera shows the zoom with the rubber band `minZoom * (raw / minZoom)^0.35` (`CameraController.swift`, lines 13 and 141 to 146).
- Arithmetic: the shown zoom reaches 0.7 × `minZoom` at a raw zoom of 0.7^(1 / 0.35) ≈ 0.36 × `minZoom`. From zoom 0.25, the fingers must close to 36 % of their start distance. From zoom 1, they must close to 9 %.
- Options:
  - (a) Keep 0.7 on the shown zoom.
  - (b) Test the threshold on the raw zoom of the fingers, with a start value of 0.6 × `minZoom`. Tune it on the iPad in M6.
- Recommendation: (b). The threshold then follows the fingers and not the resistance curve. A lift above it springs back, as acceptance 3 needs.

### D-105 When the GPU glyph buffers of D-94 come

- Decided by the product owner on 2026-10-21: the recommendation. Raised by the review of M5 on the same day, for M6.
- D-94 moved the glyph buffers on the GPU to a later milestone. After the review of M5, the text of D-56 at zoom 0.25 takes 9.3 to 10.2 ms of CPU per build, about 5 frames of the build budget of 2 ms. Thus the pan over that text still shows uncovered screen.
- With D-96 (c), cards add about 0.5 ms to the same build, about 5 %.
- Options: (a) in M6, before the cards. (b) after M6, in M10 with the other performance baselines.
- Recommendation: (b). Cards change the build cost by little, and M6 already has a large scope. M10 measures all budgets again.

### D-106 Color of the canvas

- Decided by the product owner on 2026-10-21: the canvas background is RGB(24, 24, 24), `#181818`, instead of black. CAN-01 changes. The first choice of the same day, RGB(41, 44, 51), was too bright on the iPad.
- The ink and the text stay white. The PDF of EXP-03 stays white with black ink and text (D-13).
- The composite pass mixes the background and white with the coverage as weight: `background + (1 - background) * coverage`. It mixes the sRGB values that the drawable stores, as Core Animation does when it puts the live `PKCanvasView` on top. Full coverage stays 255 in each channel (D-38).
- `DesignSystem.Color.canvasBackground` holds the color. `RendererConfiguration.background` takes it from the app, so `Rendering` needs no `DesignSystem` import. The default of the configuration stays black, so the coverage tests and their reference images do not change. A pixel test covers the new background.
- The chrome background is gray 0.14 (RGB 36, 36, 36), a little brighter than the canvas. This decision does not change the chrome.

### D-107 PNG code and the owner of the preview files

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- D-97 stores a PNG. No source file imports ImageIO, and BUILD-03 needs a decision for a new Apple framework.
- ARCH-04 lets only `Persistence` touch the file system. `Persistence` is Tier A and must not import CoreGraphics or ImageIO (ARCH-03).
- Options:
  - (a) ImageIO in `Rendering`: it encodes and decodes the PNG bytes as `Data`. A `PreviewStore` in `Persistence` reads, writes, and removes the files as `Data`.
  - (b) No PNG: raw 8-bit gray bytes with a short header. A preview of 512 by 358 then takes 183 KB on disk instead of about 9 KB. D-97 changes.
- Recommendation: (a). It keeps D-97 and the layer rules.

### D-108 The fade of the parent during the open

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- D-98 fades the ink and the text of the parent and keeps the card. Text and cards share the green channel (D-96), so the composite cannot fade the text and keep the cards.
- Options:
  - (a) At the start of the animation, the renderer of the parent fades its whole composite: ink, text, and the other cards. A card pass draws the opened card on top at full weight: its border and its preview. The other cards leave the screen as the card grows, so the result is almost the same.
  - (b) Fade red only, and keep green. The text of the parent then stays on the card until the swap, which is jump 2 of D-98.
- Recommendation: (a).

### D-109 The image of the parent during a leave

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- While a child shows, the parent is not loaded. The pinch-out of CARD-05 shows "a faded image of the parent" at once. The open of the D-56 canvas takes about 250 ms.
- After a launch into a child (WS-04) and after an up button, no image of the new parent exists.
- Options:
  - (a) At the open, keep a frozen copy of the last frame of the parent: one texture of the drawable size in `.r8Unorm` (about 4 MB on the 11-inch iPad). Keep only the copy of the direct parent. If no copy exists, show the canvas color, and fade the parent in when its first frame is ready.
  - (b) When the pinch passes below `minZoom`, load the parent. Until its first frame is ready, show the canvas color.
  - (c) Keep the parent loaded while the child shows. That doubles the memory of a large canvas.
- For the up button, the leave starts the load of the parent at the tap. The child camera moves to the camera of the open in the same time (architecture.md section 6.3). When both are done, the reverse animation starts.
- Recommendation: (a) together with (b). The copy covers the common case. The load covers the launch and the up button.

### D-110 The memory peak of a transition

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- During an open, the parent and the child are both loaded: two contents, two point arenas, four committed textures, and two sets of three drawables (16.1 MB each, D-93). With the D-56 canvas as the parent and a D-56 child, the peak is about twice 350 MB.
- Options:
  - (a) Accept the peak, and set a separate budget for a transition after a measure in task 3.6.
  - (b) At the start of the animation, the parent renderer copies its frame into the texture of D-109 (a). Then it frees its committed textures and the eraser mask. The animation draws the frozen copy. After the crossfade, the parent screen goes, and its point arena goes with it.
- Recommendation: (b), with the budget of (a) set from the measure of task 3.6.

### D-111 The events that write a preview

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- D-97 writes the preview "when you leave the child". A workspace switch from inside a child also leaves it. A force quit inside a child leaves an old preview until the next leave.
- Options: (a) up button and pinch-out only. (b) Also the workspace switch and the move to the background.
- Recommendation: (b). The move to the background already writes the pending rows (STO-06).

### D-112 A path that names a deleted card

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- At launch, the app opens the deepest canvas of the stored path (WS-04). A card of the path can be deleted (D-18), or the path can point to the wrong parent after a restore (M9). No document says what then happens.
- Options: (a) Cut the path before the first card that is not live or whose `canvasID` is not the canvas above it. (b) Open the root canvas.
- Recommendation: (a). It keeps the deepest canvas that is still valid.

### D-113 What "an empty part of the canvas" is

- Decided by the product owner on 2026-10-21: the recommendation. Raised by [m6-plan.md](m6-plan.md) on the same day.
- CARD-01 makes a card with a long press "on an empty part of the canvas". Ink cannot be selected (CARD-07), and cards lie under the ink (D-16).
- Replaced by D-117 on 2026-10-22: no long press makes a card, so the term has no use.
- Options: (a) Empty means no card and no text box under the finger. Ink does not count. (b) Ink counts too, so a long press on ink does nothing.
- Recommendation: (a). A hit test of ink costs a pass over the strokes, and ink has no menu.

### D-114 Snapshot tests of the card menu and the rename alert

- Decided by the product owner on 2026-10-22: "Compare as well", so (a) and (b). The content tests stay, and pixel snapshots compare the menu and the alert too. Raised by task 4.2 of [m6-plan.md](m6-plan.md) on 2026-10-21.
- Design: `CardMenuSnapshotTests` presents the menu and the alert without animations in a key window of the test host and draws the windows of the scene. The alert field gives up the focus first, so no caret blinks. The system can skip a menu while the window becomes key, so the test presents it up to 3 times. Each test needs the key window. Since 2026-10-22, the tests are an XCTest class: the XCTest classes of a run run alone, before the Swift Testing suites, which run at the same time. In 5 full runs, a suite beside the menu test made the system skip the menu, and the test captured a black image. It passed alone and in `make snapshots`.
- Task 4.2 says: "Snapshot tests cover the menu and the alert." The card menu is a `UIEditMenuInteraction` menu with "Rename" and "Delete", and the rename is an alert with a text field, as the workspace rename does (D-101).
- Both are system UI. The snapshot helpers of the repository render our own views with `UIGraphicsImageRenderer` or Metal (TEST-07). A system menu or alert shows only in a window during its presentation, with animations and blur, so a pixel snapshot of it is not stable. The edit menu of a text box (M5) and the rename alert of a workspace (M3) have no snapshot.
- Options:
  - (a) Test the content of the menu and the alert instead of their pixels: the titles, the order, the destructive attribute of "Delete", the text field with its text, and the actions. No snapshot.
  - (b) Present the menu and the alert in the window of the test host and capture the window with `drawHierarchy(in:afterScreenUpdates:)` after their animations. The reference images change with each iPadOS release.
  - (c) Replace the system menu and alert with views of our own, and snapshot those. This is new UI that no requirement asks for (AGENT-02).
- Recommendation: (a). It tests what Pointer controls and matches M3 and M5.

### D-115 How a card opens

- Decided by the product owner on 2026-10-22 after the manual test of task 4.7: "A single tap on the card should open it, it currently takes two taps." It replaces the double tap of D-09 and the rules of D-100.
- A finger tap on a card that no text box covers opens the card. A tap on a text box starts its edit at once, as in M5 (TOOL-06). A tap while an edit runs only ends the edit, so a tap beside a box during typing does not open a card. The single tap needs no wait, so the double-tap recognizer and the measure of item 5 of task 4.3 go.
- CARD-03 and architecture.md section 4.7 change.

### D-116 The body of a card

- Decided by the product owner on 2026-10-22: "The body of the card should be a lighter gray like in Allume." It changes "no fill" of D-96 and architecture.md section 5.5.
- The video of Allume shows the canvas at RGB 20, the card body at RGB 35, and the border at RGB 67. On the canvas of RGB 24 (D-106), the same step of the body is a coverage of 0.065, about RGB 39 (`DesignSystem.Color.cardFill`).
- The fill is a coverage in the green channel, so it joins with the ink and the text by `max`. White ink and text show over it, so the order of D-16 holds.
- The border of Pointer stays at a coverage of 0.5, about RGB 140, much brighter than the border of Allume. The product owner did not ask to change it.

### D-117 How a new card comes

- Decided by the product owner on 2026-10-22: the recommendation, 1 (b), 2 (a), and 3: the long press goes. Raised by the product owner on the same day after the manual test of task 4.7: "I do not like the hold and pick New card, it should be like the handling of Allume instead, where the card is selected from the tool bar, and then appears in the left hand side." It replaces CARD-01, D-08, D-101, and D-113.
- The video of Allume shows a bar of tools at the bottom of the screen. A tap on its card tool makes a card half outside the left edge of the screen. A finger then drags the card into its place on the canvas, where it stays.
- Pointer has no bar of tools at the bottom. Its tools are in the palette of the tool button in the top left corner (TOOL-07, D-64).
- Questions:
  1. Where is the card tool: (a) a new entry "Card" in the tool palette, next to pen, eraser, and text; (b) a button of its own in the chrome, next to the tool button; or (c) a bar of tools at the bottom, as in Allume.
  2. What happens after the tap: (a) the card appears half outside the left edge, and a drag places it, as in the video; until the drag, it is not part of the canvas; or (b) the card appears at the left edge as a full card on the canvas, with one undo step, and a drag moves it later.
  3. Does the long press on empty canvas with "New card" go, or stay as a second way?
- Recommendation: 1 (b), a card button next to the tool button, because the palette holds the tools of the pencil. 2 (a), as in the video. 3: it goes.
- Design: the card button lies right of the tool button, and the up button lies right of the card button. A tap shows a pending card with the size of D-118. Its center lies on the left edge of the screen, at half the screen height. A one-finger pan that starts on the pending card drags it, and the camera stays. At the lift, the card joins the canvas with one `AddCard` step. A cancelled drag, or a drag without a move, leaves it pending at its place. A second tap on the button puts it back at the left edge. A tap on the pending card does not open it. At level 32 and at the node limit, the button shows the message of the limit and shows no card (D-95).

### D-118 The size of a new card

- Decided by the product owner on 2026-10-22: 320 by 224 canvas points. Raised by the product owner on the same day after the manual test of D-117: "the size of the card is currently not fixed resulting in larger cards when zoomed out, than at normal scale. Cards should have a fixed size." It replaces the size of D-101.
- Options: (a) 320 by 224, the example of D-101. (b) 300 by 210, about the old size at zoom 1 on the 11-inch iPad in landscape. (c) 240 by 168.
- Recommendation: (a).

### D-119 No zoom inside a card

- Decided by the product owner on 2026-10-22: the recommendation for each question. Raised by the product owner on the same day after the manual test of task 5.1: "the switch between the view of the card on the way out, and the rendered pic is bad. The card in the video is first shown as a small box, and then rendered at rest. Allume gets around this by not having zoom inside cards, which I would rather prefer. It will also make the exit pinch more easy to trigger as there would not be any initial zoom out in the canvas."
- Cause of the jump: during the pinch-out, the child zoomed out to about 0.18 with the rubber band, so the shrinking card showed the child content small. The preview shows the child at zoom 1. The two images did not match.
- Questions and answers: (1) Zoom goes away only inside cards. The root canvas of a workspace keeps the zoom range of CAN-04. (2) Inside a card, a pinch-out only drives the exit. It shrinks the child into its card from the first movement. A pinch-in does nothing. (3) The one-finger pan stays inside a card, so a child canvas stays unbounded.
- Design: a canvas inside a card has the zoom range 1...1. A pinch there keeps the shown camera. The raw zoom of the fingers drives the exit progress, as in D-104, with the threshold `exitZoomRatio` times zoom 1. A stored camera of a child with another zoom opens at zoom 1 with the same center.
- Closed point: a pan, or new content that moves the content bounds, put the child away from the camera of the open, so the shrinking card showed another region than the preview. Since 2026-10-22, the minimize animation of the pinch-out moves the camera to the camera of the open, as the up button does (D-109).

### D-120 Where the coverage check of TEST-02 runs

- Decided by the product owner on 2026-10-22: the recommendation, (a). Raised by task 1.1 of [m6-fix-plan.md](m6-fix-plan.md) on the same day.
- TEST-02 asks for 90 % line coverage in each Tier A package and 70 % in Rendering. The M6 close measured it by hand. The Tier A numbers come from `swift test --enable-code-coverage` on the Mac. The Rendering number needs one more full run of `PointerDeviceTests` on the iPad with the instrumented build of section 2.1 of the fix plan.
- The instrumented code is slower, so the performance tests of a coverage run fail or do not count.
- Options:
  - (a) A separate target `make coverage`. `make check` does not run it. Section 5 of code-of-code.md names it in item 3 of the pull request checklist.
  - (b) `make check` runs the coverage target. Each full check then has one more full device run, and the check must ignore the performance failures of that run.
  - (c) No target. The coverage stays a measure by hand at the close of a milestone.
- Recommendation: (a).

### D-121 The render thread computes the camera of a card flight

- Decided by the product owner on 2026-10-22: the recommendation, (a). Raised by task 2.2 of [m6-fix-plan.md](m6-fix-plan.md) on the same day.
- The open of an empty card had 1 late frame in 2 of 5 close runs of D-79. The main thread steps the camera of the flight in `InkView.onFrame`. The render thread waits at most 3 ms for a new camera, and without one it presents no frame. The load of the child screen blocks the main thread for 4 to 14 ms, so the animation stops for one or two frames. The leave has the same gap at the start of the parent flight. Section 2.2 of the fix plan has the research.
- Options:
  - (a) The render thread computes the camera and the parent weight of a flight from the closed form of the spring, at the target time of each frame. The main thread still steps its own camera for the logic: the end callbacks, the input lock, and `isInCardTransition`. Architecture.md section 6.2 changes: the main thread no longer drives the frames of a flight.
  - (b) Keep the main thread as the driver, and move the work of the child screen out of the flight: make the child screen before the flight, or after it. Research item 7 found that the leave has more main-thread work than the removal of the child, so this covers only part of the gaps.
  - (c) Accept the late frame, and relax the test of acceptance 1 of M6.
- Recommendation: (a).

### D-122 The renderer gets the change of a step before the model step

- Decided by the product owner on 2026-10-22: the recommendation, (a). Raised by task 3.2 of [m6-fix-plan.md](m6-fix-plan.md) on the same day.
- An undo, a redo, and an erase first run the model step on the main thread, 4 to 8 ms for the D-69 content, and only then give the change to the renderer. The change of `EraseStrokes` and `AddStroke` comes from the command alone (`renderDelta(of:isUndo:)`), so the renderer can start about 5 ms earlier.
- Risk: if the model step then throws, the renderer already has the change. The code then gives the renderer the reverse change and logs the error. For one frame, the screen can show ink that the model does not hold.
- Options:
  - (a) Give the change to the renderer before the model step for `EraseStrokes` and `AddStroke`, and undo it in the renderer if the model step throws. The other commands keep the order of today.
  - (b) Keep the order, and make only the model step faster (task 3.3 of the fix plan).
- Recommendation: (a), together with task 3.3.

### D-123 A pending card at a leave

- Decided by the product owner on 2026-10-22: the recommendation. Raised by the product owner on the same day: "If I open a card, click the new card button, exits the card and enters again, then the newly created card is gone." It changes D-117, where the card is not part of the canvas until the drag.
- Cause: the tap of the card button shows a pending card. Only a drag places it (D-117). A leave without a drag dropped the pending card, although the screen showed it.
- Options: (a) a leave, a workspace switch, or the move to the background places the pending card where it shows, with one undo step. (b) The tap places a full card at the left edge at once, as option 2 (b) of D-117. (c) Keep D-117.
- Recommendation: (a). Nothing that the screen shows is lost, and the drag of D-117 stays.
- Design: `CanvasViewController.placePendingCard()` adds the pending card with `AddCard` at its shown frame. `endSession()` calls it, so a leave, a workspace switch, and the open of a card place the card before the next screen comes. `enterBackground()` calls it before the final save.

### D-124 The card menu snapshots as an XCTest class

- Decided by the product owner on 2026-10-22: the exception is accepted. Raised by the fix of the card menu snapshot after the close of [m6-fix-plan.md](m6-fix-plan.md) (section 6.6).
- TEST-01 asks for Swift Testing in new unit tests and allows XCTest for UI tests and performance tests. The Swift Testing suites of a full run run at the same time, and a suite beside the menu snapshot made the system skip the menu. The XCTest classes run alone before them.
- Decision: `CardMenuSnapshotTests` is an XCTest class. A test that needs the key window or a system presentation alone can be an XCTest class for the same reason.

### D-125 The accepted late frame of the empty card in `make check`

- Decided by the product owner on 2026-10-22: (b) now, and (c) in M10. Raised by the review before M7.
- Facts: `OpenAnimationTests.testOpenAndLeaveOfEmptyCardHaveNoLateFrame` had 1 late frame at place 0 of the flight in 2 of 3 full runs of `PointerDeviceTests` on 2026-10-22. It never failed alone. The product owner accepted this late frame in [m6-fix-plan.md](m6-fix-plan.md) section 6.6. With it, `make check` fails in full runs, so the checklist of AGENT-05 cannot pass, and a new failure can hide behind it.
- Options: (a) keep the failure. (b) Mark the check of the late frames of that open as an expected failure that is not strict (`XCTExpectFailure` with `isStrict = false`), with a comment that names this decision. (c) Find the cause with a trace of the render thread in Instruments.
- Decision: (b). The check of the leave and of every other open stays strict. Task: a trace of the render thread during the open of an empty card in M10, then the removal of the expected failure.

### D-126 Where the hover dot draws

- Decided by the product owner on 2026-10-22: the recommendation. Raised by the review before M7. It changes architecture.md section 5.2.
- Facts: architecture.md section 5.2 put the dot in an overlay pass of the renderer, which does not exist. The display link of the render thread pauses after 12 frames without work (`RenderThread.idleFramesBeforeSleep`). A dot in Metal wakes the render thread at each hover sample and draws a full composite each time. A layer of Core Animation moves without a frame of the renderer.
- Decision: a `CAShapeLayer` in `CanvasView`, above the live `PKCanvasView`, with implicit animations off. A hover sample moves the layer and makes no allocation (PERF-01). The dot hides at pencil down, at the end of the hover, and during a card flight.

### D-127 The hover shadow of PencilKit

- Decided by the product owner on 2026-10-22: the recommendation. Raised by the review before M7.
- Facts: at WWDC24 (session 10214), Apple says that hovering with Apple Pencil Pro shows a shadow below the pencil for the PencilKit tools, and that a `PKCanvasView` gets it with the marker and the fountain pen. The live canvas of Pointer uses the monoline pen. No public API to turn the shadow off was found on 2026-10-22.
- Decision: task 0.1 of [m7-plan.md](m7-plan.md) checks on the device whether a shadow shows with the monoline pen. If it shows, Pointer accepts it as behavior of the system, as D-23 does for haptics, and keeps its dot (PEN-04).

### D-128 The shape of the hover dot and when it shows

- Decided by the product owner on 2026-10-22: the recommendation. Raised by the review before M7.
- Facts: architecture.md section 4.6 gave the gray dot, the eraser circle, and the gate on `UIPencilInteraction.prefersHoverToolPreview`, but no decision held these rules. Apple describes that property as the preference of the user for a preview of the current drawing tool when the pencil is close to the screen.
- Decision: the pen and the text tool show a small gray dot at the tip. The eraser shows a gray circle with the eraser radius of 8 view points (`EraserTool.radius`). No dot shows while "Show Hover Preview" is off in Settings.

### D-129 The pencils of the M7 tests

- Decided by the product owner on 2026-10-22: the test pencil is an Apple Pencil Pro. Raised by the review before M7.
- Facts: the iPad Pro 11-inch (M4) takes Apple Pencil Pro and Apple Pencil (USB-C) only. Apple Pencil (USB-C) hovers on this iPad, but it has no double tap, no squeeze, and no pressure. The monoline pen ignores pressure (D-05).
- Decision: acceptance 1, 2, and 4 of M7 run with the Apple Pencil Pro. Acceptance 3 runs with the Apple Pencil Pro, with double tap and squeeze set to "Ignore" in Settings, which gives the input of an Apple Pencil (USB-C).

### D-130 The double-tap settings that switch the tool

- Decided by the product owner on 2026-10-22: "use 'Switch to eraser' and 'Switch to previous' when double tap". Raised by the review before M7. It replaces the rule of D-07 and changes PEN-02 and architecture.md section 4.5.
- Facts: Apple's guidance says to do the preferred action of the user when possible. Apple's sample switches tools only for "Switch to eraser" and "Switch to previous tool".
- Decision: for `.switchEraser` and `.switchPrevious`, a double tap switches between pen and eraser, as D-07 did. If the tool is text, it switches to the pen. Every other value does nothing.

### D-131 The findings of the review before M7

- Decided by the product owner on 2026-10-22: the recommendation. Raised by the review before M7.
- Phase 0 of [m7-plan.md](m7-plan.md) fixes three faults in the navigation, each with a test that fails before the fix (TEST-03): a failed open loses the undo history of the parent, a leave whose parent card is missing refuses each later open and leave, and a preview render on a render thread that stops never calls its completion.
- M7 sets the tool of the live canvas only when it is needed, not at each frame of a zoom (PERF-01), after a measure.
- M10 takes the rest (plan.md section M10).

### D-132 Warnings that `-warnings-as-errors` does not stop

- Open. Raised on 2026-10-22 by the fix of the build warning after phase 0 of [m7-plan.md](m7-plan.md) (section 6.7).
- Facts: `Rendering` built with `-warnings-as-errors` and `-swift-version 6`, but the capture of a non-Sendable value in the completion handler of a Metal command buffer stayed a warning, and the build passed. A probe on 2026-10-22 showed that the same capture in a Swift `@Sendable` closure is an error. The Metal header marks the handler type `NS_SWIFT_SENDABLE`, and Swift 6 reports a capture in such an imported handler only as a warning, which `-warnings-as-errors` does not raise. BUILD-02 therefore has a gap, and `make check` cannot see a new warning of this kind. An incremental build also prints no warning for a file that it does not compile again.
- Options:
  - (a) `make build` builds from a clean state and fails if its output holds a line with `warning:`.
  - (b) Option (a), but on the incremental build of `make check`, plus a clean build only in `make coverage`.
  - (c) No change. Review finds such warnings.
- Recommendation: (a). It costs one full build in each check, and it enforces BUILD-02 as written.

### D-133 The eraser circle of the hover dot

- Decided by the product owner on 2026-10-22: (a). Raised by task 2.1 of [m7-plan.md](m7-plan.md).
- Facts: D-128 and architecture.md section 4.6 say that the eraser shows a gray circle with the eraser radius of 8 view points. They do not say whether the circle is an outline or a filled disc. A filled disc of 16 points covers the ink that the user wants to erase.
- Options: (a) an outline ring, with its line width as a `DesignSystem` token. (b) A filled disc, in the style of the dot of the pen.
- Decision: (a). The start width is 1 view point. The product owner tunes it in task 2.5 with the other tokens of the dot.

### D-134 The measure of the frames in task 3.1 of M7

- Decided by the product owner on 2026-10-23: (a), the recommendation. Raised on 2026-10-23 by task 3.1 of [m7-plan.md](m7-plan.md).
- Facts: task 3.1 asks for the main-thread time of the `dense 20k zoom` frame loop, and it is done when the frame loops are not slower. `FrameLoopTests` is in `Rendering` and drives the renderer alone. It never runs `CanvasViewController.applyCamera()`, so it cannot show the cost of the pen tool, and its check cannot fail for this task. The new `ZoomFrameAllocationTests` steps the frame callback of a root canvas screen without ink. On the iPad on 2026-10-23, a frame of a spring zoom made 139 allocations at the median and took 26.6 to 31.8 µs on the main thread over 3 runs. A frame of a glide at one zoom made 0 and took 0.3 µs. The line `liveCanvas.tool = PenTool.inkingTool(zoom:)` alone made 139.
- Options:
  - (a) Record the `dense 20k zoom` loop as the plan says, and use the frames of `ZoomFrameAllocationTests` for "Done when": 0 allocations in a zoom frame, and a main-thread time that is not slower.
  - (b) Keep the plan as written.
  - (c) Add a frame loop of the canvas screen with the dense 20k content.
- Recommendation: (a). It measures the code of the task, and it costs no new suite of long runs.

### D-135 A pencil down during a pinch past a zoom limit

- Decided by the product owner on 2026-10-23: (a), the recommendation. Raised on 2026-10-23 by the manual check of task 3.1 of [m7-plan.md](m7-plan.md).
- Facts: the product owner pinched out past the minimum zoom, kept both fingers on the screen, and drew. The stroke came out slimmer than a stroke after the lift, and the canvas sprang back while the line was drawn. The build before task 3.1 (commit 09044e4) does the same, so M7 did not cause it. `pencilBegan()` stops the camera and then ends the running pinch (D-36). The end of the pinch starts the spring back to the zoom limit (CARD-06), so the camera moves during the stroke. `PencilKitStrokeConverter` converts the stroke with the camera at the handoff, so the stroke loses width and can move. No document says what the camera does when a pencil touches during a pinch past a limit.
- Options:
  - (a) The camera holds its zoom during the stroke, and the spring back starts after the lift, once the stroke is handed off.
  - (b) The pencil down puts the camera at the limit at once, before the stroke starts. The canvas jumps under the pencil.
  - (c) The camera holds, and it springs back only at the next finger gesture.
- Recommendation: (a). The stroke keeps the shape and the width that the user saw, and the canvas ends inside the zoom range as after every pinch.

### D-136 Late frames at the start of card flights in full runs

- Decided by the product owner on 2026-10-23: (c). Raised on 2026-10-23 by phase 5 of [m7-plan.md](m7-plan.md).
- Facts: in 5 full runs of `PointerDeviceTests` with the code of commit 194959c, 4 runs failed a strict check of `OpenAnimationTests` with 1 late frame at place 0 or 1 of a flight: the leave of the empty card (2 runs), the open with a blocked main thread (2 runs), and the leave of the D-56 card (1 run). Alternating full runs gave the same failure for the code before phase 1 of M7 (commit 550aaef) in 1 of 2 runs, and for the new code in 1 of 2 runs. `OpenAnimationTests` alone, 5 iterations each, alternating: the old code had 1 late frame in 10 iterations, and the new code had 0 in 10. M7 therefore does not cause the late frame, but the samples are too small to show whether M7 changes how often it comes. D-125 accepts the same late frame for the open of the empty card only, and M10 traces it.
- Options:
  - (a) Mark the late-frame checks of each flight in `OpenAnimationTests` as expected failures that are not strict, as D-125 does, and add them to the trace of M10.
  - (b) Keep the checks strict, and accept that `make check` fails in most full runs until M10.
  - (c) Trace the late frame now, before M7 closes.
- Recommendation: (a). The late frame is older than M7, a strict check that fails in most runs hides new failures (the reason of D-125), and M10 already holds the trace.

### D-137 The wiring of new textures in the first frames of a leave

- Decided by the product owner on 2026-10-23: (a), the recommendation. Raised on 2026-10-23 by the trace of D-136.
- Facts: the report of `OpenAnimationTests` now gives the first frames of each flight. In 4 full runs on 2026-10-23, every leave started the GPU work of frame 1 2 to 4 ms after the frame was due (10.3 to 12.3 ms for a target of 8.3 ms). Frame 0 and the frames from frame 2 on started on time. The render thread spent at most 1.1 ms on each of these frames. In the passing runs, frame 1 still showed at 16.7 ms. In the 2 failing runs, it missed by one refresh. A Metal System Trace of a full run (`.build/Traces/D136-full.trace`) showed 355 Pointer command buffers with 2 ms or more of CPU time in the driver. 283 of them wired 1 MiB or more of memory during that time, mostly 52 to 131 MiB at once. Of the 17,374 faster command buffers, 867 did. While a command buffer waits for the wiring, the GPU is idle. A committed texture takes 32.3 MB on this iPad (architecture.md 5.2). The late open of the empty card (D-125) is a different fault: the render thread skips a target.
- Options:
  - (a) Make each new large texture resident when it is made, before a flight needs it, for example with an `MTLResidencySet` and `requestResidency()`, or with a small use of the texture in a frame that is not shown.
  - (b) Mark the late-frame check of the leaves as an expected failure that is not strict, as D-125 does, and move the fix to M10.
  - (c) Keep the checks strict and change nothing now.
- Recommendation: (a), after a measure of which textures wire at frame 1 of a leave. A residency request is in Rendering only, and it takes the wiring off the frames of the flight.
- Measures after the first decision, 2026-10-23, each with `OpenAnimationTests` alone, 10 iterations, unless named otherwise:
  1. A clear pass of the spare committed texture in the first frame of a layer moved the GPU start of frame 1 of the empty leave from 13.6 to 14.1 ms (9 of 10 iterations of the unchanged code) to 11.7 to 12.4 ms (9 of 10). It gains about 2 ms. Its effect on the late frames of full runs is not measured, and the first frame of every new canvas pays the wiring of both textures instead.
  2. A clear pass of the preview atlas in its first frame gained nothing: 14.0 to 14.8 ms.
  3. Four presented frames of the parent before the flight did not stop the wiring at the start of the flight (15.8 and 35.8 MiB). The GPU waits of frames 0 to 2 went from 2.73, 1.98, and 1.54 ms to 1.93, 1.86, and 1.38 ms (one traced run each).
  4. With the canvas layers not opaque, backboardd sent no "Unwire Memory Request" at the start of the flight, and the wiring fell from about 51 MiB to 20 MiB. The GPU waits of frames 0 to 2 stayed at 1.22, 2.17, and 1.95 ms (one traced run). The unwiring of the hidden parent is real, but it is not the main cause of the wait.
- None of the changes is in the code. The cause of the rest of the wait is not known.
- Decided again by the product owner on 2026-10-23: (b). The late-frame checks of the leave of the D-56 card and of the empty card are expected failures that are not strict, and M10 traces the rest of the wait in Instruments. On the same day, the product owner put the late-frame check of the open with a blocked main thread under D-125, because it has the same skipped target at place 0.

### D-138 The input of the PDF exporter

- Decided by the product owner on 2026-10-23: the recommendation. Raised by the review after M7.
- Facts: architecture.md section 9 names a `CanvasSnapshot` type, which does not exist. `CanvasContent` is a `Sendable` struct with all live strokes, text boxes, and cards of one canvas. Its dictionaries copy only on a change, and strokes share their points through `InkPoints`, so a copy is cheap (data-model.md section 7.4). The open path and `PreviewMaker` already take it. In storage.md, "snapshot" means a backup file.
- Options: (a) `CanvasContent`. (b) A new `CanvasSnapshot` type.
- Decision: (a). The exporter takes a `CanvasContent` value. The name `CanvasSnapshot` leaves architecture.md.

### D-139 The API that writes the PDF

- Decided by the product owner on 2026-10-23: the recommendation. Raised by the review after M7.
- Facts: the exporter runs off the main actor (architecture.md section 9). Drawing into a Core Graphics context is thread-safe since iOS 4 (<https://steipete.me/posts/2016/investigating-thread-safety-of-uiimage>). The iOS 27.1 SDK marks the UIKit renderer classes neither as main actor nor as `Sendable`, so Swift 6 cannot check their use on another thread. An Apple forum thread reports crashes in `UIGraphicsPDFRendererContext` on a background thread (<https://developer.apple.com/forums/thread/695153>). Selectable text depends on the way the text is drawn, not on the renderer (<https://developer.apple.com/forums/thread/745459>). A probe on the Mac on 2026-10-23 made searchable PDFs of any page size with `CGContext(consumer:mediaBox:_:)`.
- Options: (a) `CGContext(consumer:mediaBox:_:)` with `beginPDFPage` and `closePDF`. (b) `UIGraphicsPDFRenderer`.
- Decision: (a). The lint rule `arch_04_pdf` also bans `CGContext(consumer:` and `beginPDFPage` outside `Export`.

### D-140 The text layout of the PDF

- Decided by the product owner on 2026-10-23: the recommendation. Raised by the review after M7.
- Facts: `TextLayout` in `Rendering` lays out the text of the screen with `CTTypesetterSuggestLineBreak` at `TextStyle.maxWidth`, SF Mono from `UIFont.monospacedSystemFont`, and the fixed line height of that font (D-84). It keeps glyph IDs and positions only. A probe on the Mac on 2026-10-23 drew the same line in a PDF in three ways and read it back with PDFKit:
  1. Glyph IDs with `CTFontDrawGlyphs`: the text read back as "e o a e s educe(0, )", and a search for "reduce" found nothing.
  2. `CTLineDraw`: the whole line read back, and searches found "reduce" and the emoji.
  3. `CTFramesetter`: the same text as `CTLineDraw`, and the same line breaks as the typesetter for a long text at 640 points. But the framesetter places the lines with its own paragraph spacing.
  The fixed-pitch system font of Core Text on the Mac was Menlo, not SF Mono, so a second layout code can drift from the screen.
- Options: (a) Export imports `Rendering`, and `TextLayout` gives the font, the line ranges, and the baselines. Export draws each line with `CTLineDraw`. (b) `CTFramesetter` in `Export`, as architecture.md section 9 said. (c) A copy of the layout code in `Export`.
- Decision: (a). `TextLayout` also records the UTF-16 range of each line. Export tests run on the iPad in `PointerDeviceTests`, as the tests of `Rendering` do (D-77). The layer rule allows the import, because both packages are in layer 1.

### D-141 The page bounds of the PDF

- Decided by the product owner on 2026-10-23: the recommendation. Raised by the review after M7.
- Facts: `CanvasContent.contentBounds` holds the frames of the cards and only the top-left corner of each text box, because `Model` has no text layout. The open camera of CARD-03 uses it. EXP-03 asks for the bounds of the ink and the text, without cards. `Stroke.bounds` already holds half the line width.
- Options: (a) A function in `Export`: the union of `Stroke.bounds` and the rectangle of each text box from its origin and `TextLayout.size`, plus the margin of 48 points. (b) A change of `contentBounds`.
- Decision: (a). `contentBounds` does not change.

### D-142 An empty canvas, emoji, and pages over 14,400 points

- Decided by the product owner on 2026-10-23: the recommendation. Raised by the review after M7.
- Facts:
  1. No document says what an export of a canvas without ink and text gives. The tldraw example of an export checks for zero shapes and shows "No shapes on the canvas" (<https://tldraw.dev/examples/export-canvas-as-image>).
  2. In the probe of D-140, Core Graphics embedded color emoji as bitmap images, and a search still found them. Bitmap emoji lose sharpness at a high zoom (<https://github.com/foliojs/pdfkit/pull/1690>). The read-back text lost the skin-tone modifier of one emoji.
  3. A PDF page side is at most 14,400 units (ISO 32000, Annex C, <https://kb.datalogics.com/article/how-large-can-a-pdf-document-be-in-inches-101.html>). The `UserUnit` entry allows larger pages, but `CGPDFContext.h` has no key for it. In the probe, Core Graphics wrote a page of 20,000 points without a warning. The canvas has no coordinate limit, so a large page is a normal case.
- Decision:
  1. A canvas without strokes and without text boxes gives no PDF. The canvas shows a message from the String Catalog. Cards alone count as empty, because the PDF does not show cards (D-13).
  2. Emoji stay as the system draws them: bitmap images with searchable text. Acceptance 1 asks for sharp ink, not for sharp emoji.
  3. If a side of the page with its margin is longer than 14,400 points, one uniform scale fits the whole page, the line widths included. No smallest line width applies.

### D-143 The file name of the shared PDF

- Decided by the product owner on 2026-10-23: the recommendation, (a). Raised on 2026-10-23 by the M8 plan.
- Facts: EXP-04 opens the share sheet with the PDF, but no document gives a file name. A temporary file needs `FileManager`, which only `Persistence` may use (ARCH-04). `NSItemProvider.suggestedName` (iOS 11) gives a name to data, and `UIActivityViewController(activityItemsConfiguration:)` (iOS 14) takes item providers, so the share sheet needs no file. A canvas screen inside a card holds that card in `ParentLink.card`, which can be `nil`. `Card.title` is optional. The screen does not know the title of its workspace, but `PointerApp` does.
- Options:
  - (a) The name that the user sees: the title of the card, or the title of the workspace on the root canvas and for a card without a title, plus ".pdf".
  - (b) One fixed name from the String Catalog, for example "Pointer.pdf".
  - (c) Data without a name. The share targets give their own name.
- Recommendation: (a). The file says what it holds, and the user can still rename it in the share target. `PointerApp` gives the name to the canvas screen through `CanvasDependencies`. Characters that file names do not allow become "-".

### D-144 A budget for the time and the memory of an export

- Decided by the product owner on 2026-10-23: the recommendation, (a). Raised on 2026-10-23 by task 2.7 of [m8-plan.md](m8-plan.md). Decided again on the same day after a fix, see the end of this entry. The budgets are in architecture.md section 12.
- Facts: architecture.md section 12 has no budget for an export. `ExportPerformanceTests` measured on the iPad Pro 11-inch (M4) in Release, in two runs:
  1. D-56 (20,000 strokes of 300 points, 5,000 cards, 5,000 text boxes): 6.92 and 7.06 s, a peak memory growth of 101 MB, and a PDF of 79.6 MB.
  2. The strokes of D-56 and 10,000 text boxes: 7.43 and 7.52 s, 137 MB, and 79.8 MB.
  3. 200,000 handwriting strokes of 60 points: 14.77 and 14.83 s, 235 to 277 MB, and 226.4 MB.
- The strokes take almost all of the time, about 1.1 to 1.3 µs per Bézier segment. The export runs off the main actor, so drawing does not stop, and the export button is off until the export ends (task 3.1). The PDF stays in memory until the share sheet ends, because no file is written (ARCH-04). No document lists a progress indicator.
- Task 2.7 names "20,000 strokes and 10,000 text boxes" for D-56, but D-56 holds 5,000 cards and 5,000 text boxes. The test measures both contents.
- Options:
  - (a) Budgets from the measures plus about 15 %: D-56 at most 8.5 s and 160 MB, and 200,000 handwriting strokes at most 17 s and 320 MB. `ExportPerformanceTests` fails above them. The code stays as it is.
  - (b) As (a), and the export button shows a progress indicator while an export runs. PERF and EXP do not list it, so it needs a change of the product specification.
  - (c) A trace in Instruments first, to find a faster way to write the paths, and a lower budget after it. The gain is not known.
- Recommendation: (a). An export of a normal canvas takes far less time, the screen stays responsive, and the button shows that an export runs. D-56 with 300 points per stroke is a hard case (D-56).
- Change after the decision: the test with the budgets of (a) measured a peak of 261 MB for D-56 in 3 of 6 runs, and up to 331 MB for the handwriting. The reads every 2 ms missed short peaks, so the first measures were too low. Two copies of the whole PDF caused the peaks: the bridge from `NSMutableData` to `Data` at the end of the export, and a move of the growing buffer. The product owner chose to remove the copy first.
- The exporter now gives `Data` that shares the bytes of the buffer (`PDFExporter+Unsafe.swift`), and the test reads the memory every 0.25 ms. In 4 runs, D-56 peaked at 100 to 101 MB in 6.97 to 7.30 s, and the handwriting at 220 to 323 MB in 14.89 to 15.06 s.
- Decided again by the product owner on 2026-10-23: the highest measures plus about 15 %. An export of D-56 takes at most 8.5 s and 120 MB. An export of 200,000 handwriting strokes takes at most 17 s and 370 MB.
- Change at the close of M8: the full run of `make check` measured 178 MB for D-56, and 0 MB for the export with 10,000 text boxes. The export reused memory that the content build had freed just before, and in a full run other tests free and take memory. The test now waits for 1.5 s of steady memory before it measures, as `CanvasMemoryPerformanceTests` does. In 4 runs, D-56 then peaked at 139 to 153 MB in 6.95 to 7.27 s, and the handwriting at 265 to 281 MB in 14.84 to 15.02 s.
- Decided a third time by the product owner on 2026-10-23: an export of D-56 takes at most 8.5 s and 180 MB. An export of 200,000 handwriting strokes takes at most 17 s and 370 MB.
- Changed by D-145 on 2026-10-24: the memory budgets go. The time budgets stay.

### D-145 The memory measure of an export in a full run

- Decided by the product owner on 2026-10-24: time budgets only, after a try of (a). Raised on 2026-10-23 by the close of M8 ([m8-plan.md](m8-plan.md) section 6.7).
- Facts: `ExportPerformanceTests` reads the peak growth of `os_proc_available_memory` after 1.5 s of steady memory. In 5 full runs of `PointerDeviceTests`, D-56 read 198, 150, 154, 210, and 145 MB against the budget of 180 MB of D-144, and failed twice. The export with 10,000 text boxes, which makes a PDF of 79.8 MB, read 0, 8, 1, 0, and 8 MB. In runs of the suite alone, the same export read 139 to 144 MB. The free memory of the process counts pages. A page that the allocator keeps after a free counts as used, so the next export can reuse it and show too little growth, and the work of other tests can show as growth of the export. The times are stable in all runs: 6.94 to 6.99 s for D-56 and 14.79 to 14.88 s for the handwriting.
- Options:
  - (a) Count the bytes that malloc holds (`malloc_zone_statistics`, `size_in_use`), read every 0.25 ms during the export. Freed memory does not count, so reuse does not hide growth. Then measure again, and set the memory budgets from the new numbers.
  - (b) Keep the time budgets of D-144. The test records the memory and does not fail on it.
  - (c) Keep the measure, and raise the budget of D-56 to 240 MB (210 MB plus about 15 %). The reads of 0 MB show that the check can still pass when the export grows.
- Recommendation: (a). It measures what the budget means, the memory that the export takes, also in a full run.
- Try of (a), the recommendation that the product owner chose first: in a run of the suite alone, the malloc count read 228 MB for D-56, 228 MB for 10,000 text boxes, and 539 MB for the handwriting, whose free memory grew only 198 MB. Malloc counts the full capacity of the growing PDF buffer, also the part that no page backs. Each read locks the allocator zones, and the handwriting export took 16.04 s instead of about 14.8 s. So neither measure gives a reliable peak of one export inside the test process.
- Decision: `ExportPerformanceTests` keeps the free-memory measure with the wait for steady memory, and fails only on the time budgets of D-144. It records the memory. A better memory measure, for example in Instruments, can come in M10. This decision replaces the memory budgets of D-144.

### D-146 The checkpoint of the library database

- Decided by the product owner on 2026-10-24: (c), with the hard limit at 8,000 pages. Raised on the same day by the M8 fix plan ([m8-fix-plan.md](m8-fix-plan.md) section 4). storage.md section 4 describes the checkpoints.
- Facts: the library uses WAL mode with `synchronous = NORMAL` and the automatic checkpoint of SQLite at 1,000 pages. The save that passes 1,000 pages runs the checkpoint and its sync. In a full run, one save took 205 ms against the budget of 50 ms. A benchmark on the iPad measured 31 to 155 ms for the checkpoint saves under disk stress. The SQLite documentation advises to "disable automatic checkpointing and run the periodic checkpoints in a separate thread" (<https://sqlite.org/wal.html>).
- Options:
  - (a) Keep the automatic checkpoint. A save can wait for a sync.
  - (b) Turn off the automatic checkpoint of the write connection. A second connection in a thread of its own runs a passive checkpoint when the WAL holds 1,000 pages or more after a save. In the benchmark, the slowest save under stress dropped from 178 to 306 ms to 10.7 ms, and the WAL stayed under 1,120 pages.
  - (c) As (b), and the write connection also runs a checkpoint itself when the WAL passes a hard limit, for example 8,000 pages, in case the checkpointer cannot keep up.
- Durability does not change: `synchronous` stays `NORMAL`, and a checkpoint still syncs. The checkpoint connection is a second SQLite connection in `Persistence` (ARCH-04).
- Recommendation: (b). With saves at most once per second, the checkpointer catches up between saves. (c) adds a second path that a test must cover, for a case that the benchmark did not show at the pace of the app.

## Points in the request that conflict or are not complete

1. "Only three tools" and "drawing data structures": cards need a way in (D-08), and diagrams need a way to move things (D-10).
2. "Double tap toggles pen and eraser" and Apple's rule to honor the user setting (D-07).
3. "Squeeze for tools": the request does not say which tools. The design shows a palette with pen, eraser, text, undo, and redo.
4. "Zoom out past the current card": the request does not give the minimum zoom. The design starts with 0.25 and a release threshold of 0.7 times that value. Both need tuning on a device.
5. "Standard zoom" in the parent: the design reads it as zoom 1.0, centered on the card that you left.
6. "Export of the current canvas": the request does not say what happens to cards on that canvas. The PDF does not show them (D-13).
