# Open decisions

This document lists each design point where the right choice is not certain. Each entry gives the options, a recommendation, and the reason. The documents use the recommendation until the product owner decides.

Status values: Open, Decided.

## Summary

| ID | Question | Recommendation | Status |
|---|---|---|---|
| D-01 | Minimum iPadOS version | iPadOS 26 | Open |
| D-02 | Custom Metal ink engine or PencilKit | Custom, with a latency test in M1 | Open |
| D-03 | Plain folders or document packages | Plain folders | Open |
| D-04 | SwiftLint and swift-syntax as development tools | swift-syntax for scripts only, no SwiftLint | Open |
| D-05 | Pressure changes the line width | No, fixed width | Open |
| D-06 | Partial eraser or whole-stroke eraser | Partial | Open |
| D-07 | Double tap and the system setting | Follow "Ignore", else toggle pen and eraser | Open |
| D-08 | How to create a card | Long press on empty canvas, then "New card" | Open |
| D-09 | How to open a card | Finger double tap on the card | Open |
| D-10 | Move content and lasso selection | Move cards and text boxes in version 1, lasso later | Open |
| D-11 | Delete a workspace | Yes, with a confirmation | Open |
| D-12 | Scope and life of undo history | Per canvas, in memory | Open |
| D-13 | PDF background and nested cards | Black, child content one level deep | Open |
| D-14 | Scheduled backup through Shortcuts | Include the App Intent | Open |
| D-15 | Text font | SF Mono | Open |
| D-16 | Layer order on a canvas | Cards, then ink, then text | Open |
| D-17 | One ID type or one type per entity | One type per entity | Open |
| D-18 | Content of deleted cards | Purge after 30 days | Open |
| D-19 | Text as one string or as paragraphs | One string | Open |
| D-20 | Restore inside the app | Not in version 1 | Open |
| D-21 | Watch the library folder for outside changes | Not in version 1 | Open |
| D-22 | Handwriting search with `PKStrokeRecognizer` | Not in version 1, keep the path open | Open |

## Details

### D-01 Minimum iPadOS version

- Options: iPadOS 18 (`UIUpdateLink`, custom tool picker items), iPadOS 26 (Liquid Glass design), iPadOS 27 (newest PencilKit features).
- Recommendation: iPadOS 26. Pointer is a personal tool, so a wide device range has little value. The iPadOS 27 features stay optional behind `if #available`.
- Doubt: if you want the app on an older iPad, choose 18.

### D-02 Custom Metal ink engine or PencilKit

- Options: a custom Metal engine (the design in these documents), PencilKit, or PencilKit for capture with custom display.
- Recommendation: custom engine. PencilKit has a confirmed tile-render bug at zoom levels other than 1x. It needs one view per visible card. It stores data in a format that is not documented.
- Doubt: no published measurement shows that a custom engine reaches the latency of PencilKit. Press reports from 2019 say that Apple keeps part of the gain for itself. Milestone M1 measures both. If the custom engine is more than 3 ms slower, the team must decide again.

### D-03 Plain folders or document packages

- Options: each workspace as a plain folder, or as a package with its own file type that Files shows as one item.
- Recommendation: plain folders. All backup tools handle them. A package needs a registered file type and gives little extra value without document sharing.
- Doubt: in Files, a plain folder invites the user to open it and change files by accident.

### D-04 Development tools

- The request says "as few dependencies as possible". The app links no third-party code. The question is about development tools.
- Options: (a) SwiftLint, the de facto standard, used by Proton, Infomaniak, and Threema. (b) Only `swift format` from the toolchain plus scripts in the repository. Metrics such as function length then need `swift-syntax`, a package from the Swift project.
- Recommendation: (b). `swift-syntax` is used by the scripts only and never ships in the app.
- Doubt: (b) means about 300 lines of script code to maintain. SwiftLint gives the same rules with no code.

### D-05 Pressure and line width

- Options: fixed width, or width that changes with pressure.
- Recommendation: fixed width (a monoline pen). Diagrams look clean, the PDF is an exact copy of the screen (a stroked path), and Apple Pencil (USB-C) behaves like the other models. The app stores force anyway, so a later version can add pressure.
- Doubt: a fixed width looks less like a real pen. A fountain-pen look needs outline geometry, which makes the renderer and the PDF export more complex.

### D-06 Eraser behavior

- Options: partial (cuts the stroke where the eraser touches), whole stroke (removes the stroke that it touches), or both with a switch.
- Recommendation: partial. It behaves like a real eraser on paper.
- Doubt: a whole-stroke eraser is faster for diagrams (one touch removes an arrow) and is simpler to build. Allume added a stroke eraser in version 3.5.2, which shows that users ask for it.

### D-07 Double tap and the system setting

- The request says that double tap switches between pen and eraser. Apple's guidelines say that apps must honor the user's choice in Settings.
- Recommendation: if the setting is "Ignore", do nothing. For every other value, switch between pen and eraser.
- Doubt: a user who chose "Switch to previous tool" can expect a switch back from text to the pen. The recommendation does this, because text then goes to the pen.

### D-08 How to create a card

- The tool list is pen, eraser, and text only. A card needs a way in.
- Options: (a) long press on empty canvas, then "New card" in a menu. (b) a fourth tool. (c) draw a rectangle with the pencil and convert it.
- Recommendation: (a). It keeps the tool list at three.
- Doubt: (c) feels more natural with a pencil but needs shape recognition, which the product rules out.

### D-09 How to open a card

- Options: finger double tap, pinch-zoom into the card past a threshold, or both.
- Recommendation: finger double tap only. Pinch-zoom on a card must stay free for a closer look at the preview.
- Doubt: zoom-in to open is the mirror of zoom-out to leave, and Muse used it. Try both in M6.

### D-10 Move content and lasso selection

- The request lists no selection tool. Data-structure diagrams often need a change of layout.
- Recommendation: version 1 moves cards and text boxes with a long press and drag. Ink cannot move. A lasso can come later as a mode of the eraser or a fourth tool.
- Doubt: without a lasso, a wrong position for a drawn arrow means you erase and draw it again. This is the largest gap against the request "only three tools".

### D-11 Delete a workspace

- The request names create and rename only.
- Recommendation: allow delete, with a confirmation. The workspace becomes a tombstone and stays on disk for 30 days (see D-18).

### D-12 Undo history

- Options: per canvas or one history for the app. In memory or stored.
- Recommendation: per canvas, in memory. Undo then never changes a canvas that is not on the screen.
- Doubt: after you leave a card and come back, its history is still there. After a restart, all history is gone.

### D-13 PDF background and nested cards

- Options for the background: black (as on the screen), or white with black ink (for print).
- Options for cards: frame and title only, child content one level deep, or one extra page per card.
- Recommendation: black, and child content one level deep. A white "print" option can come later.
- Doubt: a black page uses a lot of toner on a printer.

### D-14 Scheduled backup through Shortcuts

- Recommendation: include the App Intent. It uses no provider API, so it fits "no integration".
- Doubt: it is not proven that a Shortcuts automation can run the intent while the iPad is locked. If it cannot, the automation runs at the next unlock.

### D-15 Text font

- Recommendation: SF Mono, because the notes contain code.
- Doubt: a monospaced font is wider and harder to read for long prose.

### D-16 Layer order

- Recommendation: fixed layers. Cards at the bottom, ink in the middle, text on top. Arrows drawn over a card then stay visible.
- Doubt: a fixed order does not let you put a card on top of ink.

### D-17 ID types

- Recommendation: one wrapper type per entity (`CardID`, `StrokeID`, and so on) instead of type aliases. The compiler then refuses a `StrokeID` where a `CardID` is needed. The data model document shows aliases for brevity.

### D-18 Content of deleted cards

- Recommendation: a deleted card and its subtree stay on disk as tombstones for 30 days. Then the repository removes them at launch. A future sync needs the tombstones longer, so this number can change.

### D-19 Text model

- Recommendation: one string per text box. Text boxes are short.
- Doubt: with a future sync, two devices that edit the same box will lose one edit. Paragraph lists or a text CRDT fix this, at a cost.

### D-20 Restore inside the app

- Recommendation: not in version 1. Restore is a copy in the Files app while Pointer is closed.
- Doubt: a restore by hand into the wrong folder can mix two libraries.

### D-21 Watch the folder

- Recommendation: not in version 1. The app reloads changed canvases at launch and at each return to the foreground.

### D-22 Handwriting search

- iPadOS 27 adds `PKStrokeRecognizer`, which recognizes handwriting on the device. The custom stroke format can convert to `PKDrawing` for it.
- Recommendation: not in version 1, because the request does not ask for search. The stroke format keeps the data that the recognizer needs.

## Points in the request that conflict or are not complete

1. "Only three tools" and "drawing data structures": cards need a way in (D-08), and diagrams need a way to move things (D-10).
2. "Double tap toggles pen and eraser" and Apple's rule to honor the user setting (D-07).
3. "Squeeze for tools": the request does not say which tools. The design shows a palette with pen, eraser, text, undo, and redo.
4. "Zoom out past the current card": the request does not give the minimum zoom. The design starts with 0.25 and a release threshold of 0.7 times that value. Both need tuning on a device.
5. "Standard zoom" in the parent: the design reads it as zoom 1.0, centered on the card that you left.
6. "Export of the current canvas": the request does not say what happens to cards on that canvas (D-13).
