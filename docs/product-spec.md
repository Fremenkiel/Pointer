# Product specification

This document states what Pointer does. It does not state how. For the implementation, read [architecture.md](architecture.md).

Each requirement has an ID. Code, tests, and pull requests refer to these IDs. Items marked "Open" depend on a decision in [decisions.md](decisions.md).

## 1. Purpose

Pointer is a note app for software developers on iPad. You use it to sketch data structures, flows, and system diagrams, and to write short technical notes. Ink must appear as fast as ink from a pen on paper. The app does not imitate paper in any other way.

Pointer does few things. It has no colors, images, files, highlighters, or shapes. A feature request that adds one of these is out of scope.

## 2. Concepts

| Term | Meaning |
|---|---|
| Library | All workspaces on the device. The library is the unit of backup. |
| Workspace | A named top-level entry. A workspace owns one root canvas. |
| Canvas | A surface with no edges that holds strokes, text boxes, and cards. |
| Card | A rectangle on a canvas. A card opens into a canvas of its own (its child canvas). |
| Stroke | One line that the pen draws, from pencil down to pencil up. |
| Text box | A block of typed text at a position on a canvas. |
| Camera | The visible part of a canvas: a position and a zoom factor. |

The cards form a tree. The root of each tree is the root canvas of a workspace.

## 3. Requirements

### 3.1 Canvas

- CAN-01: The canvas background is dark gray, RGB(24, 24, 24) (`#181818`) (D-106).
- CAN-02: The canvas has no edges. You can pan in every direction without a limit that you can feel.
- CAN-03: You pan with one finger and zoom with two fingers. The pencil never pans.
- CAN-04: The zoom has a minimum and a maximum. The start values are 0.25 and 8.0. The standard zoom is 1.0.
- CAN-05: Pan and zoom run at the display refresh rate (120 Hz on ProMotion iPads) without dropped frames.

### 3.2 Tools

- TOOL-01: The app has three tools: pen, eraser, and text. No other tool exists.
- TOOL-02: The pen draws white (`#FFFFFF`) lines. The line width is fixed. Pressure does not change it (D-05).
- TOOL-03: Only Apple Pencil draws. A finger never draws.
- TOOL-04: The eraser removes ink where the pencil touches it and cuts the stroke at that place (D-06).
- TOOL-05: The text tool creates a text box where the pencil taps. The keyboard opens. Scribble (handwriting into text fields) works in the text box.
- TOOL-06: A finger tap on an existing text box starts editing it.
- TOOL-07: A small tool bar shows the current tool and lets you change it with a tap. A squeeze of the pencil opens it as the palette of PEN-03 (D-63). A button in the top left corner shows the current tool, and a finger tap on it opens the same palette (D-64).
- TOOL-08: A long press on a text box without a drag opens a menu with "Delete" (D-89).

### 3.3 Apple Pencil

- PEN-01: A double tap on the pencil switches between pen and eraser.
- PEN-02: The app reads the system setting for double tap (`UIPencilInteraction.preferredTapAction`). If the setting is "Ignore", the app does nothing. For every other value, a double tap switches between pen and eraser (D-07).
- PEN-03: A squeeze (Apple Pencil Pro) opens a small tool palette at the pencil tip. The palette holds pen, eraser, text, undo, and redo.
- PEN-04: When the pencil hovers (on iPads that support hover), a small dot shows where the tip will touch.
- PEN-05: The app works with every Apple Pencil model. It never needs pressure, because Apple Pencil (USB-C) has no pressure sensor.
- PEN-06: The app gives no haptic feedback in the pencil or in the iPad. Haptics that the system plays by itself are accepted, but drawing plays none (D-23). It has no paper texture, no paper grain, and no writing sound. Responsiveness is the only property that the app takes from paper.

### 3.4 Drawing feel

- FEEL-01: The time from pencil movement to visible ink is at most 20 ms on a 120 Hz iPad Pro. The target is 13 ms or less. See [research.md](research.md) section 3.
- FEEL-02: Ink appears on the first touch sample (D-35).
- FEEL-03: A stroke does not change shape after the pencil lifts.
- FEEL-04: No frame is dropped while you draw.

### 3.5 Cards and navigation

- CARD-01: You can create a card on a canvas. You long press on an empty part of the canvas, then pick "New card" (D-08).
- CARD-02: A card shows a frame, an optional title, and a scaled preview of its content.
- CARD-03: You open a card with a finger double tap on the card (D-09). The app zooms into the card and shows its canvas at the standard zoom.
- CARD-04: An up button leaves the current card. The app shows the parent canvas at the standard zoom, centered on the card.
- CARD-05: If you pinch past the minimum zoom inside a card, the card shrinks toward its frame in the parent. When you release past a threshold, a minimize animation takes you to the parent canvas at the standard zoom. If you release before the threshold, the camera springs back to the minimum zoom.
- CARD-06: On the root canvas, a pinch past the minimum zoom springs back. Nothing else happens.
- CARD-07: You can move a card and a text box with a finger (long press, then drag). Ink cannot move. Version 1 has no lasso (D-10).
- CARD-08: You can delete and rename a card through a context menu (long press without a drag).
- CARD-09: The tree depth has a limit of 32 levels. The root canvas is level 0, and a card on a canvas of level n opens a canvas of level n + 1. "New card" on a canvas of level 32 is refused with a message (D-95).

### 3.6 Workspaces

- WS-01: A workspace selector is in the top left corner. It shows the name of the current workspace.
- WS-02: The selector lists all workspaces. You can switch, create, and rename a workspace in it.
- WS-03: You can delete a workspace in the selector. The app asks for a confirmation first (D-11).
- WS-04: The app opens the last used workspace at launch, at the last camera position.

### 3.7 Undo, redo, and export

- UNDO-01: Undo and redo buttons are in the top right corner.
- UNDO-02: Undo and redo work on the current canvas. Each canvas keeps its own history while the app runs (D-12).
- UNDO-03: Undoable actions: add stroke, erase, add text box, edit text, delete text box, move, create card, delete card, rename card. Version 1 has no resize: a text box takes its size from its text (D-83), and a card keeps the size of its creation (D-102).
- UNDO-04: Navigation and camera changes are not undoable.
- EXP-01: An export button is in the top right corner, next to undo and redo.
- EXP-02: Export makes a vector PDF of the current canvas. Ink is vector paths. Text is real text that you can select and search.
- EXP-03: The PDF page covers the bounds of the ink and the text on the canvas, plus a margin. The page is white, and ink and text are black. The PDF does not show cards (D-13).
- EXP-04: The app opens the system share sheet with the PDF.

### 3.8 Storage and backup

- STO-01: The app stores all data on the device. It has no accounts and no network access.
- STO-02: The app writes a complete copy of the library (a snapshot) once a day into a folder that you can see in the Files app, under "On My iPad > Pointer > Backups".
- STO-03: You can back up the library by copying a snapshot file to any storage provider in the Files app.
- STO-04: A "Back up now" command makes a new snapshot and opens the share sheet. The app has no App Intent for scheduled backups (D-14).
- STO-07: You can restore the library from a snapshot file (D-20).
- STO-05: The data model is ready for an automatic backup to an online provider later. This version contains no such integration.
- STO-06: The app never loses more than 2 seconds of work after a crash.

## 4. Out of scope

These features are not part of Pointer. A pull request that adds one of them will be rejected:

- Colors other than white ink and text on the canvas color of CAN-01.
- Images, files, PDFs, links, audio, and video on the canvas.
- Highlighters, shapes, rulers, and stickers.
- Accounts, sharing, collaboration, and sync.
- An iPhone or Mac version.
