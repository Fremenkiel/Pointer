# M2 work plan: ink on one canvas

This document breaks milestone M2 of [plan.md](plan.md) into tasks. It also records the facts that the work found. The acceptance criteria stay in [plan.md](plan.md).

## 1. Facts found before the work

The tests ran PencilKit on macOS 26 and in the iPad Pro 13-inch (M5) simulator with iPadOS 26. Both gave the same results.

1. Curve end rule. `PKStrokePath` is a uniform cubic B-spline with one segment between each pair of neighbor control points. The parameter runs from 0 to `count - 1`, and the curve passes through the first and the last control point. At each end, the spline uses a phantom point that mirrors the second point through the end point: `P[-1] = 2 P[0] - P[1]` and `P[n] = 2 P[n-1] - P[n-2]`.
2. Monoline width. PencilKit draws a monoline stroke `2 * (size.width - 2)` points wide, where `size.width` is the size of a `PKStrokePoint`. The force, the altitude, `size.height`, and the image scale do not change the width. A point size of 2 or less draws nothing. The width of the `PKInkingTool` is not the drawn width. This explains the width difference of the M1 spike, which used half the tool width as the capsule radius.
3. Monoline edge. The anti-aliased edge of PencilKit is about 2 pixels wide at every scale and follows a smooth curve. A `smoothstep` over plus or minus 1.06 pixels around the edge matches the measured values to within 4 of 255.
4. White. A white monoline stroke in the light interface style has the value 255 in each channel at its center (D-38).
5. `PKInkingTool.InkType.monoline.validWidthRange` is `0.5...4.0`. `PKInkingTool(width:)` keeps a width outside the range, for example 16. The device test of acceptance 5 shows whether the live stroke clamps it.

From fact 2, the converter takes the stroke width from the point sizes of the live stroke, not from the tool width. The Metal stroke then has the width that PencilKit drew, at every zoom (FEEL-03).

## 2. Tasks

### 2.1 Geometry (Tier A)

1. `Point`, `Vector`, `Size`, `Rect`, and `Transform` (2D affine) in `Double`.
2. `Camera` with `center` and `zoom`, the conversion between view space and canvas space, zoom about a view point, and the zoom clamp.
3. `SpatialGrid`: square cells of 512 canvas points, insert, remove, and a query that visits at most `maxQueryCells` cells.
4. `StrokeCurve`: the B-spline of fact 1, with evaluation at a parameter, the segment count, and the four control points of a segment.
5. Unit tests for each public function.

### 2.2 Model (Tier A)

1. `StrokeID`, `CanvasID`, and `DeviceID` as separate wrapper types (D-17).
2. `UUIDVersion7` from an injected clock and an injected random source (D-31, RFC 9562 section 5.7).
3. `HybridTimestamp` and `HybridClock` with an injected wall clock (data-model.md section 4).
4. `InkPoint` (16 bytes), `InkPoints` (the one reference type), and `Stroke` with its bounds.
5. `ControlPointSample` and `StrokeFactory`: transform view-space control points to canvas space, set the origin, and split a path above `Limits.maxPointsPerStroke` into strokes that overlap by 3 points.
6. `CanvasContent` with the strokes only. Cards, text boxes, and erase records come in M4 to M6.
7. `Limits` with all values of architecture.md section 10.
8. Unit tests, with parameterized tests at each limit.

### 2.3 Rendering (Tier B)

1. `SlabAllocator`: a pure type that hands out point ranges in size classes of 16 to 16,384 points.
2. `PointArena`: one shared `MTLBuffer` that grows up to a byte budget, and least-recently-drawn eviction with a margin.
3. Shaders: the B-spline capsule vertex shader with vertex pulling, the fragment shader with the edge of fact 3, and a composite shader.
4. Pipelines: `max` blending for ink (D-38), an `.r8Unorm` committed texture, and a `.bgra8Unorm` sRGB drawable.
5. `DrawListBuilder`: the visible strokes, the level of detail (control points at least 0.5 pixels apart), and the pieces per segment at high zoom.
6. `CommittedLayer`: a texture with a margin of half a screen on each side. It redraws in chunks with a fixed budget per frame. At a handoff, it draws only the new stroke.
7. `CanvasRenderer`: the `CAMetalLayer` setup of architecture.md section 5.1, the `UIUpdateLink` frame loop, the presented handler for the handoff, signposts, and an offscreen render for tests.
8. Snapshot tests: a zigzag stroke (acceptance 7), strokes at the origin and at (1,000,000, 1,000,000) (acceptance 3), and the white center (acceptance 6).
9. Unit tests for the allocator, the arena, and the draw list. Performance tests for the content pass with 20,000 and 200,000 strokes.

### 2.4 CanvasFeature (Tier C)

1. `CanvasViewController` and `CanvasView`: the Metal view with one `PKCanvasView` on top (architecture.md section 4.1).
2. The live `PKCanvasView`: `.pencilOnly`, the light interface style, `UIColor.white`, and the tool width from the camera zoom.
3. `PencilKitStrokeConverter`: read the control points, apply `stroke.transform` and the camera, take the width from fact 2, and split at the point limit.
4. The handoff: add the stroke to the renderer, and remove only that stroke from the `PKDrawing` after the presented handler runs.
5. `CameraController`: one-finger pan with deceleration, two-finger pinch about the finger midpoint, and the zoom clamp with a spring back.
6. `PalmGuard`: the three rules of architecture.md section 4.1. Finger gestures do nothing while the pencil draws (D-36).
7. Tests: the converter, the camera controller, and the palm guard. A handoff test compares the PencilKit image with the Metal image at zoom 0.25, 1, and 8 (acceptance 4). A test compares `StrokeCurve` with `PKStrokePath.interpolatedLocation(at:)` (acceptance 9).

### 2.5 App and tooling

1. `PointerApp` composes the canvas screen. M2 has no storage, so the canvas is empty at each launch, and the device ID is new at each launch.
2. Add the `Geometry`, `Model`, and `Rendering` packages to the Xcode project for the composition.
3. Add test targets to the packages, and add the new folders to the context map of `AGENTS.md`.
4. Update architecture.md sections 4.2, 4.3, 5.2, and 5.3 with the facts of section 1 and the chosen values.

## 3. What needs a real iPad

These criteria need a device and a person. The code and the tests for them are in place, but this work did not run them:

| Acceptance | What to do on the device |
|---|---|
| 1 | Film the screen at 240 fps or more and measure the latency (research.md section 3.4). |
| 2, 10 | Record 10 seconds of pan and zoom with 20,000 and 200,000 strokes in the Animation Hitches template. The app has a debug launch argument that fills the canvas. |
| 4, 5 | Draw at zoom 0.25, 1, and 8 and compare the live stroke with the finished stroke. The simulator tests cover programmatic strokes only. |
| 8 | Rest a palm on the screen while you write. Tune the palm radius and the 150 ms delay. |
| 9 | Run the `StrokeCurve` test on the device. It also runs in the simulator. |

The `Spikes/` folder was deleted after the device tests passed, as its README said. Commit `92b5e5d` still holds it.

## 4. Status on 2026-10-17

All tasks of section 2 are in the code, and `make check` passes. The simulator tests give these results:

| Acceptance | Result in the simulator |
|---|---|
| 3 | Strokes at (1,000,000, 1,000,000) and at the origin give the same pixels at zoom 0.25, 1, and 8. |
| 4 | Metal image against PencilKit image of the same stroke: no pixel differs by more than 17 of 255, and the total ink differs by at most 1.3 %. |
| 6 | The center of a stroke is 255 in each channel in both images. |
| 7 | The zigzag snapshot matches its reference image. |
| 9 | `StrokeCurve` matches `PKStrokePath.interpolatedLocation(at:)` to within 0.01 points at 16 values per segment. |

Test 4 uses programmatic strokes with the point size `width / 2 + 2`. A live stroke can have other point sizes. The converter reads the real sizes, so the handoff still matches, but the pen width on the screen can differ from 2 canvas points (D-37). The device test of acceptance 4 and 5 shows this.

On 2026-10-17 the CanvasFeature tests also passed on an iPad Pro 11-inch (M4), with 24 of 24 tests, including acceptance 9 and the handoff images of acceptance 4. Swift package tests cannot run on a device without a host app. Thus the test target `PointerDeviceTests` in `Pointer.xcodeproj` compiles the files of `Packages/CanvasFeature/Tests/CanvasFeatureTests`, with the app as its host. To run it, use this command with the device ID from `xcrun devicectl list devices`:

```
xcodebuild test -project Pointer.xcodeproj -scheme PointerApp -destination 'id=DEVICE_ID' -allowProvisioningUpdates
```

The coverage of `TEST-02` is not measured yet. To fill the canvas for acceptance 2 and 10, launch the app with `-fillStrokes 20000` or `-fillStrokes 200000 -fillPoints 30`.

### 4.1 Fixes from the device test of 2026-10-17

- The app froze when the pencil came near the screen. The hover preview of PencilKit causes a UI update on each display frame, and `UIUpdateLink` also called the frame action on these updates. Each call drew a Metal frame, and the two renderers waited for drawables. `InkView` now draws only when a frame has work (architecture.md 5.1).
- A glide after a pan did not stop when a finger touched. A finger that touches down now stops the glide, as in `UIScrollView`.
- During a glide, `waitUntilScheduled` blocked the main thread, and touches arrived late. The layer now uses `presentsWithTransaction = false` (architecture.md 5.1).
- At the stroke limit, a new pencil stroke stopped the app at a precondition. The canvas now refuses the stroke and removes it from the live drawing.
- The palm guard could stay in the pencil state if UIKit did not report the end of a pencil touch. The observer now ends open pencil touches in `reset()`.

After these fixes, on 2026-10-17, the product owner drew on the iPad Pro 11-inch (M4) with 20,000 strokes on the canvas. The strokes stayed after pencil lift, and pan and zoom worked, also when a finger stopped a glide.

### 4.2 Frame rate of pan and zoom

On the device, pan and zoom with 20,000 strokes ran at a steady 60 Hz with zero hitches, while the Settings app ran at 120 Hz. The ink pass took 5.7 ms of GPU time per frame (median). With two drawables, this work does not fit into one 120 Hz frame. The product owner accepted 60 Hz for now (D-39). A budget of 80,000 instances was tried and rejected.

The launch argument `-instanceBudget N` sets the build budget for tests on a device.

### 4.3 Device results of 2026-10-17

The tests ran on an iPad Pro 11-inch (M4) in the Release configuration.

| Acceptance | Result |
|---|---|
| 1 | The product owner filmed at 240 fps: the ink reaches the pencil tip after about 6 video frames, so about 25 ms. FEEL-01 sets 20 ms as the limit and 13 ms as the goal. The live stroke is drawn by PencilKit alone, so this is the latency of PencilKit in Pointer. The product owner accepted this value (D-40). |
| 2 | 20,000 strokes: zero hitches in 30 seconds of pan and zoom, at about 60 Hz (D-39). |
| 4, 5 | The product owner saw no change of the stroke at the handoff. |
| 8 | The product owner confirmed that a resting palm does not pan or zoom the canvas. |
| 9 | The device test passed (section 4). |
| 10 | 200,000 strokes of 30 points: zero hitches in 25 seconds of pan and zoom, at 57 to 60 Hz (D-39). |

The traces also show many short waits of the main thread during pan and zoom, from 33 ms up to 300 ms ("potential hangs" in Instruments). They cause no hitches, but they can delay touches. The cause is not known yet.

### 4.4 Coverage and performance baselines

Line coverage on 2026-10-17 (TEST-02): Geometry 90.9 %, Model 93.6 %, Rendering 78.9 %. InkEngine and Persistence have no code yet.

The performance tests ran on the iPad Pro 11-inch (M4) in the Release configuration, through the test target `PointerDeviceTests`. Each run renders all strokes into an image at zoom 0.25, with the upload of the points. These values are the baselines of M2 (PERF-03). A later run that is more than 10 % slower fails the checklist.

| Test | Average |
|---|---|
| `testContentPassTwentyThousandStrokes`: 20,000 strokes of 300 points | 61 ms |
| `testContentPassTwoHundredThousandStrokes`: 200,000 strokes of 30 points | 58 ms |

`PointerDeviceTests` also compiles the files of `Packages/Rendering/Tests/RenderingTests`, except the snapshot tests, which read their reference images from the Mac.
