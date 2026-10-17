# Architecture

This document describes how Pointer is built. It covers the modules, the input pipeline, the renderer, navigation, text, undo, and export. The data types are in [data-model.md](data-model.md). Files and backup are in [storage.md](storage.md). The rules for the code are in [code-of-code.md](code-of-code.md).

## 1. Principles

1. Ink latency comes first. Each design choice that touches the drawing path must keep the latency target (FEEL-01).
2. One stroke geometry. The screen and the PDF draw the same points with the same width. Thus the export matches the screen.
3. Pure core. All logic that does not need UIKit or Metal lives in packages that import Foundation only. Unit tests cover these packages without a device.
4. Apple frameworks only. The app links no third-party code.
5. Bounded everything. Each collection, loop, and recursion has a named limit (see section 10).

## 2. Platform choices

| Area | Choice | Reason |
|---|---|---|
| App shell | UIKit `UIApplication` with a `UIScene` | The canvas needs direct `UITouch` access and exact frame timing. |
| Canvas view | A `UIView` subclass with a `CAMetalLayer` | Lowest latency path. Full control of the camera and the cards. |
| Chrome (top bars, workspace selector, palette) | SwiftUI views in `UIHostingController` children | Less code for lists, menus, and alerts. Not on the ink path. |
| Text editing | `UITextView` (TextKit 2), only while you edit | Keyboard, Scribble, selection, and dictation come free. |
| Frame timing | `UIUpdateLink` (iOS 18+) | Apple's documented low-latency path for pencil apps. |
| PDF | `UIGraphicsPDFRenderer`, Core Graphics, Core Text | Vector output and real text. |
| Storage | Files in the app `Documents` folder, Foundation `FileManager`, `NSFileCoordinator` | See [storage.md](storage.md). |
| Logging | `os.Logger`, `OSSignposter` | Logging that is off has zero cost. Signposts feed the performance tests. |

PencilKit is not part of the main design. If the custom engine fails the latency test, PencilKit is the fallback (decision D-02).

## 3. Modules

The project is one Xcode project with one app target and local Swift packages under `Packages/`. The packages use three layers. A package can import only packages in the same layer or in a lower layer. Feature packages never import other feature packages.

```
Layer 3  App target       PointerApp
                              |
Layer 2  Features         CanvasFeature    WorkspaceFeature    BackupFeature
                              |                  |                  |
Layer 1  Shared           Rendering   Export   Persistence   DesignSystem
                              |          |          |
Layer 0  Foundations      InkEngine ---- Model ---- Geometry
```

| Package | Layer | Imports | Contents |
|---|---|---|---|
| `Geometry` | 0 | Foundation | `Point`, `Vector`, `Rect`, `Transform` in `Double`. Camera math. `SpatialGrid`. |
| `Model` | 0 | `Geometry` | Value types: `Workspace`, `Card`, `TextBox`, `Stroke`, IDs, `HybridClock`, `FractionalIndex`. Commands and `History`. Protocol `LibraryRepository`. |
| `InkEngine` | 0 | `Model`, `Geometry` | `OneEuroFilter`, `StrokeBuilder`, Catmull-Rom subdivision, eraser hit test and stroke split. |
| `Persistence` | 1 | `Model` | `FileLibraryRepository` (an actor), JSON and binary codecs, migrations, zip backup. |
| `Rendering` | 1 | `Model`, `Geometry`, `InkEngine`, Metal | `CanvasRenderer`, GPU stroke buffers, shaders, text texture cache. |
| `Export` | 1 | `Model`, `Geometry`, `InkEngine`, Core Graphics, Core Text | `PDFExporter`. |
| `DesignSystem` | 1 | SwiftUI, UIKit | Color, spacing, size, and icon tokens. Shared small views. |
| `CanvasFeature` | 2 | Layer 0 and 1 | `CanvasViewController`, `CanvasView`, input routing, camera control, card navigation, text editing, top bars. |
| `WorkspaceFeature` | 2 | Layer 0 and 1 | Workspace selector, create, rename, delete. |
| `BackupFeature` | 2 | Layer 0 and 1 | "Back up now" command and the App Intent. |
| `PointerApp` | 3 | All | Scene setup, dependency composition, routing between features. |

A script in CI reads `swift package show-dependencies --format json` for each package. It fails the build on a forbidden import (see [code-of-code.md](code-of-code.md), rule ARCH-02).

Dependencies flow down. Features get repositories and services through their initializers. No singletons exist, except the ones that Apple provides.

## 4. Input pipeline

### 4.1 Touch routing

The canvas view gets all touches. It separates them by `UITouch.type`:

- `.pencil` touches go to the active tool directly, in `touchesBegan`, `touchesMoved`, `touchesEnded`, and `touchesCancelled`. No gesture recognizer sees pencil touches. Thus nothing delays the first ink sample (FEEL-02).
- `.direct` (finger) touches go to gesture recognizers with `allowedTouchTypes = [.direct]`: one-finger pan, two-finger pinch, tap, and long press.

The view sets `isMultipleTouchEnabled = true`. A finger that touches during a pencil stroke does not cancel the stroke.

### 4.2 Pen samples

For each pencil event, the pen tool does these steps:

1. Read `event.coalescedTouches(for: touch)`. Each coalesced touch is one sample (240 Hz).
2. Convert each location from view space to canvas space with the camera (in `Double`).
3. Send each sample through `OneEuroFilter`. Start values: minimum cutoff 1.0 Hz, beta 0.007, derivative cutoff 1.0 Hz. Tune them on a device (see [plan.md](plan.md), M1).
4. Append the filtered samples to the `StrokeBuilder` as committed points.
5. Read `event.predictedTouches(for: touch)`. Filter them with a copy of the filter state. Give them to the builder as the temporary tail. Keep only the predicted points within 8 ms of the last real sample.
6. Mark the live stroke as dirty for the next frame.

If a touch has `estimatedPropertiesExpectingUpdates` that contains `.force`, the builder keeps its `estimationUpdateIndex`. `touchesEstimatedPropertiesUpdated(_:)` then updates the force of that sample. Force is stored but not drawn in version 1 (decision D-05).

On `touchesEnded`, the builder drops the tail and returns a finished `Stroke`. The stroke contains exactly the committed points that the user saw (FEEL-03). On `touchesCancelled`, the builder drops the stroke.

### 4.3 Curve smoothing

`StrokeBuilder` subdivides the committed points with centripetal Catmull-Rom splines. It adds points until no segment is longer than 0.5 canvas points. The renderer and the PDF exporter both draw the subdivided points as straight segments. Thus the screen and the export show the same curve.

### 4.4 Eraser

The eraser has a radius of 8 view points. The radius stays the same on the screen at every zoom. On each pencil sample, the eraser tool does these steps:

1. Convert the sample to canvas space. Convert the radius to canvas units with the camera zoom.
2. Ask the `SpatialGrid` for the strokes whose bounds touch the eraser circle.
3. For each of these strokes, run the hit test against each segment.

The result depends on decision D-06:

- Partial eraser (recommended): `StrokeSplitter` removes the points inside the circle and returns the remaining runs as new strokes. The command records the old stroke ID and the new strokes.
- Whole-stroke eraser: the command records the stroke ID only.

The changes of one eraser gesture (pencil down to pencil up) form one undo step.

### 4.5 Apple Pencil interaction

`CanvasViewController` installs one `UIPencilInteraction` and is its delegate.

Double tap (`pencilInteraction(_:didReceiveTap:)`):

| `preferredTapAction` | Action |
|---|---|
| `.ignore` | Nothing. |
| `.runSystemShortcut` | Nothing. The system handles it. |
| `.switchEraser`, `.switchPrevious`, and all other values | Switch between pen and eraser. If the current tool is text, switch to pen. |

Squeeze (`pencilInteraction(_:didReceiveSqueeze:)`): act on phase `.ended` only.

| `preferredSqueezeAction` | Action |
|---|---|
| `.ignore` | Nothing. |
| `.runSystemShortcut` | The app never receives it. |
| All other values | Show the tool palette at `squeeze.hoverPose?.location`. If the pose is `nil`, show it at the last pencil location. |

The mapping of user preferences to actions is decision D-07.

### 4.6 Hover

A `UIHoverGestureRecognizer` with `allowedTouchTypes = [.pencil]` shows a small gray dot at the tip. If `UIPencilInteraction.prefersHoverToolPreview` is `false`, the dot does not show. For the eraser, the dot is a circle with the eraser radius.

### 4.7 Finger gestures

| Gesture | Target | Action |
|---|---|---|
| One-finger pan | Canvas | Pan the camera. Deceleration after release. |
| Two-finger pinch | Canvas | Zoom about the midpoint of the two fingers. Pan at the same time. |
| Tap | Text box | Start editing (TOOL-06). |
| Double tap | Card | Open the card (decision D-09). |
| Long press | Card or text box | Context menu: rename (card), delete. |
| Long press, then drag | Card or text box | Move it (decision D-10). |

## 5. Rendering

### 5.1 Frame loop

`CanvasRenderer` owns the `CAMetalLayer` and one `UIUpdateLink`. Use this configuration:

```swift
link.wantsLowLatencyEventDispatch = true
link.wantsImmediatePresentation = true
link.requiresContinuousUpdates = false   // true only while the pencil is down or the camera moves
link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

metalLayer.maximumDrawableCount = 2
metalLayer.presentsWithTransaction = true
metalLayer.pixelFormat = .bgra8Unorm
metalLayer.framebufferOnly = true
```

If the M1 test shows no gain from `UIUpdateLink`, the fallback is `CAMetalDisplayLink` with `preferredFrameLatency = 1`. With two drawables, `nextDrawable()` can block. The renderer must measure the frame time against `UIUpdateInfo.completionDeadlineTime` and log a signpost for each late frame.

### 5.2 Layers in a frame

Each frame draws three passes:

1. The committed layer: all finished strokes, text, and cards that are visible. This layer is a texture with the size of the drawable. The renderer reuses it while the camera and the content do not change.
2. The live stroke: the committed points and the predicted tail of the stroke in progress.
3. Overlays: the hover dot and the selection outline.

While you draw, the camera does not move. So each frame copies the committed texture and draws only the live stroke on top. The cost of a frame does not depend on the size of the canvas.

While the camera moves, the renderer draws all visible content directly from the GPU buffers of each stroke. The `SpatialGrid` limits the work to the strokes that touch the viewport.

### 5.3 Stroke geometry on the GPU

Ink is opaque white on black. So overlapping parts of a stroke need no blending, and the draw order of strokes does not matter.

Each stroke is a list of capsules (a capsule is a segment with round ends). The renderer draws them as instanced quads. The fragment shader computes the distance from the pixel to the segment and gives an anti-aliased edge one pixel wide. One draw call draws all capsules of all visible strokes.

GPU data for one capsule:

```swift
struct CapsuleInstance {      // 20 bytes, stroke-local Float32
    var start: SIMD2<Float>
    var end: SIMD2<Float>
    var radius: Float
}
```

Each stroke stores its origin in `Double` and its points as `Float` offsets from that origin. Per frame, the CPU computes the transform from stroke space to clip space in `Double`. The CPU converts the transform to `Float` only after the camera position is removed. Thus precision stays correct at any distance from the canvas origin.

The renderer builds the GPU buffer of a stroke once: at load time, or at the end of the stroke. After the stroke leaves the viewport plus one screen of margin, the renderer frees the buffer.

### 5.4 Text

The renderer draws text as textures. `TextRasterizer` draws each text box with Core Text into a bitmap. The scale of the bitmap is the zoom rounded up to the next power of two. The cache holds at most 256 textures and removes the least recently used one first.

While a text box is in edit mode, the renderer hides it. A `UITextView` sits at the same place, with the same font and a transform that matches the camera.

The text font is SF Mono, 17 points at zoom 1.0 (decision D-15).

### 5.5 Cards

A card on its parent canvas has these parts:

- A rounded rectangle with a 1-point border in gray (`DesignSystem.Color.cardBorder`).
- The optional title, above the top-left corner.
- A preview of the child canvas inside the frame.

The preview uses the same renderer. It draws the content of the child canvas into a texture with the size of the card on the screen, then caches the texture. If the content of the child canvas changes, the renderer draws the preview again. The preview shows content one level deep. Deeper cards show as empty frames. This limits the work and the recursion.

Layer order on a canvas, from bottom to top: cards, ink, text boxes (decision D-16).

### 5.6 Spatial index

Each loaded canvas has one `SpatialGrid`. The grid has square cells of 512 canvas points in a dictionary keyed by cell coordinates. Each cell holds the IDs of the strokes, text boxes, and cards whose bounds touch it. A query for a rectangle reads only the cells in that rectangle. A query has a limit: at zoom 0.25 on a 13-inch iPad, the viewport covers at most about 40 cells.

## 6. Camera and navigation

### 6.1 Camera

```swift
struct Camera: Equatable, Sendable {
    var center: Point     // canvas space, Double
    var zoom: Double      // view points per canvas point
}
```

The limits are `Limits.minZoom = 0.25`, `Limits.maxZoom = 8.0`, and `Limits.standardZoom = 1.0`. `CameraController` turns pan and pinch input into camera changes. It also applies deceleration and the rubber band below the minimum zoom.

The camera of each canvas is stored in the device state, not in the library (see [storage.md](storage.md)).

### 6.2 Open a card

1. The user opens a card (decision D-09).
2. The controller animates the camera of the parent so that the card frame fills the screen. The animation takes 0.35 s with a spring curve.
3. At the end of the animation, the controller swaps the parent canvas for the child canvas. The child camera starts at the standard zoom, centered on the content bounds of the child. If the child is empty, the camera centers on the origin.
4. The swap has no visible jump. The preview texture of the card and the first frame of the child show the same content at the same size.

### 6.3 Leave a card

There are two ways to leave a card:

- Up button. The controller shows the parent canvas with the camera on the card center at the standard zoom. Then it plays the open animation in reverse: the child shrinks into the card frame.
- Pinch out. Below `minZoom`, the zoom does not stop. It continues with resistance (rubber band). While below `minZoom`, the controller shows the child as a shrinking card over a faded image of the parent. If the fingers lift when `zoom < minZoom * 0.7`, the controller plays the minimize animation and shows the parent at the standard zoom. Otherwise, the camera springs back to `minZoom`.

On the root canvas, the rubber band springs back. No transition happens (CARD-06).

The threshold `0.7` is a start value. Tune it on a device.

### 6.4 Navigation state

`NavigationState` holds the path from the root canvas to the current canvas as a list of card IDs. The list has a limit of `Limits.maxDepth = 32`. If the list is not empty, the up button shows.

## 7. Text boxes

- Create: with the text tool active, a pencil tap makes a new text box at the tap point and starts editing.
- Edit: a `UITextView` (TextKit 2) appears at the place of the box. Scribble works without extra code. The text view has its own undo while you edit.
- End: a tap outside the box, or a change of tool, ends editing. The canvas records one `EditText` command with the old and the new text. An empty text box is deleted, and the canvas records no command.
- Size: the width grows with the longest line, up to 640 canvas points. Longer lines wrap. The height grows with the text.
- Content: plain text only. No rich text, no links.

## 8. Undo and redo

Undo uses the `History` type from `Model`. It does not use `UndoManager` for canvas content, because `History` is a pure value type that unit tests can cover.

- Each canvas has its own `History` while the app runs (decision D-12).
- Each user action becomes one `CanvasCommand`. Each command has an `apply` function and a `revert` function on the canvas content. Both functions are pure.
- Commands: `AddStroke`, `EraseStrokes` (removed IDs plus added parts), `AddTextBox`, `EditText`, `MoveNode`, `ResizeTextBox`, `AddCard`, `DeleteNode`, `RenameCard`.
- A delete is a tombstone, not a removal (see [data-model.md](data-model.md)). Thus an undo of a delete only clears the tombstone.
- The history has a limit of `Limits.maxHistoryDepth = 500` steps per canvas. The oldest step is dropped first.
- A new command clears the redo list.
- A hardware keyboard gets Command-Z and Shift-Command-Z through `UIKeyCommand`.

While a text view is in edit mode, the undo and redo buttons go to the text view.

## 9. PDF export

`PDFExporter` takes a `CanvasSnapshot` (all live strokes, text boxes, and cards of one canvas) and returns PDF `Data`.

1. Compute the content bounds. Add a margin of 48 points.
2. Make one page with the size of the bounds. If a side is longer than 14,400 points (the PDF page limit of 200 inches), scale the content down to fit.
3. Fill the page black (decision D-13).
4. Draw the cards: frame, title, and the child content one level deep, as vectors and clipped to the frame.
5. Draw each stroke as one `CGPath` of the subdivided points. Use `setLineCap(.round)`, `setLineJoin(.round)`, the stroke width, and white.
6. Draw each text box with `CTFramesetter` and `CTFrameDraw`. Flip the text matrix for the PDF coordinate system.

The exporter runs off the main actor. It reads a snapshot (a value copy), so it does not block drawing. The result goes to `UIActivityViewController`.

## 10. Limits

All limits live in one type, `Limits`, in `Model`. Code uses the names, never the numbers.

| Name | Value | Reason |
|---|---|---|
| `maxDepth` | 32 | Card tree depth (CARD-09). Bounds the recursion. |
| `maxPointsPerStroke` | 16,384 | About 68 s of pencil input. A longer stroke ends and a new one starts. |
| `maxStrokesPerCanvas` | 200,000 | Upper bound for loops and memory. |
| `maxNodesPerCanvas` | 10,000 | Cards plus text boxes. |
| `maxTextLength` | 100,000 | Characters per text box. |
| `maxWorkspaces` | 1,000 | Workspace list. |
| `maxHistoryDepth` | 500 | Undo steps per canvas. |
| `minZoom`, `maxZoom`, `standardZoom` | 0.25, 8.0, 1.0 | Camera (CAN-04). |

If the user reaches a limit, the app shows a short message. It never crashes and never drops data in silence.

## 11. Concurrency

- Swift 6 language mode with complete strict concurrency in every target.
- UI types, the canvas, and the renderer run on the main actor.
- `FileLibraryRepository` is an actor. All file access goes through it.
- The canvas sends value snapshots to the repository. It never shares mutable state.
- PDF export and the backup zip run in a `Task` off the main actor. They report progress to the main actor.
- No code on the main actor waits for disk.

## 12. Performance budgets

| Measure | Budget | How to measure |
|---|---|---|
| Pencil to ink | 13 ms goal, 20 ms limit | High-speed camera and the presented-time log (see [research.md](research.md) 3.4) |
| Frame time while drawing | Under 4 ms CPU, under 4 ms GPU | `OSSignposter` intervals in an `XCTOSSignpostMetric` test |
| Dropped frames while drawing or panning | 0 per 10 s | Animation Hitches template |
| Open a workspace with 20,000 strokes | Under 300 ms to first frame | `XCTClockMetric` |
| Save after a stroke | Off the main actor, under 50 ms | Signpost |
| Memory for a canvas with 20,000 strokes | Under 300 MB | `XCTMemoryMetric` |

Performance tests run on a real iPad. If a measure is more than 10% worse than its baseline, the test fails.
