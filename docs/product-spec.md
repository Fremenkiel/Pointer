# Product specification

This document states what Pointer does. It does not state how. For the implementation, read [architecture.md](architecture.md).

Each requirement has an ID. Code, tests, and pull requests refer to these IDs. Items marked "Open" depend on a decision in [decisions.md](decisions.md).

## 1. Purpose

Pointer is a note app for software developers on iPad. You use it to sketch data structures, flows, and system diagrams, and to write short technical notes. The writing must feel like a pen on paper.

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

- CAN-01: The canvas background is black (`#000000`).
- CAN-02: The canvas has no edges. You can pan in every direction without a limit that you can feel.
- CAN-03: You pan with one finger and zoom with two fingers. The pencil never pans.
- CAN-04: The zoom has a minimum and a maximum. The start values are 0.25 and 8.0. The standard zoom is 1.0.
- CAN-05: Pan and zoom run at the display refresh rate (120 Hz on ProMotion iPads) without dropped frames.

### 3.2 Tools

- TOOL-01: The app has three tools: pen, eraser, and text. No other tool exists.
- TOOL-02: The pen draws white (`#FFFFFF`) lines. The line width is fixed (Open: D-05, pressure).
- TOOL-03: Only Apple Pencil draws. A finger never draws.
- TOOL-04: The eraser removes ink where the pencil touches it (Open: D-06, partial or whole-stroke eraser).
- TOOL-05: The text tool creates a text box where the pencil taps. The keyboard opens. Scribble (handwriting into text fields) works in the text box.
- TOOL-06: A finger tap on an existing text box starts editing it.
- TOOL-07: A small tool bar shows the current tool and lets you change it with a tap.

### 3.3 Apple Pencil

- PEN-01: A double tap on the pencil switches between pen and eraser.
- PEN-02: The app reads the system setting for double tap (`UIPencilInteraction.preferredTapAction`). If the setting is "Ignore", the app does nothing (Open: D-07).
- PEN-03: A squeeze (Apple Pencil Pro) opens a small tool palette at the pencil tip. The palette holds pen, eraser, text, undo, and redo.
- PEN-04: When the pencil hovers (on iPads that support hover), a small dot shows where the tip will touch.
- PEN-05: The app works with every Apple Pencil model. It never needs pressure, because Apple Pencil (USB-C) has no pressure sensor.

### 3.4 Drawing feel

- FEEL-01: The time from pencil movement to visible ink is at most 20 ms on a 120 Hz iPad Pro. The target is 13 ms or less. See [research.md](research.md) section 3.
- FEEL-02: Ink appears on the first touch sample. No gesture recognizer delays the start of a stroke.
- FEEL-03: A stroke does not change shape after the pencil lifts.
- FEEL-04: No frame is dropped while you draw.

### 3.5 Cards and navigation

- CARD-01: You can create a card on a canvas (Open: D-08, how you create it).
- CARD-02: A card shows a frame, an optional title, and a scaled preview of its content.
- CARD-03: You can open a card (Open: D-09, how you open it). The app zooms into the card and shows its canvas at the standard zoom.
- CARD-04: An up button leaves the current card. The app shows the parent canvas at the standard zoom, centered on the card.
- CARD-05: If you pinch past the minimum zoom inside a card, the card shrinks toward its frame in the parent. When you release past a threshold, a minimize animation takes you to the parent canvas at the standard zoom. If you release before the threshold, the camera springs back to the minimum zoom.
- CARD-06: On the root canvas, a pinch past the minimum zoom springs back. Nothing else happens.
- CARD-07: You can move a card and a text box with a finger (long press, then drag) (Open: D-10).
- CARD-08: You can delete and rename a card through a context menu (long press without a drag).
- CARD-09: The tree depth has a limit of 32 levels.

### 3.6 Workspaces

- WS-01: A workspace selector is in the top left corner. It shows the name of the current workspace.
- WS-02: The selector lists all workspaces. You can switch, create, and rename a workspace in it.
- WS-03: You can delete a workspace in the selector. The app asks for a confirmation first (Open: D-11).
- WS-04: The app opens the last used workspace at launch, at the last camera position.

### 3.7 Undo, redo, and export

- UNDO-01: Undo and redo buttons are in the top right corner.
- UNDO-02: Undo and redo work on the current canvas. Each canvas keeps its own history while the app runs (Open: D-12).
- UNDO-03: Undoable actions: add stroke, erase, add text box, edit text, move, resize, create card, delete card, rename card.
- UNDO-04: Navigation and camera changes are not undoable.
- EXP-01: An export button is in the top right corner, next to undo and redo.
- EXP-02: Export makes a vector PDF of the current canvas. Ink is vector paths. Text is real text that you can select and search.
- EXP-03: The PDF page covers the bounds of all content on the canvas, plus a margin (Open: D-13, background color and cards).
- EXP-04: The app opens the system share sheet with the PDF.

### 3.8 Storage and backup

- STO-01: The app stores all data on the device. It has no accounts and no network access.
- STO-02: The library is a folder that you can see in the Files app, under "On My iPad > Pointer".
- STO-03: You can back up the library by copying that folder to any storage provider in the Files app.
- STO-04: A "Back up now" command makes one zip file of the library and opens the share sheet (Open: D-14).
- STO-05: The data model is ready for an automatic backup to an online provider later. This version contains no such integration.
- STO-06: The app never loses more than 2 seconds of work after a crash.

## 4. Out of scope

These features are not part of Pointer. A pull request that adds one of them will be rejected:

- Colors other than white ink on black.
- Images, files, PDFs, links, audio, and video on the canvas.
- Highlighters, shapes, rulers, and stickers.
- Accounts, sharing, collaboration, and sync.
- An iPhone or Mac version.
