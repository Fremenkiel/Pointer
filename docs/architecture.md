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
| Frame timing | `CAMetalDisplayLink` on a render thread (D-42), and `UIUpdateLink` on the main thread for camera animations | The render thread gets each drawable without a block on the main thread (section 5.1). |
| PDF | Core Graphics PDF context, Core Text (D-139, D-140) | Vector output and real text. |
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
| `Persistence` | 1 | `Model`, `Geometry`, SQLite3 | `SQLiteLibraryRepository` (an actor), `WALCheckpointer` (an actor with a second connection, D-146), a small SQLite wrapper, row codecs, migrations, snapshots, restore. `PreviewStore`, which reads and writes the preview files as `Data` (D-107). |
| `Rendering` | 1 | `Model`, `Geometry`, Metal, ImageIO | `CanvasRenderer`, the point arena, shaders, the committed texture cache, text layout, the glyph atlas (D-81). The card previews and their PNG code (D-107). |
| `Export` | 1 | `Model`, `Geometry`, `Rendering` for `TextLayout` (D-140), Core Graphics, Core Text | `PDFExporter`. |
| `DesignSystem` | 1 | SwiftUI, UIKit | Color, spacing, size, and icon tokens. |
| `CanvasFeature` | 2 | Layer 0 and 1, PencilKit | `CanvasViewController`, `CanvasView`, the live `PKCanvasView`, `PencilKitStrokeConverter`, input routing, camera control, card navigation, text editing, top bars. |
| `WorkspaceFeature` | 2 | Layer 0 and 1 | Workspace selector, create, rename, delete. |
| `BackupFeature` | 2 | Layer 0 and 1 | "Back up now" command and restore. |
| `PointerApp` | 3 | All | Scene setup, dependency composition, routing between features. |

The script `Scripts/check-layers.swift` reads `swift package dump-package` for each package and the `import` lines of its sources. It fails the build on a forbidden import (see [code-of-code.md](code-of-code.md), rule ARCH-02). It also fails on third-party code (rule BUILD-03): a remote package, a local package outside `Packages/`, a binary target, or a prebuilt framework in the Xcode project.

Dependencies flow down. Features get repositories and services through their initializers. No singletons exist, except the ones that Apple provides.

## 4. Input pipeline

### 4.1 Touch routing

The canvas view holds the Metal view and one `PKCanvasView` on top of it. The `PKCanvasView` has a clear background and `drawingPolicy = .pencilOnly`. It never zooms or scrolls. It never becomes the first responder (`LiveCanvasView`). Thus a finger tap on it does not take the keyboard from the edit view of a text box. Some recognizers inside it take finger touches, for example the selection of PencilKit. Each of them waits for the finger tap and the long press of the canvas to fail. Pointer does not use the selection of PencilKit (D-10).

- With the pen tool, `.pencil` touches go to the drawing gesture recognizer of the `PKCanvasView`. PencilKit draws the live stroke.
- With the eraser tool or the text tool, the drawing gesture recognizer is off. `.pencil` touches go to the active tool through `PencilTouchObserver`, a gesture recognizer on the canvas view that never recognizes and works next to every other recognizer. It takes only the touches on the canvas surfaces, not on the buttons above them (F-06). During an erase, it reports the coalesced samples of each move. See decision D-34.
- `.direct` (finger) touches go to gesture recognizers with `allowedTouchTypes = [.direct]`: one-finger pan, two-finger pinch, tap, and long press.

The view sets `isMultipleTouchEnabled = true`. A finger that touches during a pencil stroke does not cancel the stroke. While the pencil draws, the pan and pinch gesture recognizers ignore the finger, so the camera does not move (decision D-36).

A palm guard keeps the palm away from the finger gestures (review A-14). iPadOS suppresses most palm touches while the pencil is near the screen, but not all. The finger gesture recognizers ignore a `.direct` touch in these cases:

1. The touch begins while a pencil touch is active.
2. The touch begins less than 150 ms after the last pencil touch ended. The value is a start value. Tune it on a device.
3. The `majorRadius` of the touch is larger than a palm threshold of 30 points (`PalmGuard.palmRadius`).

The guard affects the finger gestures only. A finger never draws in any case (TOOL-03), because the `PKCanvasView` uses `drawingPolicy = .pencilOnly`.

### 4.2 Pen strokes

PencilKit gives no samples before pencil lift. The pen tool works in these steps:

1. The `PKCanvasView` draws the live stroke at zoom 1 in view space. Its tool is a white monoline `PKInkingTool`. The pen width is 2 canvas points (decision D-37). The tool width is the pen width times the camera zoom, so the live stroke has the same size on the screen as the finished stroke. The canvas sets the tool at the hit test of each new touch, at a pencil down, and when the camera comes to rest, and only if the zoom changed, not at each frame of a pinch, a spring, or a flight (PERF-01, D-131). PencilKit takes the tool before `pencilBegan()` runs, so the hit test, which UIKit runs before any gesture recognizer gets the touch, sets it in time.
2. At pencil lift, `canvasViewDrawingDidChange(_:)` reports the new `PKStroke`.
3. `PencilKitStrokeConverter` reads the control points of `stroke.path` (decision D-26), applies `stroke.transform`, and converts each point from view space to canvas space with the camera (in `Double`). The converter takes the stroke width from the point sizes of the `PKStroke`, not from the tool width. A monoline point of size `s` draws a line `2 * (s - 2)` points wide (see [m2-plan.md](m2-plan.md) section 1). The result is a `Stroke` of the `Model`. Both steps are affine transforms, and an affine transform of the control points gives the same transform of the curve. Thus the conversion does not change the shape. The math lives in `Geometry` and `Model` (Tier A). `CanvasFeature` only reads the `PKStroke`.
   If the path has more than `Limits.maxPointsPerStroke` control points, the converter makes several strokes. Each new stroke starts with the last 3 control points of the stroke before it, so the curve continues without a gap or a kink. With `max` blending, the overlap does not show.
4. The renderer adds the stroke to the committed layer and asks for a frame.
5. After the presented handler of that frame runs, the canvas view removes the stroke from the `PKCanvasView`. Thus no frame shows the stroke twice or not at all.

The `PKDrawing` of the `PKCanvasView` holds at most the strokes that wait for the handoff. Pointer never stores PencilKit data.

The finished stroke must look the same as the live stroke (FEEL-03). One exception is accepted (D-61): at the pencil lift, PencilKit drops the end of a fast stroke from its own live ink, up to about 60 points. Pointer keeps the stroke that PencilKit gives. In the M1 hybrid spike, the product owner saw a clear difference in style and width at the handoff. M2 must fix it (see [plan.md](plan.md), M2). Possible causes to test:

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

The eraser has a radius of 8 view points. The radius stays the same on the screen at every zoom. The eraser is partial (decision D-06).

While the pencil moves, the eraser tool sends each sample in view space to the renderer, the coalesced samples included. The render thread stamps a capsule of the eraser radius from the sample before into a mask texture, so a fast pencil leaves no gap. The screen hides the ink under the stamps (section 5.2, D-66). The gesture changes no content and no stored row. A cancelled touch ends the mask and changes nothing.

At pencil lift, the eraser tool does these steps once (D-30, review A-08):

1. Convert the samples of the gesture to canvas space. Convert the radius to canvas units with the camera zoom.
2. Find the strokes whose bounds touch the bounds of the path, with one pass over the bounds of the live strokes. The only `SpatialGrid` of the canvas lives on the render thread.
3. For each of these strokes, `StrokeHitTest` finds the curve parameters where the distance to the path equals the eraser radius plus half the stroke width. The path covers a circle at each sample and the band between neighbor samples.
4. `StrokeSplitter` makes one new stroke for each part of the curve outside the path. Steps 3 and 4 run in up to 8 chunks on several threads. The parts get their IDs and clock values afterward, in order.
5. The tool emits one `EraseStrokes` command with the removed strokes, the new parts, and the area of the change. The area holds the path, the 3 old control points on each side of each cut, the 3 control points of each part next to a cut, and half the width. An end of a part at an end of the old stroke does not change. A stroke that leaves no part adds its whole bounds (F-07 of [m4-fix-plan.md](m4-fix-plan.md)). The renderer then redraws that area and clears the mask in the same frame.

The changes of one eraser gesture (pencil down to pencil up) form one undo step.

The stored points are control points, not points on the curve (decision D-26). A part keeps the control points of the old stroke that lie between its two cuts. At each cut, the point of the curve at the cut parameter becomes the new end point of the part (D-65). The end rule of section 4.3 then makes the part end exactly at the cut. The shape changes only in the two segments next to a cut. The change is at most half the distance between the new end point and the dropped control point (D-72). A part whose curve is shorter than the pen width is dropped. An erase can make the canvas go past `Limits.maxStrokesPerCanvas`, because an erase never fails. The pen then refuses new strokes with the limit message (D-71). The parts never take the canvas past `Limits.maxStrokesAfterErase`: an erase whose parts would pass it removes the strokes that it touches whole (D-73).

A tool change takes effect at the next pencil down. A stroke or an erase that runs ends with the old tool (D-70). The drawing gesture recognizer of the `PKCanvasView` is on only while the tool is the pen and the library can save.

### 4.5 Apple Pencil interaction

`CanvasViewController` installs one `UIPencilInteraction` and is its delegate.

Double tap (`pencilInteraction(_:didReceiveTap:)`):

| `preferredTapAction` | Action |
|---|---|
| `.switchEraser`, `.switchPrevious` | Switch between pen and eraser. If the current tool is text, switch to pen. |
| All other values | Nothing (D-130). |

Squeeze (`pencilInteraction(_:didReceiveSqueeze:)`): act on phase `.ended` only.

| `preferredSqueezeAction` | Action |
|---|---|
| `.ignore` | Nothing. |
| `.runSystemShortcut` | The app never receives it. |
| All other values | Show the tool palette at `squeeze.hoverPose?.location`. If the pose is `nil`, show it at the last pencil location. |

The palette is the tool bar of TOOL-07 (D-63). It holds pen, eraser, text, undo, and redo. The text tool has the SF Symbol `character.cursor.ibeam` (D-87). A button in the top left corner shows the current tool. A finger tap on it opens the same palette under the button (D-64). Thus every pencil and every squeeze setting can reach each tool. The palette is a popover. A tap on a tool picks it and closes the palette. Undo and redo keep it open. The canvas gives the button to `PointerApp`, which places it to the right of the workspace selector.

The mapping of user preferences to actions is decision D-130 for double tap and D-63 for squeeze. During a card flight, double tap and squeeze do nothing.

### 4.6 Hover

A `UIHoverGestureRecognizer` with `allowedTouchTypes = [.pencil]` shows a small gray dot at the tip for the pen and the text tool. For the eraser, the dot is a gray outline circle with the eraser radius (D-133). If `UIPencilInteraction.prefersHoverToolPreview` is `false`, the dot does not show (D-128). The dot is a `CAShapeLayer` in `CanvasView` above the live `PKCanvasView`, with implicit animations off, so a hover sample wakes no frame of the renderer (D-126). It hides at pencil down, at the end of the hover, and during a card flight. The recognizer runs together with every other recognizer, also the hover recognizers of `UIPencilInteraction` and PencilKit, so that it blocks no gesture. A shadow of PencilKit below the pencil can show beside it, and Pointer accepts it (D-127).

### 4.7 Finger gestures

| Gesture | Target | Action |
|---|---|---|
| One-finger pan | Canvas | Pan the camera. Deceleration after release. |
| Two-finger pinch | Canvas | Zoom about the midpoint of the two fingers. Pan at the same time. |
| Tap | Text box | Start editing (TOOL-06). |
| Tap | Card | Open the card (D-115), if no text box covers the card there. A tap while an edit runs only ends the edit. |
| One-finger pan | Pending card | Drag the card of the card button. At the lift, it joins the canvas with one undo step (D-117). The camera stays. |
| Long press | Card or text box | Context menu: rename (card), delete. A long press on empty canvas does nothing (D-117). |
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

The flight of a card is the exception (D-121). The render thread plays it by itself, so a blocked main thread does not stop it. `CameraFlight` in `Geometry` gives the camera of a flight from the time alone. The main thread gives the flight to the renderer once, with `CanvasRenderer.fly(_:)`. Each frame then takes the camera at the `targetTimestamp` of its `CAMetalDisplayLink` update and does not wait for the main thread. The main thread steps the same flight at the `modelTime` of its `UIUpdateLink`, for the logic only: the end callbacks, the input lock, and `isInCardTransition`. It sends no camera during the flight, and the next camera that it sends ends the flight on the render thread.

A build also has a time budget of 2 ms per frame on the render thread (`RendererConfiguration.buildTimeBudget`).

The live pen stroke does not use this frame loop (section 4.2). The eraser of M4 needs low latency. `UIUpdateLink` runs on the main thread only, so its low-latency settings do not apply to the render thread (D-42). The eraser therefore sends its samples through the inbox of the renderer. The render thread stamps them into the mask texture on the next frame (section 4.4, D-66).

### 5.2 Layers in a frame

Each frame draws these passes:

1. The committed layer: all finished strokes, text, and cards that are visible. Cards share the green channel with the text (D-96). This layer is a texture with twice the size of the drawable in each direction, as described below. The renderer reuses it while the camera and the content do not change.
2. The eraser mask, while an eraser gesture runs. The renderer makes the mask texture when the eraser becomes the tool and drops it when another tool becomes the tool, after the last gesture ends (D-78). A `.r8Unorm` texture of the size of the committed texture holds the eraser circles of the gesture. The composite pass hides the ink under them. At the pencil lift, the renderer redraws the area of the change in the committed texture and clears the mask (D-66). The mask uses the mapping of the front texture. If the front texture changes during a gesture, the next frame stamps all samples again.
3. Overlays: none. The hover dot is a layer of Core Animation, not a pass of the renderer (section 4.6, D-126).

The live pen stroke is not a pass of the renderer. The `PKCanvasView` on top draws it (section 4.2). While you draw, the renderer draws a frame only at the handoff of a stroke.

The committed texture covers the viewport plus a margin of half a screen on each side (review A-04). It has the format `.rg8Unorm`: the ink coverage in red, and the coverage of the text and the cards in green (D-82, D-96). A texture has twice the drawable size in each direction: 3,336 by 4,840 pixels (32.3 MB) on the 11-inch iPad and 4,128 by 5,504 pixels (45.4 MB) on the 13-inch iPad. Thus the two committed textures take about 65 MB and 91 MB. The eraser mask has one channel of the same size and exists only while the eraser is the tool (D-78). With it, the textures take about 81 MB and 114 MB. The ink passes write red only, and the text passes write green only. The composite pass mixes the canvas color and white in the `.bgra8Unorm` drawable, with the larger coverage of the two channels as weight (D-106). `RendererConfiguration.background` holds the canvas color. At the end of a stroke, the renderer draws only the new stroke into the committed texture. It never redraws all content at a pencil lift.

While the camera moves, the renderer shows the committed texture, translated and scaled (decision D-28). It draws a new committed texture (a build) only in one of these cases:

1. No front texture exists.
2. A load made the front texture old.
3. The zoom ratio of the front texture leaves the band 0.8 to 1.25.
4. The visible rectangle leaves the front texture minus a quarter of its margin.
5. The camera stays still for 6 frames and differs from the camera of the front texture. This build gives the exact zoom.

An erase, and an undo or a redo that removes ink, cannot subtract ink from the texture, because the ink pipeline blends with `max`. The renderer then clears the changed rectangle of the front texture, and of a running build, with a scissor rectangle. It draws again the strokes that the `SpatialGrid` finds in it (D-66). Each stroke draws only the segments that can touch the rectangle. For an erase and its undo and redo, the rectangle is the area of the eraser path, and the added strokes are not drawn in full, because their ink outside the area is on the screen already. For other changes, it is the bounds of the removed strokes.

A build runs in chunks. Each frame draws at most 125,000 instances of the build (`RendererConfiguration.instanceBudgetPerFrame`), so no frame drops. A chunk of 250,000 instances took up to 9.4 ms of GPU time and made late frames. The screen keeps the old texture until the new texture is complete. The `SpatialGrid` limits all passes to the strokes that touch the texture area.

While the camera moves, the ink can look a little soft until the new texture is complete. This is accepted (D-28).

### 5.3 Stroke geometry on the GPU

Ink is white on the canvas color (CAN-01, D-106). The ink pipeline blends with `MTLBlendOperation.max` and the blend factors `one` and `one` (decision D-38, review A-06). The result of a pixel is the larger of the old value and the new value. Thus overlapping capsules do not get brighter, the anti-aliased edge of one capsule does not cut a notch into another capsule, and the draw order of strokes does not matter. A snapshot test draws a tight zigzag stroke and compares it with a reference image.

The GPU memory follows decision D-28.

The point arena:

1. All control points of a canvas live in the arena: a list of `MTLBuffer` objects of 16 MB with `.storageModeShared`. Apple GPUs share memory with the CPU, so the GPU reads the points directly. The arena grows by one buffer and never copies points.
2. A slab allocator (an allocator that hands out ranges of fixed size classes) manages the arena. The 32 size classes grow by 1.25, from 16 to 16,384 points. Each stroke owns one range, and a range never crosses a buffer.
3. The arena stores only `x` and `y` of each point as a `float2`, 8 bytes per point, because the shader reads nothing else. The upload converts each `InkPoint` once. At the end of a stroke, the renderer copies the new points into the arena once.
4. The arena has a byte budget. Above the budget, the renderer removes strokes that were not drawn recently, with a margin so that a pan at the edge does not remove and add the same strokes again. A clock sweep (a hand that walks the resident strokes and gives each recently drawn stroke a second chance) picks them. It never removes a stroke by its distance to the viewport, and never a stroke that a frame in flight can still read.

`Model` keeps a second copy of the points in `InkPoints` for commands, saves, and the export. The arena replaces the capsule buffers of the earlier design. For 20,000 strokes of 300 points, the `InkPoints` copy takes about 96 MB, and the arena takes about 48 MB.

Drawing (vertex pulling, which means that the shader reads the points from the buffer itself):

1. Each instance is one piece of a curve segment. The vertex shader reads 4 control points from the arena, evaluates the B-spline at the start and the end of the piece, and builds a capsule (a segment with round ends) as a quad. No capsule buffer exists.
2. The fragment shader computes the distance from the pixel to the segment and gives an anti-aliased edge with a `smoothstep` over plus or minus 1.06 pixels. This matches the edge of the PencilKit monoline (see [m2-plan.md](m2-plan.md) section 1).
3. Per frame, the CPU writes one small draw list for the visible strokes: the first point, the point count, the level of detail, the first instance, and the stroke origin minus the camera center as `Float`. One instanced draw per arena buffer covers many strokes: the encoder groups the entries of a pass by buffer. The vertex shader finds the stroke of an instance with a binary search over the first instances. The draw list of a frame holds `RendererConfiguration.drawListCapacity` entries. If the new strokes or the strokes of a redraw do not fit, the next frames draw the rest. A redraw clears its area only in its first frame. The handoff of new strokes waits for the frame that draws the last of them (F-04, F-05 of [m4-fix-plan.md](m4-fix-plan.md)). If the clipped entries of a stroke in a redraw do not fit, the stroke draws its whole runs, and the scissor keeps the same pixels.

Level of detail:

- At low zoom, the draw list skips control points so that the points it uses are at least 1 pixel apart on the screen (`LevelOfDetail.minimumPixelSpacing`). At zoom 0.25, the 20,000 dense strokes of the performance tests then draw 300,000 instances instead of 560,000 at the 0.5 pixels of M2.
- At high zoom, each segment is cut into pieces so that the curve stays smooth. The number of pieces depends on the zoom, and a named limit bounds it.
- A stroke is cut into blocks of 64 segments (`DetailRuns`). Neighbor blocks with the same pieces per segment merge into one run, and each run gets its stride and its pieces from its own spacing. Thus one long segment sets the pieces of its own block only. A stroke whose blocks all have the same pieces stays one run with the detail of the whole stroke.
- Where the length rule gives more than one piece, the pieces can be fewer where the curve bends little. A segment of `L` pixels that turns by `t` radians, cut into `k` pieces, differs from its chords by about `L t / (8 k k)` pixels. The run takes the largest length times turn of its segments, and `k` keeps this error at or under `LevelOfDetail.maxPieceError`, 0.125 pixels. The bend never adds pieces. The renderer measures the bend of a block at the first draw that needs it, so the load of a canvas measures lengths only.
- Each run is one draw entry. At a boundary between two runs, the shader reads the real neighbor point of the stroke at the stride of the neighbor run, so the curves of the two runs meet exactly. At the ends of the stroke, it uses the mirrored phantom points (section 4.3).

Each stroke stores its origin in `Double` and its points as `Float` offsets from that origin. Per frame, the CPU computes the offset of the stroke from the camera in `Double`. The CPU converts it to `Float` only after the camera position is removed. Thus precision stays correct at any distance from the canvas origin.

### 5.4 Text

The renderer draws text from a glyph atlas (D-29, D-81). `TextLayout` in `Rendering` lays out each text box with Core Text (`CTTypesetter`), with the attributes of the edit view: SF Mono, a fixed line height, and word wrap at the width of section 7 (D-84). Each glyph is one quad from the atlas. The atlas keys a glyph by its font, its glyph ID, and its scale, so the glyphs of fallback fonts work too. An emoji draws as a white shape, because the canvas has no color. Core Text draws the glyphs into one atlas per scale. The scale is the zoom times the display scale, rounded up to the next power of two. The atlas cache has a byte budget, not a count: `RendererConfiguration.glyphAtlasByteBudget`, 16 MB as a start value. Past it, the page that a frame used least recently goes first. The size of a text box does not change the size of the cache (review A-10). A table holds the places of the SF Mono glyphs of each scale, so most glyphs need no hash lookup.

The text boxes of a load are laid out off the render thread, in up to 8 chunks on several threads (D-92). The first frame with the strokes does not wait for them, and the text shows a few frames later. An edit of a box during that time wins over the loaded box. A build draws the ink first and then the text, in the same time budget per frame (`RendererConfiguration.buildTimeBudget`). A frame writes at most `RendererConfiguration.glyphCapacity` (65,536) glyph quads. A change of a text box clears the green channel of its old and its new bounds and draws the text boxes there again.

While a text box is in edit mode, the renderer hides it. A `UITextView` sits at the same place, with the same font at 17 points times the zoom, and without a scale transform (D-85). A camera change moves it, and a zoom change lays out its text again. During a pinch, it uses a scale transform from its last layout. A spring back to a zoom limit after the pinch counts as a part of the pinch. When the pinch and its spring end, it lays out the text at the new size.

Text does not join the eraser mask (D-66, D-82). The committed textures hold the ink in their red channel and the text in their green channel. The eraser mask hides the red channel only.

The text font is SF Mono, 17 points at zoom 1.0 (decision D-15).

### 5.5 Cards

A card on its parent canvas has these parts:

- A rounded rectangle with a 1-point border in gray and a body in a lighter gray than the canvas (D-116). The border and the body are coverage values below 1 (`DesignSystem.Color.cardBorder` and `DesignSystem.Color.cardFill`). The preview is cut to the rounded rectangle.
- The optional title, above the top-left corner.
- A preview of the child canvas inside the frame.

The renderer draws cards into the green channel of the committed textures, with the text (D-96). A build and a redraw draw them as they draw text, inside the same time budget. A card adds about 10 quads: the frame, the preview, and the glyphs of the title. The eraser mask hides the red channel only, so it never hides a card.

Layer order on a canvas, from bottom to top: cards, ink, text boxes (decision D-16). The composite takes the larger coverage of the two channels, and a card has no fill. Thus the screen shows the same image as cards drawn below the ink.

The preview is a gray 8-bit PNG per child canvas in `Caches/Pointer/previews/<canvas-id>.png` (D-97). The app writes it when you leave the child canvas, because a canvas changes only while it is on the screen (STO-01). A leave is the up button, the pinch-out, a workspace switch, or the move to the background (D-111). iOS refuses work on the GPU in the background, so the render for the background starts when the scene resigns active. The child stays on the screen until its render ends, because the render runs on its frames. At a leave, the parent shows the new image at once, without a read of the file. `Rendering` encodes and decodes the PNG with ImageIO, and `PreviewStore` in `Persistence` reads and writes the file as `Data` (D-107). The preview shows the region of the child that the open camera of section 6.2 shows, cut to the aspect of the card (D-98). It shows content one level deep. Deeper cards show as empty frames. The renderer reads the files of the visible cards off the main actor, after the first frame, as it lays out the text (D-92). A cache with a byte budget holds the decoded previews, 8 MB as a start value. The size comes in steps of 128, 256, and 512 pixels, from the size of the card on the screen. If a file is missing, the app loads that child canvas alone off the main actor and draws its preview. `PreviewMaker`, an actor on its own serial queue, draws it. The app keeps one maker, so all such previews share one `InkResources`. The maker draws only the strokes, cards, and text boxes that touch the region of the preview, and it draws the strokes in passes whose point arena keeps `RendererConfiguration.previewArenaByteBudget`, 32 MB (D-157). A preview of a D-56 child took 0.029 to 0.037 s and a peak memory growth of 90 to 96 MB, against 0.187 s and 202 MB before the cut. A restore (M9) clears the folder.

A new card is 320 by 224 canvas points at each zoom (D-118). It comes from the card button, centered on the left edge of the screen, and has no title (D-101, D-117). A pending card that no drag placed joins the canvas where it shows at a leave, a workspace switch, the open of a card, or the move to the background (D-123). "Rename" opens an alert with a text field, as the workspace rename does. Version 1 has no resize of a card (D-102).

### 5.6 Spatial index

The stroke store of the renderer holds the one `SpatialGrid` of a loaded canvas. A second grid with the same cells holds the text boxes (M5). In M6, cards get a grid with their renderer. The canvas finds the strokes of an eraser path with one pass over the bounds of its live strokes (section 4.4). The grid has square cells of 512 canvas points in a dictionary keyed by cell coordinates. Each cell holds the slots of the strokes whose bounds touch it. A query for a rectangle reads only the cells in that rectangle. A query has a limit: at zoom 0.25 on a 13-inch iPad, the viewport covers 5,504 by 4,128 canvas points. That is 11 by 9 cells, and at most 120 cells when the viewport does not align with the grid (review A-04).

## 6. Camera and navigation

### 6.1 Camera

`Camera` lives in `Geometry`, because `Model` (`DeviceState`) and `CanvasFeature` both use it.

```swift
struct Camera: Equatable, Sendable {
    var center: Point     // canvas space, Double
    var zoom: Double      // view points per canvas point
}
```

The limits are `Limits.minZoom = 0.25`, `Limits.maxZoom = 8.0`, and `Limits.standardZoom = 1.0`. They apply to the root canvas. A canvas inside a card has the zoom range 1...1 (D-119). `CameraController` turns pan and pinch input into camera changes. It also applies deceleration and the rubber band below the minimum zoom.

The camera of each canvas is stored in the device state, not in the library (see [storage.md](storage.md)). The app reads it only at launch and at a workspace switch, for the deepest canvas of the stored path (WS-04). An open by a tap, the up button, or a pinch-out uses the cameras of sections 6.2 and 6.3 (D-99, D-115).

### 6.2 Open a card

1. The user opens a card with a finger tap (decision D-115).
2. The controller animates the camera of the parent until the card frame covers the screen (D-98). The animation takes 0.35 s with a spring curve. During it, the parent fades out, because its ink and its text lie on top of the card (D-16). Text and cards share the green channel, so the whole parent composite fades. A card pass draws the opened card on top at full weight (D-108). At the start of the animation, the parent copies its frame into one `.r8Unorm` texture of the drawable size. Then it frees its committed textures and the eraser mask. The animation draws this frozen copy (D-110). The render thread computes the camera and the parent weight of each frame from the flight, `1 - progress` for an open, so the load of the child on the main thread does not stop the animation (D-121, section 5.1).
3. The child canvas loads during the animation. Its camera starts at the standard zoom, centered on the content bounds of the child. If the child is empty, the camera centers on the origin.
4. When the animation ends and the first frame of the child is ready, the child replaces the preview with a crossfade of 0.1 s.
5. The swap has no visible jump. The child shows W by H view points at zoom 1. A card of w by h parent points covers the screen at the scale k = max(W / w, H / h). The preview shows the child region of w × k by h × k points around the center of the open camera, so the preview and the first frame of the child show the same content at the same size.

### 6.3 Leave a card

There are two ways to leave a card:

- Up button. The tap starts the load of the parent. In the same time, the controller moves the child camera to the camera of the open (section 6.2). When both are done, the animation starts (D-109). Then it shows the parent canvas with the camera on the card center at the standard zoom, and plays the open animation in reverse: the child shrinks into the card frame. The render thread computes the camera and the parent weight, `progress`, of this flight, as in section 6.2 (D-121).
- Pinch out. A canvas inside a card has the zoom range 1...1, so the screen shows no zoom (D-119). The zoom of the fingers continues below 1 with resistance (rubber band), and it drives only the exit. The controller shows the child at zoom 1 as a shrinking card over a faded image of the parent. The image is the frozen copy of the open (section 6.2). It exists only for the direct parent of an open in this run of the app. Without it, the pinch below `minZoom` starts the load of the parent. It shows the canvas color until the first frame of the parent (D-109). If the fingers lift when the zoom of the fingers, without the rubber band, is under `0.7` times zoom 1, the controller plays the minimize animation and shows the parent at the standard zoom (D-104). The animation also moves the child camera to the camera of the open, as the up button does, so that the shrinking child ends at the region of the preview (D-109). The render thread computes the exit progress of this animation from the zoom of the flight, with the formula of the pinch (D-121). At the end, the child image crossfades to the preview. Both show the child at zoom 1. Otherwise, the card springs back to full screen.

On the root canvas, the rubber band springs back. No transition happens (CARD-06). If the pencil touches during a pinch past a zoom limit, the camera holds while the pencil draws, and the spring back starts after the stroke is handed off, or at the lift for the eraser and the text tool (D-135).

A workspace switch during an open or a leave ends it. The screen that the open or the leave added leaves the container with its renderer, and the switch shows the canvas of the new workspace (WS-02). A failed load of the new screen, or a first frame later than 5 s, also removes the added screen and shows a message.

The threshold is `0.7`. The start value was `0.6`, and the product owner asked for an earlier leave on the iPad on 2026-10-22. The shown zoom is a poor measure: with the rubber band exponent of 0.35, a threshold of 0.7 on the shown zoom needs the fingers to close to 36 % of their start distance (D-104).

### 6.4 Navigation state

`NavigationPath` in `Model` holds the workspace and the path from the root canvas to the current canvas as a list of card IDs. The list has a limit of `Limits.maxDepth = 32`. The root canvas is level 0, so a list of 32 cards reaches level 32, and the card button there is refused with a message (D-95). If the list is not empty, the up button shows. At launch, the app cuts the stored path before the first card that is not valid (D-112). A valid card is live, and its `canvasID` is the canvas above it.

## 7. Text boxes

- Create: with the text tool active, a pencil tap on empty canvas makes a new text box at the tap point and starts editing. The tool stays the text tool (D-87).
- Edit: a `UITextView` (TextKit 2) appears at the place of the box. Scribble works without extra code. The text view has its own undo while you edit. With the text tool, a pencil tap on a box starts its edit. With any tool, a finger tap on a box starts its edit (TOOL-06). A pencil movement that is not a tap does nothing with the text tool (D-87).
- End: a tap outside the box, a change of tool, a workspace switch, or the move to the background ends editing. A change of tool ends it at once, also while D-70 waits for the next pencil down (D-87). The canvas records one step for the edit (D-86): `AddTextBox` for a new box with text, `EditText` for a changed box, and `DeleteNode` for an existing box that ends empty. A new box that ends empty and a box without a change record no step.
- Delete: a long press on a box without a drag opens a menu with "Delete" (TOOL-08, D-89). It records one `DeleteNode` step.
- Size: the width grows with the longest line, up to 640 canvas points (`TextStyle.maxWidth`). Longer lines wrap. The height grows with the text. The size is not stored (D-83).
- Content: plain text only. No rich text, no links.

## 8. Undo and redo

Undo uses the `History` type from `Model`. It does not use `UndoManager` for canvas content, because `History` is a pure value type that unit tests can cover.

- Each canvas has its own `History` while the app runs (decision D-12).
- Each user action becomes one `CanvasCommand`. Each command has an `apply` function and a `revert` function on the canvas content. Both functions are pure.
- Commands hold the `Stroke` values that they add or remove (D-68). A copy of a stroke copies one reference to its points, so the history holds no second copy of the points.
- `AddStroke` adds a stroke. Its revert removes the stroke from the content and writes an erase record for it. A redo sets `isDeleted` on that record.
- Commands: `AddStroke`, `EraseStrokes` (removed strokes plus added parts), `AddTextBox`, `EditText`, `MoveNode`, `AddCard`, `DeleteNode`, `RenameCard`. `MoveNode` and `DeleteNode` hold a node: a text box or a card (D-103). A text box has no resize, because its size comes from its text (D-83). A card has no resize in version 1 (D-102). A move of a card to another parent is not in version 1.
- A delete is a tombstone, not a removal (see [data-model.md](data-model.md)). Thus an undo of a delete only clears the tombstone.
- The history has a limit of `Limits.maxHistoryDepth = 500` steps per canvas. The oldest step is dropped first.
- The history of one canvas holds at most `Limits.maxHistoryPointsPerCanvas` (4,000,000) control points, and the histories of all sessions hold at most `Limits.maxHistoryPointsInSessions` (16,000,000) (D-76). A step counts the points of the strokes that it holds, and one point for each code point of the texts that it holds (D-88). Past the canvas budget, the oldest steps go, also a new step that alone passes the budget. Past the session budget, the oldest steps of the least recently used session go first. The session erase records of the strokes in dropped steps go with them, unless a kept step holds the stroke too.
- A new command clears the redo list.
- A hardware keyboard gets Command-Z and Shift-Command-Z through `UIKeyCommand`.
- `PointerApp` holds `CanvasSessions`: for each canvas, the `History` and the erase records of the session. A new load of a canvas reads no erase record, so the canvas takes the records of its session back at the open (`CanvasContent.adoptSessionRecords(_:)`). The shown canvas keeps its session with `endSession()` before the app makes the next canvas screen, so that a screen of the same canvas finds the steps of the visit (F-02 of [m4-fix-plan.md](m4-fix-plan.md)). The open of a canvas takes its session out of `CanvasSessions`, so the shown canvas is the only owner of its history, and its first step copies nothing (M-03). A deleted workspace loses its session, also when its canvas is on the screen. A tap on the workspace of the shown canvas makes no new screen. A newer switch cancels the load of an older one, so quick switches load only the last canvas (F-13).
- An undo or a redo sends its change to the renderer and its rows to the library, and asks for a save. The renderer change of an `EraseStrokes` step redraws only the area of its eraser path.
- An erase, and an undo or a redo of `EraseStrokes` or `AddStroke`, give the change to the renderer before the model step, so the render thread starts about one model step earlier (D-122). The change comes from the command alone. If the model step then throws, the renderer gets the strokes of the change back as the model holds them, and the error goes to the log. For one frame, the screen can show the wrong ink. The other commands give their change after the model step, from the rows.

In edit mode, the undo and redo of the buttons, the palette, and Command-Z go to the text view. If it has no step, they are off (D-86).

## 9. PDF export

`PDFExporter` takes a `CanvasContent` value (all live strokes, text boxes, and cards of one canvas) and returns PDF `Data` (D-138).

1. Compute the page bounds: the union of `Stroke.bounds` and the rectangle of each text box, from its origin and `TextLayout.size` (D-141). Add a margin of 48 points. Cards do not count. If no stroke and no text box exist, the export makes no PDF, and the canvas shows a message (D-142).
2. Make one page with the size of the bounds in a Core Graphics PDF context, `CGContext(consumer:mediaBox:_:)` (D-139). If a side is longer than 14,400 points (the PDF page limit of 200 inches), one uniform scale fits the whole page, the line widths included (D-142).
3. Fill the page white (decision D-13).
4. Draw each stroke as one `CGPath` of cubic Bézier segments. The exporter converts each piece of the B-spline to one Bézier segment, which is exact (decision D-26). Use `setLineCap(.round)`, `setLineJoin(.round)`, the stroke width, and black.
5. Draw each text box in black. `TextLayout` gives the font, the line ranges, and the baselines, so the PDF has the lines of the screen. Draw each line with `CTLineDraw`, so that the PDF keeps the text and you can select and search it (D-140). Color emoji stay as the system draws them: bitmap images with searchable text (D-142). Flip the text matrix for the PDF coordinate system.

The PDF contains no cards (decision D-13). The exporter does not draw card frames, titles, or child content.

The exporter runs off the main actor. It reads a copy of the content, so it does not block drawing. The result goes to `UIActivityViewController` through an `NSItemProvider`, without a file. The item provider names the PDF after the title of the card, or after the title of the workspace on the root canvas and for a card without a title (D-143).

## 10. Limits

All limits live in one type, `Limits`, in `Model`. Code uses the names, never the numbers.

| Name | Value | Reason |
|---|---|---|
| `maxDepth` | 32 | Card tree depth (CARD-09). Bounds the recursion. |
| `maxPointsPerStroke` | 16,384 | Control points per stroke, about 68 s at 240 Hz. The converter splits a longer PencilKit stroke into several strokes (section 4.2). |
| `maxStrokesPerCanvas` | 200,000 | The pen refuses a new stroke at this count. |
| `maxStrokesAfterErase` | 210,000 | Upper bound for loops and memory. Only the parts of an erase go past `maxStrokesPerCanvas` (D-71, D-73). |
| `maxNodesPerCanvas` | 10,000 | Cards plus text boxes. |
| `maxTextLength` | 10,000 | Unicode code points per text box (D-29, D-57). |
| `maxWorkspaces` | 1,000 | Workspace list. |
| `maxTitleLength` | 120 | Unicode code points per workspace title or card title (D-57). |
| `maxSortKeyLength` | 64 | Digits of a sort key. A longer key needs a rebalance. |
| `minCardWidth`, `minCardHeight` | 64, 48 | The smallest card, in canvas points. |
| `maxHistoryDepth` | 500 | Undo steps per canvas. |
| `maxHistoryPointsPerCanvas` | 4,000,000 | Control points in the undo history of one canvas, about 67 MB (D-76). |
| `maxHistoryPointsInSessions` | 16,000,000 | Control points in the histories of all sessions, about 270 MB (D-76). |
| `strokeOverlapPoints` | 3 | Control points that two neighbor strokes of one long path share, so that the curve continues without a gap (section 4.2). |
| `minZoom`, `maxZoom`, `standardZoom` | 0.25, 8.0, 1.0 | Camera (CAN-04). |
| `gridCellSize` | 512 | The side of a cell of the grids of strokes, text boxes, and cards, in canvas points (section 5.6). |
| `maxGridCellsPerItem` | 4,096 | The most grid cells that one item can touch. It bounds the loops of `SpatialGrid.insert` and `remove` (FLOW-03). The load refuses a stroke or a card past it as a damaged row (D-158). The largest item that the app can make is a text box of 10,000 line breaks, at most 1,179 cells. A text box needs no check at the load, because its text length and `TextStyle.maxWidth` bound its size. |

The split of an erase has two bounds of its own in `Eraser`, because only the split uses them: `minimumChunk` (64), the fewest candidates of one thread, and `maxChunks` (8), the most threads. The iPad Pro (M4) has 4 performance cores.

If the user reaches a limit, the app shows a short message. It never crashes and never drops data in silence.

## 11. Concurrency

- Swift 6 language mode with complete strict concurrency in every target.
- UI types and the canvas run on the main actor. The renderer encodes its frames on a render thread (D-42, section 5.1). The main actor sends values to it and never waits for a frame.
- `SQLiteLibraryRepository` is an actor. It owns the connection that writes the rows, and all SQL of the library goes through it. `WALCheckpointer`, an actor with a second connection, runs only the passive checkpoints (D-146). The actor has a custom serial executor on a `DispatchSerialQueue` (SE-0392), so the blocking SQLite calls run on their own thread and never hold a thread of the shared pool (review A-13).
- The canvas sends the changed rows to the repository, in order through one channel (F-11), and the change of a step to the renderer: the IDs of the removed strokes, the added `Stroke` values, and the area to redraw (`CanvasRenderer.change(removing:adding:area:)`). It never shares mutable state (see [data-model.md](data-model.md) section 8).
- PDF export runs in a `Task` off the main actor. Snapshots run in `SnapshotWriter`, an actor with its own read-only connection and its own serial executor, so saves continue while a snapshot runs (D-32). Both report progress to the main actor.
- `DeviceStateStore` owns `device.sqlite` with its own connection and its own serial executor (D-53). Thus four actors touch SQLite, each on its own queue, and none of them on the shared pool.
- At launch, `PointerApp` opens the device state, the snapshot writer, and the library in this order, and then makes the one clock of the app (data-model.md section 4). At the move to the background, it writes the pending rows and the device state with extra time from `UIApplication.beginBackgroundTask`. A custom `UIWindow` notes the time of the last touch. After 5 seconds without a touch and with no pending rows, the app sends the idle signal to the snapshot writer (storage.md section 7.2).
- A restore replaces the composition (D-148). The old composition saves the work on the screen, writes the pre-restore snapshot, ends its screens, and lets `SQLiteLibraryRepository.restore(from:stop:)` copy the snapshot on the executor of the repository, with extra time from `beginBackgroundTask` (D-164). Then `SceneDelegate` makes a new composition with a new root view, and its `start(after:)` opens the files as at launch. The new clock continues after the larger of the old clock and the restored `lastTimestamp` (D-152). `SnapshotImport` and `PreviewMaker` are actors with their own serial executors too.
- No code on the main actor waits for disk.

## 12. Performance budgets

| Measure | Budget | How to measure |
|---|---|---|
| Pencil to ink | 13 ms goal, 20 ms limit | High-speed camera and the presented-time log (see [research.md](research.md) 3.4) |
| Frame time while drawing | Under 3 ms CPU from the pencil event to the end of encoding, under 4 ms GPU | `OSSignposter` intervals, and the medians of `EraserFramePerformanceTests` and `FrameLoopTests` on the device |
| Dropped frames while drawing or panning | 0 per 10 s | Animation Hitches template |
| Open a workspace with 20,000 strokes | Under 300 ms to first frame | `CanvasOpenPerformanceTests`: the open on the screen, timed with `ContinuousClock` |
| Save after a stroke | Off the main actor, under 50 ms | Signpost |
| Memory of the open of the D-56 canvas (20,000 strokes, 10,000 nodes) | Under 380 MB on the 11-inch iPad (D-93) | `CanvasMemoryPerformanceTests`: the peak growth of `os_proc_available_memory` during the open. The views of the test host leave the window, and the measure starts after 1.5 s of steady memory. |
| Memory peak of an open from the D-56 canvas into a D-56 child | Under 670 MB on the 11-inch iPad (D-110) | `TransitionMemoryPerformanceTests` alone: the growth over the steady memory before the parent opened |
| Memory peak of the leave from that child back to the D-56 parent | Under 720 MB on the 11-inch iPad (D-110) | The same test. The parent and the child are both loaded (D-109). The allocator of the process keeps about 165 MB of the heap of the parent that closed after the open, and the next load reuses it. |
| Frame with 4 new eraser samples | Under 3 ms CPU, under 4 ms GPU | `EraserFramePerformanceTests` |
| PDF export of the D-56 canvas | Under 8.5 s on the 11-inch iPad, off the main actor (D-144). The memory is recorded and has no budget (D-145). | `ExportPerformanceTests`: the time of `PDFExporter.pdfData(of:)` in a detached task, and the peak growth of `os_proc_available_memory` after 1.5 s of steady memory |
| PDF export of 200,000 handwriting strokes | Under 17 s on the 11-inch iPad (D-144, D-145) | The same test |
| Erase, undo, or redo of 1,000 strokes in one gesture | Under 33 ms, 16 ms as a goal (D-75) | `EraseUndoPerformanceTests`: from the lift or the call until the GPU completes the first frame that holds the result (D-74) |

Performance tests run on a real iPad. If a measure is more than 10% worse than its baseline, the test fails.
