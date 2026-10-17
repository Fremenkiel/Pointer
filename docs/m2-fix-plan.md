# M2 fix plan: performance, memory, and allocations before M3

This document lists the work that fixes the findings of the M2 code review of 2026-10-17. Each task has a measured reason, a fix, and a number that the fix must reach. M3 starts after all tasks of phases 0 to 5 are done or rejected by the product owner. The acceptance criteria of M2 stay in [plan.md](plan.md).

## 1. How the numbers were measured

A temporary benchmark suite ran on the iPad Pro 11-inch (M4) in the Release configuration, through the `PointerDeviceTests` target, on 2026-10-17. The drawable is 2420 by 1668 pixels. The suite used the internal types of `Rendering` through `@testable import`. It counted heap allocations through `malloc_logger`, so the counts include the allocations of every thread of the process during the measured call.

The suite used three kinds of content:

1. Dense: 20,000 strokes of 300 control points each, on a smooth curve 24 canvas points long. The M2 performance tests use other content with the same grid, but their points are up to 10 times farther apart (D-45).
2. Handwriting: 200,000 strokes of 60 control points, about 2 canvas points apart. This is closer to real pencil input at 240 Hz.
3. A frame loop on the screen: a `CADisplayLink` at 120 Hz drives a pan or a zoom for 4 seconds after 1 second of warm-up.

The frame loop used `CADisplayLink`, not the `UIUpdateLink` of `InkView`. Phase 1 repeats the key measurement with `UIUpdateLink` in the app.

The suite is not in the repository, because it does not meet the lint rules. Phase 0 turns the parts that the later phases need into permanent performance tests (PERF-03).

## 2. What the measurements showed

| Finding of the review | Measured result | Verdict |
|---|---|---|
| Pan runs at 60 Hz because of the continuous rebuild | Two drawables give exactly 60 Hz even at 0.34 ms of GPU time per frame. Three drawables give 120 Hz with zero late frames, also with the continuous rebuild. | The cause is the drawable count, not the rebuild. |
| `nextDrawable()` blocks the main thread | With two drawables it blocks 16.3 ms in every frame. With three it blocks 5.7 to 7.9 ms in every frame. | Confirmed. This is the main-thread time of the renderer. |
| The committed layer rebuilds during every pan | 254 builds in 4 seconds of pan. A gated policy gives 17 builds, mean GPU time 0.65 ms instead of 5.5 ms, and zero frames with uncovered screen. | Confirmed. The cost is energy and heat, not frame rate. |
| Level of detail is too fine at low zoom | A minimum spacing of 1 pixel instead of 0.5 halves the instances and the GPU time of dense content. The largest pixel difference is 12 of 255. | Confirmed. |
| One long segment inflates a whole stroke | 31,968 instances instead of 2,028 for a 1,000-point stroke with one jump at zoom 8. | Confirmed. |
| The point arena wastes bytes | The 192 MB buffer holds 45.8 MB of positions for dense content (24 %). The footprint grows 332 to 384 MB while the arena fills. | Confirmed. |
| Arena growth stalls the main thread | The four growth steps take 0.8, 1.7, 3.3, and 7.4 ms. | Confirmed, but it does not explain the 33 to 300 ms waits. |
| Eviction is O(n log n) per miss | 4.2 ms for one call. 8.1 ms per 2,000 strokes at the 90th percentile. | Confirmed. |
| The CPU holds strokes three times | 200,000 handwriting strokes use 226 MB in strokes and points, 72 MB in the content dictionary, and 77 MB in the renderer store. | Confirmed. |
| Load path allocates and walks points twice | 20,000 dense strokes: `Stroke.init` 9.5 ms with 20,000 allocations. A loop without the temporary array takes 3.5 ms. `StrokeStore.add` takes 14.8 ms with 44,481 allocations. | Confirmed, but small. |
| One render pass per handed-off stroke | 8 strokes in 8 passes: 0.34 to 0.48 ms. In 1 pass: 0.06 ms. | Confirmed, but small. |
| Load and store of the 2x texture is expensive | An empty load and store pass costs 0.05 to 0.06 ms at 1x, 1.5x, and 2x. | Rejected. Only the memory differs: 30.8 MB for the pair at 2x, 17.3 MB at 1.5x. |
| The vertex shader repeats its work and uses `constant` | The binary search, the `device` address space, an owner index, and `float2` points all give 4.1 ms. A compute pre-pass is 0.3 to 0.5 ms slower, except at zoom 8. | Rejected. Do not change the shader structure. |
| The sub-pixel composite blurs the ink | A 0.5-pixel offset widens the edge from 4 to 6 partial pixels. The center stays at 255. | Confirmed, but small. |
| The frame path allocates | The renderer makes 73 allocations per frame. A bare Metal command buffer with one pass makes 33 to 36. | Confirmed. About half of them are inside Metal. |
| The 200,000-stroke performance test | Its test data has 25,600 unique stroke IDs, not 200,000. The store drops the duplicates. | New finding. The M2 baseline of 58 ms is not valid. |

The 33 to 300 ms main-thread waits of [m2-plan.md](m2-plan.md) section 4.3 did not show in the benchmarks. One zoom frame took 22 to 25 ms on the main thread in the build step, in both policies. Phase 0 adds the signposts that find the cause.

### 2.1 Cause of the main-thread waits

On 2026-10-17, Instruments recorded 25 seconds of pan and zoom with 20,000 strokes on the iPad Pro 11-inch (M4), with the signposts of phase 0. The recording showed 215 "Potential Interaction Delay" intervals on the main thread, from 33.1 ms to 300.4 ms, with a median of 33.3 ms.

Each wait is a run of frames without an idle gap in the run loop. 196 of the 215 waits hold exactly two frames, and the longest wait holds 18 frames. In each frame, `nextDrawable()` blocks for about 15 to 16 ms, because the layer has two drawables (D-41). Over all waits, `nextDrawable()` takes 37.4 ms of the 40.3 ms of frame time in a mean wait. In the 300.4 ms wait, it takes 271.0 ms.

One wait at 4.05 s, during the load, has two other causes. An arena growth took 29.1 ms, and the builds took 40.3 ms. The benchmark measured at most 7.4 ms for one growth step.

Thus the cause of the waits is the block in `nextDrawable()`. Phase 1 removes it from the main thread (D-42).

## 3. Decisions for the product owner

These proposals change a decided item or a document rule. The product owner accepted all three on 2026-10-17. [decisions.md](decisions.md) records them as D-41, D-42, and D-43.

1. D-41: replace D-39 and use three drawables. With two drawables, `CAMetalLayer` gives a drawable only every second refresh, so pan and zoom can never reach 120 Hz (CAN-05). The live pen stroke does not use this layer (D-02), so the extra frame of latency touches only the handoff and the camera.
2. D-42: move the frame encoding off the main actor. architecture.md section 11 puts the renderer on the main actor. The main thread then waits in `nextDrawable()` for 5.7 to 16.3 ms in every frame, and touches wait with it. When no drawable is free, `nextDrawable()` waits up to one second, as Apple documents. `CAMetalDisplayLink` can run on a run loop of a render thread and hand over the drawable without a block on the main thread.
3. D-43: change the scope of PERF-01 from "no allocation" to "no allocation in Pointer code". A bare Metal frame makes 33 to 36 allocations inside Metal, so the rule as written cannot pass. The test measures the count of a frame minus the count of a bare frame.

## 4. Tasks

### Phase 0: measurement base

Do this phase first. Each later phase reruns these tests and compares them with the baseline.

1. Fix `StrokeBuilder.stroke` in `Packages/Rendering/Tests/RenderingTests/StrokeBuilder.swift`. Make the ID from the full index, not from truncated bytes. Run the two content-pass tests on the device again and record the new baselines in [m2-plan.md](m2-plan.md) section 4.4.
2. Add the handwriting content (200,000 strokes of 60 points) to the performance tests. The dense content alone hides the costs of real input.
3. Add an on-screen frame-loop test to `PointerDeviceTests`. It pans and zooms for 4 seconds. It reports the frame rate, the late frames, and the main-thread time. It also reports the GPU time, the builds, the frames with uncovered screen, and the allocations per frame.
4. Add signpost intervals around `beginFrame`, `nextDrawable()`, `startBuildIfNeeded`, `continueBuild`, `PointArena.grow`, and `evictAndAllocate` (PERF-03).
5. Record the app with Instruments while you pan and zoom with 20,000 strokes. Find the interval that matches each wait of 33 ms or more. Write the cause into section 2 of this document.
6. Add a GPU-time test of a full content pass for each level-of-detail value, with an image comparison against the current output. The largest pixel difference must stay at or below 17 of 255, the limit of M2 acceptance 4.

### Phase 1: frame pacing (D-41, D-42)

1. Set `maximumDrawableCount = 3` in `CanvasRenderer.configure` and in architecture.md section 5.1.
2. Run the frame-loop test with `UIUpdateLink`.
   - Done when: pan and zoom with 20,000 dense strokes and with 200,000 handwriting strokes run at 120 Hz with zero intervals over 12.5 ms.
3. Move the encoding to a render thread with `CAMetalDisplayLink`.
   - The main actor sends the camera and the new strokes as values.
   - The render thread owns `CommittedLayer`, `InkEncoder`, `StrokeStore`, and `DrawListRing`.
   - The handoff callback returns to the main actor as it does now.
   - Done when: the main-thread time of the renderer is under 1 ms per frame at the 99th percentile, and the handoff test of acceptance 4 still passes.
4. Film the handoff at 240 fps as in M2 acceptance 1. The stroke must not flicker or jump at the handoff with three drawables (FEEL-03).

### Phase 2: rebuild policy

1. In `CommittedLayer`, start a build only in one of these cases:
   - No front texture exists.
   - The zoom ratio of the front texture leaves the band 0.8 to 1.25.
   - The visible rectangle leaves the front texture minus a quarter of the margin.
   - The camera stays still for 6 frames and differs from the front camera.
   - A load invalidated the texture.
2. Keep the stale front texture on the screen during a build, as now.
   - Done when: a pan of 4 seconds with 20,000 dense strokes has at most 20 builds. The mean GPU time per frame is under 1 ms, and no frame shows uncovered screen. The benchmark gave 17 builds, 0.65 ms, and 0 frames.
3. Run the zoom loop.
   - Done when: there are at most 10 builds in 4 seconds of zoom between 0.25 and 0.49.
4. Measure the frames with uncovered screen at a margin of 1.5x instead of 2x. Pan at speeds up to 2,000 view points per second. If the count stays at zero, use 1.5x. This saves 13.5 MB on the 11-inch iPad and about 20 MB on the 13-inch iPad. If the count is not zero, keep 2x.

### Phase 3: level of detail

1. Set `LevelOfDetail.minimumPixelSpacing` to 1.0.
   - Done when: the dense content at zoom 0.25 has at most 300,000 instances, and its GPU time is at most 0.58 times the GPU time at 0.5 pixels (D-46). The largest pixel difference is at or under 17. The benchmark gave 300,000 instances, 2.62 ms against 4.68 ms (0.56), and 12 of 255. `LevelOfDetailPerformanceTests` gave 1.81 ms against 3.10 ms (0.58) on 2026-10-17.
   - Do not use 2.0. It gave a pixel difference of 58.
2. Fix the inflation by one long segment. Split each stroke into level-of-detail runs of 64 segments. Each run gets its own stride and pieces from its own spacing.
   - Store the runs as draw entries with a `firstSegment` field. At a run boundary, the shader then uses the real neighbor points, not the phantom points.
   - Pack `stride` and `pieces` into one `UInt32`, so the entry stays at 32 bytes.
   - Done when: the 1,000-point stroke with one 100-point jump at zoom 8 gets at most 2,100 instances instead of 31,968.
3. Measure the pieces per segment from the curvature, not only from the length. A piece length of 12 pixels halved the instances of handwriting at zoom 8 (1.17 ms to 0.77 ms, difference 18 of 255). It gave a difference of 40 at zoom 1. Use 12 pixels only where the turn of the segment is small.
   - Done when: handwriting at zoom 1 and 8 has at least 30 % fewer instances, and the largest pixel difference is at or under 17.
4. Keep the shader structure. Do not add a compute pre-pass or mesh shaders. The benchmark showed no gain.

### Phase 4: memory

1. Store only `x` and `y` in the arena, 8 bytes per point. The shader reads only `.xy`. The `float2` variant ran at the same speed (4.10 ms against 4.12 ms). This halves the arena for the same strokes.
2. Use size classes in steps of 1.25 instead of powers of two. A 300-point stroke then takes a 304-point block instead of a 512-point block. `SlabAllocator` keeps one size class per slab, with 32 classes instead of 11.
3. Replace the growing buffer with a list of fixed buffers of 16 MB each.
   - A block never crosses a buffer.
   - The draw list groups the entries by buffer, with one draw per buffer.
   - A new buffer needs no copy of the old points.
   - Done when: no frame of the load spends more than 1 ms in the arena. The footprint of the arena never exceeds its budget plus 16 MB. The benchmark gave 7.4 ms and +332 MB.
4. Replace the sort in `evictAndAllocate` with a clock sweep (a pointer that walks the slots and gives each recently drawn stroke a second chance).
   - Done when: the worst single call is under 0.5 ms with 200,000 strokes and a 16 MB arena. The benchmark gave 4.2 ms.
5. Shrink `StrokeStore`.
   - Keep an array of `InkPoints` references (8 bytes each) instead of the `Stroke` copies (128 bytes each).
   - Shrink `DrawInfo` from 80 bytes to at most 48 bytes: `Float` spacings, an `Int32` point count, and the block as two `Int32` values.
   - Reserve capacity by growth, not 200,000 entries at the start.
   - Done when: the renderer store of 200,000 handwriting strokes uses at most 30 MB of heap. The benchmark gave 77 MB.
6. Give `InkPoints` tail-allocated storage with `ManagedBuffer`, so one stroke is one heap block, not two.
   - Done when: 200,000 strokes make at most 200,100 heap blocks. The benchmark gave 400,193.
   - The public API of `InkPoints` stays. data-model.md section 7.4 needs a one-line update.

### Phase 5: small fixes

1. Draw all handed-off strokes of a frame in one pass in `CommittedLayer.addStroke`. Pass the pending slots as one array that the renderer keeps. Do not make a new array per stroke.
2. If the zoom ratio is 1, snap the composite offset to whole pixels.
3. Stop setting the PencilKit tool at each zoom step in `CanvasViewController.applyCamera`. Set it at two events only: the camera comes to rest, or a pencil touch stops an animation. First measure the cost of the current setter with a signpost. No Apple document gives it.
4. Compute the stroke bounds in one loop over the points in `Stroke.init`, without the temporary `[Point]` array.
5. Make `UUIDVersion7.make` fill a tuple, not an array. The benchmark counted one allocation per ID.
6. Keep the old front texture on the screen after `setViewport`, scaled, until the new texture is complete. A rotation or a Stage Manager resize then shows no black screen.
7. Remove the per-frame allocations of Pointer code:
   - Reuse two `MTLRenderPassDescriptor` objects.
   - Store the completed handlers once as properties instead of new closures in each frame.
   - Done when: the allocations per frame minus the bare-frame count are 0 (D-43).

### Phase 6: structure for M4

1. Rename `StrokeStore.residentInfo(of:frame:)` to a name that says that it uploads, evicts, and marks the stroke as drawn, for example `makeResident(_:frame:)`.
2. Add a free list of slots, so that M4 can remove a stroke. The removal frees the arena block after three frames and removes the slot from the grid.
3. Pass a per-frame context value (command buffer and frame number) to `CommittedLayer` and `InkEncoder` instead of separate arguments. Do not reach through `encoder.ring` from `CanvasRenderer`.

## 5. Order and checks

1. Phase 0 comes first, because each later phase compares against its baselines.
2. Phases 1 to 6 can run in any order after phase 0. Phase 1 gives the largest gain, so do it next.
3. After each phase, run `make check` and the device tests, and update the baselines of [m2-plan.md](m2-plan.md) section 4.4.
4. After phase 1 or phase 2, also rerun the 10-second Instruments recordings of M2 acceptance 2 and 10.
5. Update architecture.md sections 5.1, 5.2, and 5.3 with the new values in the same pull request as the code (AGENT-05).

## 6. Rejected changes

These review findings were measured and rejected. Do not do them without new numbers.

1. Restructure the vertex shader, use the `device` address space for the draw list, or add a compute pre-pass. All variants ran within 0.1 ms of each other, and the pre-pass was slower.
2. Reduce the texture margin for the load and store bandwidth. A load and store pass costs 0.06 ms at every size. The margin is a memory question only (phase 2, task 4).
