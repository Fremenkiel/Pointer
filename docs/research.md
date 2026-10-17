# Research results

This document records the research behind the design. Each section ends with the decision that follows from it. Statements marked [UNVERIFIED] did not have a primary source during the research (October 2026). Treat them as assumptions and test them.

## 1. Allume (formerly Muse)

Allume is the new name of Muse, the nested-board app from the Ink & Switch research lab. The rename came in a memo dated 2026-05-02. Version 4.0 shipped on 17 June 2026. Since 2023, one developer, Adam Wulf (Milestone Made, LLC), builds the app.

What the makers said in public about the technology (Metamuse podcast, episode 56, 2021 to 2023):

- The client is native Swift. It started on Core Data, then moved to a custom store on SQLite.
- Ink rendering uses OpenGL, and strokes are Bézier curves. It does not use PencilKit. [UNVERIFIED: a later move to Metal]
- The eraser and the selection cut Bézier curves. This code comes from Loose Leaf, an older open-source app by the same developer.
- Data is a growing set of edits ("atoms": entity, attribute, value, timestamp). Each attribute resolves by "last writer wins". Order comes from a hybrid logical clock (defined in [data-model.md](data-model.md)).
- The team splits data into three kinds: transactional data (cards, positions), blobs (images, PDFs), and temporary data (a stroke in progress).

Interaction ideas from the Muse research prototype that Pointer copies:

- Zoom is the navigation. A pinch responds at once and settles on a stable level.
- You can "peek" into a card with a pinch and roll back.
- Distant nested boards get a light haze.

What Allume does differently from the Pointer requirements:

- Allume boards have a size limit (a 2021 memo set 10 by 10 screens). The reasons were user orientation and 120 fps performance on large boards. Pointer has no size limit, so it must cull and cache from the start (see [architecture.md](architecture.md) section 5).
- Allume supports images, PDFs, video, links, and colors. Pointer supports none of these.

User complaints in App Store reviews: no infinite canvas, no way to scale content inside a board, awkward pencil writing in text boxes, and resizing by accident.

Sources: <https://allume.com/>, <https://allume.com/memos/2026-07-allume-v4/>, <https://allume.com/podcast/56-sync/>, <https://allume.com/memos/2021-03-flex-boards/>, <https://www.inkandswitch.com/muse/>.

Decision: Pointer uses its own ink engine and its own data format, like Allume. It copies the zoom-as-navigation model and the record-per-object data model.

## 2. Other implementations

| App | What we learned |
|---|---|
| GoodNotes | Custom ink engine in Swift with CRDT-based sync. The team names "above 60 fps for real-time ink" as a requirement. The engine also runs on the web through SwiftWasm. |
| tldraw | Every object is a record with an `id`, a `parentId`, and a fractional index `index` for order. Fractional indexes let you insert between two items without a renumber. |
| perfect-freehand | Builds a filled outline around the input points. Options: `thinning` (pressure effect), `streamline` (smoothing), taper at the ends. |
| Excalidraw | Each element has an integer `version`, a random `versionNonce`, and an `isDeleted` flag (a tombstone). This merges well without a full CRDT. |
| Obsidian | A vault is a plain folder. Every sync tool works with it. Most sync conflicts come from busy shared files. |
| Notability | A note is one zip of binary property lists. Sync conflicts cover the whole note. |
| Apple Freeform | Storage format is not documented. No user-visible file exists except PDF export. |

Sources: <https://swift.org/blog/bringing-goodnotes-to-web-with-swift/>, <https://tldraw.dev/sdk-features/shape-indexing>, <https://docs.excalidraw.com/docs/codebase/json-schema>, <https://obsidian.md/help/data-storage>, <https://jvns.ca/blog/2018/03/31/reverse-engineering-notability-format/>.

Decision: Pointer stores one small file per object. Each object has a stable ID, a parent ID, a fractional index, a clock, and a tombstone flag.

## 3. Latency and the feel of paper

### 3.1 Research papers

| Paper | Result |
|---|---|
| Ng et al., UIST 2012, "Designing for Low-Latency Direct-Touch Input" | The prototype had 1 ms latency. In a drag task, users did not feel latency below about 6 ms (range 2 to 11 ms). |
| Jota et al., CHI 2013, "How fast is fast enough?" | Drag performance gets worse as latency increases. The threshold for a tap was 64 ms. [UNVERIFIED: the 25 ms drag figure, secondary source only] |
| Ng et al., CHI 2014, "In the Blink of an Eye" | Stylus thresholds: drag a small box, median 2 ms. Drag a large box, median 6 ms. Scribble, median 40 ms (range 10 to 70). |
| Annett et al., GI 2014, (title: "How Low ... We Go?") | While people write or sketch, latency is harder to see (about 50 ms) than in other tasks (2 to 7 ms). The visible reference is the pen and the hand. |
| Deber et al., CHI 2015 | Smallest difference that users notice: about 11 ms for drag, about 69 ms for tap. |
| Cattan et al., ITS 2015, "Reducing Latency with a Continuous Prediction" | Linear prediction removes much of the cost of latency. Prediction that goes too far overshoots at corners and at the end of a stroke. |
| Casiez et al., CHI 2012, "1€ Filter" | A low-pass filter with a cutoff that rises with speed. At low pen speed it removes jitter. At high pen speed it adds little lag. |
| Annett et al., TOCHI 2014, and Schwarz et al., CHI 2014 | Stylus data improves palm rejection. On iPad, the system does most of this for Apple Pencil. |

Sources: <https://webdocs.cs.ualberta.ca/~wfb/publications/C-2014-SIGCHI-Latency.pdf>, <https://graphicsinterface.org/proceedings/gi2014/gi2014-22/>, <https://www.dgp.toronto.edu/?p=697>, <https://iihm.imag.fr/en/publication/CRP+15a/>, <https://cristal.univ-lille.fr/~casiez/1euro>.

### 3.2 Apple platform numbers

- In 2017, Apple stated 20 ms Pencil latency on the first ProMotion iPad Pro.
- In 2019 (iPadOS 13), Apple stated 9 ms. Press reports said that third-party apps reach about 13 ms, because part of the gain (mid-frame event processing) was internal to Apple. [UNVERIFIED: whether this is still true]
- iOS 18 added `UIUpdateLink` with `wantsLowLatencyEventDispatch` and `wantsImmediatePresentation`. Apple documents it as the path for "a custom low-latency drawing implementation for a pencil-drawing app" (WWDC24 session 10118). One forum report (thread 797083) says that immediate presentation never turned on in a test. [UNVERIFIED: real gain on a device]
- Apple Pencil reports samples at 240 Hz. You get all of them through `UIEvent.coalescedTouches(for:)`.

### 3.3 What matters most for the feel

In order of effect:

1. The gap between the pencil tip and the end of the ink. This is the main signal. Draw the predicted touches as a temporary tail and replace the tail on each frame. Limit the prediction to about one frame (8 ms) to prevent overshoot.
2. The delay at the start of a stroke. Draw ink on the first sample. Pencil touches go to the canvas directly, never through a gesture recognizer that waits.
3. Jitter at the tip. Use a 1€ filter on the live tip. Limit the lag of the filter to about one frame.
4. A stroke that changes after the pencil lifts. Users notice it. The stored stroke must be the stroke that the user saw.
5. Dropped frames. One dropped frame at 120 Hz adds 8.3 ms. Users notice latency that changes more than latency that stays constant.

Friction (the physical feel of paper) depends on the screen protector of the user. Software cannot change it. Apple Pencil Pro has haptics (`UICanvasFeedbackGenerator`), but only for alignment and path events, not for texture.

### 3.4 How to measure latency

1. Film the pencil tip and the ink with a high-speed camera (240 fps or more) while you draw straight lines at a constant speed. Latency is the distance from tip to ink divided by the pencil speed.
2. Use the Instruments "Animation Hitches" template and Metal System Trace to find dropped frames.
3. In the app, log `UITouch.timestamp` against the presented time of the drawable (`MTLDrawable.addPresentedHandler`, `presentedTime`). This gives software latency for each frame and can run in automated tests on a device.

Decision: The targets are 13 ms (goal) and 20 ms (limit). The first milestone is a latency test that compares PencilKit with the custom engine (see [plan.md](plan.md), M1).

## 4. Apple APIs

### 4.1 PencilKit

Advantages:

- Apple tunes its latency.
- A white monoline pen without the tool picker takes about 20 lines of code.
- iPadOS 27 adds stable stroke IDs and Bézier conversion in both directions (`PKStrokePathReference.bezierRepresentation`). It also adds erasing in code (`PKDrawing.erasePath`) and handwriting recognition (`PKStrokeRecognizer`).

Problems for Pointer:

- `PKCanvasView` is a `UIScrollView`. In March 2026, an Apple engineer confirmed flicker in its internal tile rendering at zoom scales other than 1x. No workaround exists (feedback FB22063128, FB22297047, forum thread 818218).
- Nested cards need one `PKCanvasView` per visible card.
- The storage format (`PKDrawing.dataRepresentation()`) is not documented. An older iPadOS refuses data from a newer one.
- Before iPadOS 27, PencilKit exports bitmaps only. On iPadOS 27, it is not clear whether `bezierRepresentation` gives the center line or the outline. [UNVERIFIED]
- After a change of the interface style, PencilKit can show white ink as black. [UNVERIFIED]

Sources: <https://developer.apple.com/documentation/pencilkit/pkcanvasview>, <https://developer.apple.com/documentation/pencilkit/pkcontentversion>, <https://developer.apple.com/forums/thread/818218>, <https://developer.apple.com/documentation/updates/pencilkit>, WWDC19 session 221, WWDC24 session 10214, WWDC26 session 203.

### 4.2 Custom rendering

- Input: `coalescedTouches(for:)` for all samples, `predictedTouches(for:)` for the temporary tail, `estimatedPropertiesExpectingUpdates` and `touchesEstimatedPropertiesUpdated(_:)` for late force and roll values (WWDC15 session 233, WWDC16 session 220).
- Frame timing: `UIUpdateLink` (iOS 18) with low-latency event dispatch and immediate presentation. Fallback: `CAMetalDisplayLink` or `CADisplayLink`.
- Metal: `CAMetalLayer` with `maximumDrawableCount = 2` and `presentsWithTransaction = true`. Two drawables lower latency. If the GPU is late, a frame is dropped.
- Precision: Metal shaders use 32-bit floats. At 1,000,000 points from the origin, the step between two values is about 0.125 points. Store positions as `Double` and send positions relative to the camera to the GPU.

Source: <https://developer.apple.com/documentation/uikit/uiupdatelink>, <https://developer.apple.com/documentation/uikit/leveraging-touch-input-for-drawing-apps>.

### 4.3 UIPencilInteraction

- iOS 17.5 added `pencilInteraction(_:didReceiveTap:)` and `pencilInteraction(_:didReceiveSqueeze:)`. The squeeze has phases. Act on `.ended`.
- Both events carry a `hoverPose`, so the app can place a palette at the pencil tip.
- The user chooses the double-tap action and the squeeze action in Settings. Read `UIPencilInteraction.preferredTapAction` and `preferredSqueezeAction`. Values: `.ignore`, `.switchEraser`, `.switchPrevious`, `.showColorPalette`, `.showInkAttributes`, `.showContextualPalette`, `.runSystemShortcut`.
- If the setting is `.runSystemShortcut`, the app never receives the squeeze.
- If the app has no squeeze delegate, the system shows its own undo slider on squeeze.

| Pencil | Double tap | Squeeze | Pressure | Hover |
|---|---|---|---|---|
| Apple Pencil Pro | Yes | Yes | Yes | Yes |
| Apple Pencil (2nd generation) | Yes | No | Yes | M2 iPad Pro only |
| Apple Pencil (USB-C) | No | No | No | Yes |
| Apple Pencil (1st generation) | No | No | Yes | No |

Sources: <https://developer.apple.com/documentation/uikit/uipencilinteraction>, <https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil>, <https://support.apple.com/en-us/108937>.

### 4.4 Vector PDF

- Use `UIGraphicsPDFRenderer`, or `CGContext(consumer:mediaBox:)` for pages of a custom size.
- Draw ink as `CGPath` objects. A monoline stroke is a center line with round caps and round joins.
- Draw text with Core Text (`CTFramesetter`, `CTFrameDraw`). The result is real glyphs.
- Never use `CALayer.render(in:)` or a view snapshot. A TextKit 2 text view becomes a bitmap that way (forum thread 745459).

Decision: Pointer uses a custom Metal renderer for display and Core Graphics for PDF export. Both use the same stroke geometry. If the custom engine fails the latency test in M1, PencilKit is the fallback.

## 5. Storage

| Option | Result for Pointer |
|---|---|
| SwiftData or Core Data | Rejected. A live SQLite store (with its `-wal` and `-shm` files) is not safe to copy as a folder. It does not diff. |
| SQLite only | Rejected as the source of truth. One edit changes the one big file, so a file-based backup uploads all of it. |
| Plain files per object | Selected. Each write is atomic. A small edit changes a small file. Any backup tool works. |

Facts that the design uses:

- `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)` gives a zip of a folder without third-party code. The system deletes the zip at the end of the block. Move the zip to a different location inside the block.
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` show the `Documents` folder in the Files app.
- Device backups (iCloud or Finder) include `Documents` and `Library`, but not `Library/Caches`.
- Background tasks (`BGProcessingTask`) cannot run on a fixed schedule. A Shortcuts automation can call an App Intent at a fixed time. [UNVERIFIED: whether the intent runs while the iPad is locked]

Sources: <https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/foruploading>, <https://developer.apple.com/forums/thread/681770>, <https://www.sqlite.org/fasterthanfs.html>.

## 6. Coding standards

The research for the coding standard is in [code-of-code.md](code-of-code.md), section 1.
