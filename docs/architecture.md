# Architecture

This document describes how Pointer is built. It covers the modules, the input pipeline, the renderer, navigation, text, undo, and export. The data types are in [data-model.md](data-model.md). Storage and backup are in [storage.md](storage.md). The rules for the code are in [code-of-code.md](code-of-code.md).

## 1. Principles

1. Ink latency comes first. Each design choice that touches the drawing path must keep the latency target (FEEL-01).
2. One stroke geometry. The screen and the PDF draw the same points with the same width. Thus the export matches the screen.
3. Pure core. All logic that does not need UIKit or Metal lives in packages that import Foundation only. Unit tests cover these packages without a device.
4. Apple frameworks only. The app links no third-party code.
5. Bounded everything. Each collection, loop, and recursion has a named limit (see section 10).
6. No imitation of paper. The app plays no haptics and no sounds, and draws no paper texture (PEN-06). Haptics that the system plays by itself, for example on squeeze, are accepted (D-23).

## 2. Platform choices

| Area | Choice | Reason |
|---|---|---|
| App shell | UIKit `UIApplication` with a `UIScene` | The canvas needs direct `UITouch` access and exact frame timing. |
| Canvas view | A `UIView` subclass with a `CAMetalLayer`, and one `PKCanvasView` on top for the live stroke | PencilKit gives the lowest latency for the live stroke (M1). Metal gives full control of the camera and the cards. |
| Live pen input | PencilKit, `PKCanvasView` at zoom 1 (decisions D-02 and D-33) | The custom input path trailed the pencil in M1. |
| Chrome (top bars, workspace selector, palette) | SwiftUI views in `UIHostingController` children | Less code for lists, menus, and alerts. Not on the ink path. |
| Text editing | `UITextView` (TextKit 2), only while you edit | Keyboard, Scribble, selection, and dictation come free. |
| Frame timing | `UIUpdateLink` (iOS 18+) | Frame loop of the Metal renderer. |
| PDF | `UIGraphicsPDFRenderer`, Core Graphics, Core Text | Vector output and real text. |
| Storage | SQLite from the system (`import SQLite3`), no wrapper library | See [storage.md](storage.md). |
| Logging | `os.Logger`, `OSSignposter` | Logging that is off has zero cost. Signposts feed the performance tests. |

PencilKit captures the pen input and draws the live stroke. The Metal renderer draws all finished ink. Pointer never stores PencilKit data. The custom input path failed the latency test of M1 (see [research.md](research.md) section 3.5, decisions D-02 and D-33).

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
| `Geometry` | 0 | Foundation | `Point`, `Vector`, `Rect`, `Transform` in `Double`. `Camera` and camera math. `SpatialGrid`. `StrokeCurve`, the B-spline math. |
| `Model` | 0 | `Geometry` | Value types: `Workspace`, `Card`, `TextBox`, `Stroke`, IDs, `HybridClock`, `FractionalIndex`. Commands and `History`. Protocol `LibraryRepository`. |
| `InkEngine` | 0 | `Model`, `Geometry` | Eraser hit test and stroke split. |
| `Persistence` | 1 | `Model`, SQLite3 | `SQLiteLibraryRepository` (an actor), a small SQLite wrapper, row codecs, migrations, snapshots, restore. |
| `Rendering` | 1 | `Model`, `Geometry`, `InkEngine`, Metal | `CanvasRenderer`, the point arena, shaders, the committed texture cache, text texture cache. |
| `Export` | 1 | `Model`, `Geometry`, `InkEngine`, Core Graphics, Core Text | `PDFExporter`. |
| `DesignSystem` | 1 | SwiftUI, UIKit | Color, spacing, size, and icon tokens. Shared small views. |
| `CanvasFeature` | 2 | Layer 0 and 1, PencilKit | `CanvasViewController`, `CanvasView`, the live `PKCanvasView`, `PencilKitStrokeConverter`, input routing, camera control, card navigation, text editing, top bars. |
| `WorkspaceFeature` | 2 | Layer 0 and 1 | Workspace selector, create, rename, delete. |
| `BackupFeature` | 2 | Layer 0 and 1 | "Back up now" command and restore. |
| `PointerApp` | 3 | All | Scene setup, dependency composition, routing between features. |

The script `Scripts/check-layers.swift` reads `swift package dump-package` for each package and the `import` lines of its sources. It fails the build on a forbidden import (see [code-of-code.md](code-of-code.md), rule ARCH-02). It also fails on third-party code (rule BUILD-03): a remote package, a local package outside `Packages/`, a binary target, or a prebuilt framework in the Xcode project.

Dependencies flow down. Features get repositories and services through their initializers. No singletons exist, except the ones that Apple provides.

## 4. Input pipeline

### 4.1 Touch routing

The canvas view holds the Metal view and one `PKCanvasView` on top of it. The `PKCanvasView` has a clear background and `drawingPolicy = .pencilOnly`. It never zooms or scrolls.

- With the pen tool, `.pencil` touches go to the drawing gesture recognizer of the `PKCanvasView`. PencilKit draws the live stroke.
- With the eraser tool or the text tool, the drawing gesture recognizer is off. `.pencil` touches go to the active tool directly, in `touchesBegan`, `touchesMoved`, `touchesEnded`, and `touchesCancelled`. See decision D-34.
- `.direct` (finger) touches go to gesture recognizers with `allowedTouchTypes = [.direct]`: one-finger pan, two-finger pinch, tap, and long press.

The view sets `isMultipleTouchEnabled = true`. A finger that touches during a pencil stroke does not cancel the stroke. While the pencil draws, the pan and pinch gesture recognizers ignore the finger, so the camera does not move (decision D-36).

A palm guard keeps the palm away from the finger gestures (review A-14). iPadOS suppresses most palm touches while the pencil is near the screen, but not all. The finger gesture recognizers ignore a `.direct` touch in these cases:

1. The touch begins while a pencil touch is active.
2. The touch begins less than 150 ms after the last pencil touch ended. The value is a start value. Tune it on a device.
3. The `majorRadius` of the touch is larger than a palm threshold. Find the start value on a device in M2.

The guard affects the finger gestures only. A finger never draws in any case (TOOL-03), because the `PKCanvasView` uses `drawingPolicy = .pencilOnly`.

### 4.2 Pen strokes

PencilKit gives no samples before pencil lift. The pen tool works in these steps:

1. The `PKCanvasView` draws the live stroke at zoom 1 in view space. Its tool is a white monoline `PKInkingTool`. The pen width is 2 canvas points (decision D-37). The tool width is the pen width times the camera zoom, so the live stroke has the same size on the screen as the finished stroke.
2. At pencil lift, `canvasViewDrawingDidChange(_:)` reports the new `PKStroke`.
3. `PencilKitStrokeConverter` reads the control points of `stroke.path` (decision D-26), applies `stroke.transform`, and converts each point from view space to canvas space with the camera (in `Double`). The converter takes the stroke width from the point sizes of the `PKStroke`, not from the tool width. A monoline point of size `s` draws a line `2 * (s - 2)` points wide (see [m2-plan.md](m2-plan.md) section 1). The result is a `Stroke` of the `Model`. Both steps are affine transforms, and an affine transform of the control points gives the same transform of the curve. Thus the conversion does not change the shape. The math lives in `Geometry` and `Model` (Tier A). `CanvasFeature` only reads the `PKStroke`.
   If the path has more than `Limits.maxPointsPerStroke` control points, the converter makes several strokes. Each new stroke starts with the last 3 control points of the stroke before it, so the curve continues without a gap or a kink. With `max` blending, the overlap does not show.
4. The renderer adds the stroke to the committed layer and asks for a frame.
5. After the presented handler of that frame runs, the canvas view removes the stroke from the `PKCanvasView`. Thus no frame shows the stroke twice or not at all.

The `PKDrawing` of the `PKCanvasView` holds at most the strokes that wait for the handoff. Pointer never stores PencilKit data.

The finished stroke must look the same as the live stroke (FEEL-03). In the M1 hybrid spike, the product owner saw a clear difference in style and width at the handoff. M2 must fix it (see [plan.md](plan.md), M2). Possible causes to test:

- The PencilKit monoline width and the capsule width use different definitions. The spike drew capsules with half the tool width as the radius and ignored the point sizes of the `PKStroke`.
- The monoline rendering of PencilKit has its own edge and end shape, which capsules do not copy.
- PencilKit clamps the monoline width to `PKInkingTool.InkType.monoline.validWidthRange`. At zoom 0.25 or 8, the live width can differ from the finished width.
- The spike Metal layer had no color space, so its anti-aliased edge differed from the edge of PencilKit.
- The spike blended capsules with "over", so overlapping capsules made the joints brighter.
- The spike made the PencilKit white with `PKInkingTool.convertColor` in the dark style, so the white was possibly not exactly `#FFFFFF`.
- The spike cleared the whole `PKDrawing` at the handoff. If the pencil already started the next stroke, the clear can cancel it. M2 removes only the handed-off stroke and tests a fast second stroke.

Decision D-38 sets the color and the blending for both layers:

- The Metal layer uses `.bgra8Unorm` and the sRGB color space (section 5.1).
- The ink pipeline blends with `max`, not with "over" (section 5.3).
- The `PKCanvasView` uses the light interface style and the tool color `UIColor.white`, so PencilKit does not convert the color. A test makes sure that the center of a stroke is 255 in each channel in both layers. If PencilKit cannot give 255, the Metal ink uses the value that PencilKit gives.

### 4.3 Curve smoothing

PencilKit smooths the stroke. A `PKStrokePath` is a uniform cubic B-spline over its control points. Pointer stores these control points and draws the same curve (decision D-26).

- `StrokeCurve` in `Geometry` evaluates the curve on the CPU. Tests, the eraser, and the export use it.
- The vertex shader evaluates the same curve on the GPU (section 5.3).
- The PDF exporter converts each curve piece to one cubic Bézier segment. This conversion is exact (section 9).

The screen and the export show the same curve. The curve does not depend on the zoom at which you drew it.

Apple does not document how PencilKit treats the first and the last control point. A test in M2 compared `StrokeCurve` with `PKStrokePath.interpolatedLocation(at:)` and found the end rule: each end uses a phantom point that mirrors the second point through the end point, so the curve passes through both end points. The parameter runs from 0 to `count - 1`. The handoff test at zoom 0.25, 1, and 8 compares the images.

### 4.4 Eraser

The eraser has a radius of 8 view points. The radius stays the same on the screen at every zoom. On each pencil sample, the eraser tool does these steps:

1. Convert the sample to canvas space. Convert the radius to canvas units with the camera zoom.
2. Ask the `SpatialGrid` for the strokes whose bounds touch the eraser circle.
3. For each of these strokes, run the hit test against each segment.

The eraser is partial (decision D-06). `StrokeSplitter` removes the points inside the circle and returns the remaining runs as new strokes. The command records the old stroke ID and the new strokes.

The changes of one eraser gesture (pencil down to pencil up) form one undo step.

The stored points are control points, not points on the curve (decision D-26). M4 must define how a cut on the curve maps to the control points of the new parts.

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

The renderer encodes its frames on a render thread (D-42). The types work together in this way:

1. `InkView` owns the `CAMetalLayer`. When the view joins a window, it starts one `RenderThread`. When the view leaves the window, it stops the thread.
2. `RenderThread` runs a `CAMetalDisplayLink` on its own run loop. Each update of the link gives the drawable of the frame, so `nextDrawable()` never blocks the main thread.
3. `RenderEngine` holds the frame work (`FrameRenderer`) behind one lock and an inbox behind a second lock.
4. `CanvasRenderer` is the main-actor side. It writes the camera, the viewport, and new strokes into the inbox as values. It never waits for a frame.
5. At the start of each frame, the render thread takes the inbox and draws. The handoff callback returns to the main actor (section 4.2).

`FrameRenderer` owns `CommittedLayer`, `InkEncoder`, `StrokeStore`, and `DrawListRing`. These types have no actor isolation. One thread at a time uses them: the render thread in the app, or the thread of a test.

Use this configuration:

```swift
displayLink.preferredFrameLatency = 2       // RenderThread.frameLatency
displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

metalLayer.maximumDrawableCount = 3   // decision D-41
metalLayer.presentsWithTransaction = false // see below
metalLayer.pixelFormat = .bgra8Unorm
metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)   // decision D-38
metalLayer.framebufferOnly = true
```

The frame presents with `commandBuffer.present(_:)`. With `presentsWithTransaction = true`, the call `waitUntilScheduled` blocked the main thread during a camera glide on the device, and touches arrived late (M2, see [m2-plan.md](m2-plan.md) section 4). With two drawables, `nextDrawable()` blocked the main thread for 16.3 ms in each frame (D-41). A frame latency of 1 or 3 gave more late frames than 2 on the device.

The display link pauses after 12 frames that drew nothing. A frame that drew is not idle, even if the renderer needs no next frame. The next change in the inbox wakes the link. The main-thread side of a change costs about 0.01 ms.

The render thread and the main thread wake on the same display frame. If the camera moved in the last frame and no new camera waits, the render thread waits up to 3 ms (`RenderEngine.cameraWaitBudget`) for the camera of the main thread. Without the wait, about 1 frame in 10 of a pan found no new camera and drew nothing.

`InkView` keeps one `UIUpdateLink` on the main thread for the camera animations, for example the glide after a pan. It runs only while an animation runs.

A build also has a time budget of 2 ms per frame on the render thread (`RendererConfiguration.buildTimeBudget`).

The live pen stroke does not use this frame loop (section 4.2). The eraser of M4 needs low latency. `UIUpdateLink` runs on the main thread only, so its low-latency settings do not apply to the render thread (D-42). M4 must design the eraser path for the render thread.

### 5.2 Layers in a frame

Each frame draws these passes:

1. The committed layer: all finished strokes, text, and cards that are visible. This layer is a texture with the size of the drawable. The renderer reuses it while the camera and the content do not change.
2. The live eraser path, if the eraser is active.
3. Overlays: the hover dot and the selection outline.

The live pen stroke is not a pass of the renderer. The `PKCanvasView` on top draws it (section 4.2). While you draw, the renderer draws a frame only at the handoff of a stroke.

The committed texture covers the viewport plus a margin of half a screen on each side (review A-04). It has the format `.r8Unorm`, because all content is gray. Thus two textures for a 13-inch iPad take about 45 MB. The composite pass turns the coverage into white on black in the `.bgra8Unorm` drawable. At the end of a stroke, the renderer draws only the new stroke into the committed texture. It never redraws all content at a pencil lift.

While the camera moves, the renderer shows the committed texture, translated and scaled (decision D-28). It draws a new committed texture (a build) only in one of these cases:

1. No front texture exists.
2. A load made the front texture old.
3. The zoom ratio of the front texture leaves the band 0.8 to 1.25.
4. The visible rectangle leaves the front texture minus a quarter of its margin.
5. The camera stays still for 6 frames and differs from the camera of the front texture. This build gives the exact zoom.

A build runs in chunks. Each frame draws at most 125,000 instances of the build (`RendererConfiguration.instanceBudgetPerFrame`), so no frame drops. A chunk of 250,000 instances took up to 9.4 ms of GPU time and made late frames. The screen keeps the old texture until the new texture is complete. The `SpatialGrid` limits all passes to the strokes that touch the texture area.

While the camera moves, the ink can look a little soft until the new texture is complete. This is accepted (D-28).

### 5.3 Stroke geometry on the GPU

Ink is white on black. The ink pipeline blends with `MTLBlendOperation.max` and the blend factors `one` and `one` (decision D-38, review A-06). The result of a pixel is the larger of the old value and the new value. Thus overlapping capsules do not get brighter, the anti-aliased edge of one capsule does not cut a notch into another capsule, and the draw order of strokes does not matter. A snapshot test draws a tight zigzag stroke and compares it with a reference image.

The GPU memory follows decision D-28.

The point arena:

1. All control points of a canvas live in one `MTLBuffer` with `.storageModeShared`, the arena. Apple GPUs share memory with the CPU, so the GPU reads the points directly.
2. A slab allocator (an allocator that hands out ranges of fixed size classes) manages the arena. Each stroke owns one range.
3. The arena stores only `x` and `y` of each point as a `float2`, 8 bytes per point, because the shader reads nothing else. The upload converts each `InkPoint` once. At the end of a stroke, the renderer copies the new points into the arena once.
4. The arena has a byte budget. Above the budget, the renderer removes the least recently drawn strokes first, with a margin so that a pan at the edge does not remove and add the same strokes again. It never removes a stroke by its distance to the viewport.

`Model` keeps a second copy of the points in `InkPoints` for commands, saves, and the export. The arena replaces the capsule buffers of the earlier design. For 20,000 strokes of 300 points, the `InkPoints` copy takes about 96 MB, and the arena takes about 48 MB.

Drawing (vertex pulling, which means that the shader reads the points from the buffer itself):

1. Each instance is one piece of a curve segment. The vertex shader reads 4 control points from the arena, evaluates the B-spline at the start and the end of the piece, and builds a capsule (a segment with round ends) as a quad. No capsule buffer exists.
2. The fragment shader computes the distance from the pixel to the segment and gives an anti-aliased edge with a `smoothstep` over plus or minus 1.06 pixels. This matches the edge of the PencilKit monoline (see [m2-plan.md](m2-plan.md) section 1).
3. Per frame, the CPU writes one small draw list for the visible strokes: the first point, the point count, the level of detail, the first instance, and the stroke origin minus the camera center as `Float`. One instanced draw covers many strokes. The vertex shader finds the stroke of an instance with a binary search over the first instances.

Level of detail:

- At low zoom, the draw list skips control points so that the points it uses are at least 1 pixel apart on the screen (`LevelOfDetail.minimumPixelSpacing`). At zoom 0.25, the 20,000 dense strokes of the performance tests then draw 300,000 instances instead of 560,000 at the 0.5 pixels of M2.
- At high zoom, each segment is cut into pieces so that the curve stays smooth. The number of pieces depends on the zoom, and a named limit bounds it.
- A stroke is cut into blocks of 64 segments (`DetailRuns`). Neighbor blocks with the same pieces per segment merge into one run, and each run gets its stride and its pieces from its own spacing. Thus one long segment sets the pieces of its own block only. A stroke whose blocks all have the same pieces stays one run with the detail of the whole stroke.
- Where the length rule gives more than one piece, the pieces can be fewer where the curve bends little. A segment of `L` pixels that turns by `t` radians, cut into `k` pieces, differs from its chords by about `L t / (8 k k)` pixels. The run takes the largest length times turn of its segments, and `k` keeps this error at or under `LevelOfDetail.maxPieceError`, 0.125 pixels. The bend never adds pieces. The renderer measures the bend of a block at the first draw that needs it, so the load of a canvas measures lengths only.
- Each run is one draw entry. At a boundary between two runs, the shader reads the real neighbor point of the stroke at the stride of the neighbor run, so the curves of the two runs meet exactly. At the ends of the stroke, it uses the mirrored phantom points (section 4.3).

Each stroke stores its origin in `Double` and its points as `Float` offsets from that origin. Per frame, the CPU computes the offset of the stroke from the camera in `Double`. The CPU converts it to `Float` only after the camera position is removed. Thus precision stays correct at any distance from the canvas origin.

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

Each loaded canvas has one `SpatialGrid`. The grid has square cells of 512 canvas points in a dictionary keyed by cell coordinates. Each cell holds the IDs of the strokes, text boxes, and cards whose bounds touch it. A query for a rectangle reads only the cells in that rectangle. A query has a limit: at zoom 0.25 on a 13-inch iPad, the viewport covers 5,504 by 4,128 canvas points. That is 11 by 9 cells, and at most 120 cells when the viewport does not align with the grid (review A-04).

## 6. Camera and navigation

### 6.1 Camera

`Camera` lives in `Geometry`, because `Model` (`DeviceState`) and `CanvasFeature` both use it.

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
3. Fill the page white (decision D-13).
4. Draw each stroke as one `CGPath` of cubic Bézier segments. The exporter converts each piece of the B-spline to one Bézier segment, which is exact (decision D-26). Use `setLineCap(.round)`, `setLineJoin(.round)`, the stroke width, and black.
5. Draw each text box in black with `CTFramesetter` and `CTFrameDraw`. Flip the text matrix for the PDF coordinate system.

The PDF contains no cards (decision D-13). The exporter does not draw card frames, titles, or child content. The content bounds in step 1 also ignore cards.

The exporter runs off the main actor. It reads a snapshot (a value copy), so it does not block drawing. The result goes to `UIActivityViewController`.

## 10. Limits

All limits live in one type, `Limits`, in `Model`. Code uses the names, never the numbers.

| Name | Value | Reason |
|---|---|---|
| `maxDepth` | 32 | Card tree depth (CARD-09). Bounds the recursion. |
| `maxPointsPerStroke` | 16,384 | Control points per stroke, about 68 s at 240 Hz. The converter splits a longer PencilKit stroke into several strokes (section 4.2). |
| `maxStrokesPerCanvas` | 200,000 | Upper bound for loops and memory. |
| `maxNodesPerCanvas` | 10,000 | Cards plus text boxes. |
| `maxTextLength` | 100,000 | Characters per text box. |
| `maxWorkspaces` | 1,000 | Workspace list. |
| `maxHistoryDepth` | 500 | Undo steps per canvas. |
| `minZoom`, `maxZoom`, `standardZoom` | 0.25, 8.0, 1.0 | Camera (CAN-04). |

If the user reaches a limit, the app shows a short message. It never crashes and never drops data in silence.

## 11. Concurrency

- Swift 6 language mode with complete strict concurrency in every target.
- UI types and the canvas run on the main actor. The renderer encodes its frames on a render thread (D-42, section 5.1). The main actor sends values to it and never waits for a frame.
- `SQLiteLibraryRepository` is an actor. It owns the only database connection that writes. All SQL goes through it.
- The canvas sends the changed rows to the repository and the IDs of changed strokes to the renderer. It never shares mutable state (see [data-model.md](data-model.md) section 8).
- PDF export runs in a `Task` off the main actor. Snapshots run inside the repository actor. They report progress to the main actor.
- No code on the main actor waits for disk.

## 12. Performance budgets

| Measure | Budget | How to measure |
|---|---|---|
| Pencil to ink | 13 ms goal, 20 ms limit | High-speed camera and the presented-time log (see [research.md](research.md) 3.4) |
| Frame time while drawing | Under 3 ms CPU from the pencil event to the end of encoding, under 4 ms GPU | `OSSignposter` intervals in an `XCTOSSignpostMetric` test |
| Dropped frames while drawing or panning | 0 per 10 s | Animation Hitches template |
| Open a workspace with 20,000 strokes | Under 300 ms to first frame | `XCTClockMetric` |
| Save after a stroke | Off the main actor, under 50 ms | Signpost |
| Memory for a canvas with 20,000 strokes | Under 300 MB | `XCTMemoryMetric` |

Performance tests run on a real iPad. If a measure is more than 10% worse than its baseline, the test fails.
