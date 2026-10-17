# Research results

This document records the research behind the design. Each section ends with the decision that follows from it. Statements marked [UNVERIFIED] did not have a primary source during the research (October 2026). Treat them as assumptions and test them.

## 1. Allume (formerly Muse)

Allume is the new name of Muse, the nested-board app from the Ink & Switch research lab. The rename came in a memo dated 2026-05-02, after the sale of the Muse name and trademarks. Version 4.0 shipped on 2026-06-11. Since 2023, one developer, Adam Wulf, builds the app. Milestone Made is the company of Adam Wulf for Loose Leaf. (Source review 2026-10-17, see [review-2026-10-17.md](review-2026-10-17.md) B-1.)

What the makers said in public about the technology (Metamuse podcast, episode 56, 2021 to 2023):

- The client is native Swift. It started on Core Data, then moved to a store on SQL.
- No public source states the rendering technology of Muse or Allume. Loose Leaf, an older open-source app by the same developer, draws with JotUI, an OpenGL view, and cuts Bézier curves with ClippingBezier. No source links that code to Muse. (Source review 2026-10-17.)
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
| GoodNotes | Custom ink engine in Swift on Metal (iOS) and WebGL (web), with CRDTs for conflict resolution. The team names "more than 60 fps for real-time ink" as a requirement. The engine also runs on the web through SwiftWasm. |
| tldraw | Every shape is a record with an `id`, a `parentId`, and a fractional index `index` for order. Fractional indexes let you insert between two items without a renumber. |
| perfect-freehand | Builds a filled outline around the input points. Options: `thinning` (pressure effect), `streamline` (smoothing), taper at the ends. |
| Excalidraw | Each element has an integer `version`, a random `versionNonce`, and an `isDeleted` flag (a tombstone). This merges well without a full CRDT. Source: `packages/element/src/types.ts` in the Excalidraw repository. |
| Obsidian | A vault is a plain folder. Every sync tool works with it. Most sync conflicts come from busy shared files. |
| Notability | A note is one zip of binary property lists. Sync conflicts cover the whole note. |
| Apple Freeform | Storage format is not documented. No user-visible file exists except PDF export. |

Sources: <https://swift.org/blog/bringing-goodnotes-to-web-with-swift/>, <https://tldraw.dev/sdk-features/shape-indexing>, <https://docs.excalidraw.com/docs/codebase/json-schema>, <https://obsidian.md/help/data-storage>, <https://jvns.ca/blog/2018/03/31/reverse-engineering-notability-format/>.

Decision: Pointer stores one database row per object. Each object has a stable ID, a parent ID, a fractional index, a clock, and a tombstone flag.

## 3. Latency and the feel of paper

### 3.1 Research papers

| Paper | Result |
|---|---|
| Ng et al., UIST 2012, "Designing for Low-Latency Direct-Touch Input" | The prototype had 1 ms latency. Users preferred lower latency, and the gain continued well below 10 ms. The figure "6 ms (range 2 to 11 ms)" comes from the CHI 2014 paper of the same authors, not from this paper. |
| Jota et al., CHI 2013, "How fast is fast enough?" | Drag performance gets worse as latency increases. The 64 ms tap threshold is quoted by Ng et al. 2014 and Annett et al. 2014. The 25 ms drag figure appears in secondary sources only (arXiv 2408.02525). The paper itself was not accessible. |
| Ng et al., CHI 2014, "In the Blink of an Eye" | Stylus thresholds: drag a small box, median 2 ms. Drag a large box, median 6 ms. Scribble, median 40 ms (range 10 to 70). Baselines: 1 ms for drag, 7 ms for inking. Taken from the paper PDF. |
| Annett et al., GI 2014, (title: "How Low ... We Go? Understanding the Perception of Latency While Inking") | While people write or sketch, latency is harder to see (about 50 ms) than in other tasks (2 to 7 ms). The visible reference is the pen and the hand. Taken from the paper PDF. |
| Deber et al., CHI 2015, "How Much Faster is Fast Enough?" | Smallest difference that users notice: about 11 ms for drag, about 69 ms for tap. An improvement of 8.3 ms is noticeable. These numbers come from a secondary source (arXiv 2408.02525). The abstract has no numbers. |
| Cattan et al., ITS 2015, "Reducing Latency with a Continuous Prediction" | Linear prediction at constant speed offsets much of the cost of latency. The useful prediction length depends on the task. The overshoot statement was not found in the abstract. |
| Casiez et al., CHI 2012, "1€ Filter" | A low-pass filter with a cutoff that rises with speed. At low pen speed it removes jitter. At high pen speed it adds little lag. Author defaults: `mincutoff` 1 Hz, `beta` 0, `dcutoff` 1 Hz. The author says to tune `beta` with values like 0.001 or 0.0001. |
| Annett et al., TOCHI 2014, "Exploring and Understanding Unintended Touch during Direct Pen Interaction", and Schwarz et al., CHI 2014, "Probabilistic Palm Rejection" | Stylus data improves palm rejection. On iPad, the system does most of this for Apple Pencil. |

Sources: <https://webdocs.cs.ualberta.ca/~wfb/publications/C-2014-SIGCHI-Latency.pdf>, <https://graphicsinterface.org/proceedings/gi2014/gi2014-22/>, <https://www.dgp.toronto.edu/?p=697>, <https://iihm.imag.fr/en/publication/CRP+15a/>, <https://cristal.univ-lille.fr/~casiez/1euro>.

### 3.2 Apple platform numbers

- In 2017, Apple stated 20 ms Pencil latency on the first ProMotion iPad Pro. Source: the Apple newsroom post of June 2017.
- In 2019 (iPadOS 13), Apple stated 9 ms in its marketing. WWDC19 session 221 gives no number. The 13 ms figure for third-party apps is not an Apple statement. It comes from a 2019 email from Craig Federighi to a developer: "4 ms of our improvement comes from a technique called mid-frame event processing". The email added that Apple wanted to expose that technique later. `UIUpdateLink.wantsLowLatencyEventDispatch` (iOS 18) appears to be that exposure. Whether a gap remains is open. M1 measures it.
- iOS 18 added `UIUpdateLink` with `wantsLowLatencyEventDispatch` and `wantsImmediatePresentation`. The documentation page names "a custom low-latency drawing implementation for a pencil-drawing app" as a use case. WWDC24 session 10118 ("What's new in UIKit") introduced the class. Apple documents that low-latency events "dispatch in the middle of a UI update". Apple adds that this "gives an app half the amount of time to handle them as standard events". Forum thread 797083 reports that immediate presentation never turned on, but that test used a plain `UIView` without Metal and has no replies. The real gain on a device is still open. M1 measures it.
- Apple Pencil reports samples at 240 Hz. You get all of them through `UIEvent.coalescedTouches(for:)`. Apple says to read them at once inside the event handler.

### 3.3 What matters most for the feel

In order of effect:

1. The gap between the pencil tip and the end of the ink. This is the main signal. Draw the predicted touches as a temporary tail and replace the tail on each frame. Limit the prediction to about one frame (8 ms) to prevent overshoot.
2. The delay at the start of a stroke. Draw ink on the first sample. Pencil touches go to the canvas directly, never through a gesture recognizer that waits.
3. Jitter at the tip. Use a 1€ filter on the live tip. Limit the lag of the filter to about one frame.
4. A stroke that changes after the pencil lifts. Users notice it. The stored stroke must be the stroke that the user saw.
5. Dropped frames. One dropped frame at 120 Hz adds 8.3 ms. Users notice latency that changes more than latency that stays constant.

Friction (the physical feel of paper) depends on the screen protector of the user. Software cannot change it. Apple Pencil Pro has haptics (`UICanvasFeedbackGenerator`), but only for alignment and path events, not for texture. Pointer plays no haptics and does not imitate paper (PEN-06). It accepts haptics that the system plays by itself (D-23). Only the latency findings apply.

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
- Before iPadOS 27, PencilKit exports bitmaps only. On iPadOS 27, `bezierRepresentation` gives the center line: Apple calls it "a Bézier path representation of the path's curve", the conversion round-trips the control points, and the path carries no width or force. (Source review 2026-10-17.)
- PencilKit adapts black and white ink to the interface style by design. Forum reports of wrong colors with an overridden style exist (threads 689847 and 701841). Apple answered none of them. Pointer draws white on black at all times, so the custom engine avoids this.

Sources: <https://developer.apple.com/documentation/pencilkit/pkcanvasview>, <https://developer.apple.com/documentation/pencilkit/pkcontentversion>, <https://developer.apple.com/forums/thread/818218>, <https://developer.apple.com/documentation/updates/pencilkit>, WWDC19 session 221, WWDC24 session 10214, WWDC26 session 203.

### 4.2 Custom rendering

- Input: `coalescedTouches(for:)` for all samples, `predictedTouches(for:)` for the temporary tail, `estimatedPropertiesExpectingUpdates` and `touchesEstimatedPropertiesUpdated(_:)` for late force and roll values (WWDC15 session 233, WWDC16 session 220).
- Frame timing: `UIUpdateLink` (iOS 18) with low-latency event dispatch and immediate presentation. Fallback: `CAMetalDisplayLink` or `CADisplayLink`.
- Metal: `CAMetalLayer` with `maximumDrawableCount = 2`. Apple allows 2 or 3 drawables and makes no latency statement about the value. The assumption that two drawables lower latency is a test variable for M1. `presentsWithTransaction = true` synchronizes Metal content with Core Animation and makes the main thread wait in `waitUntilScheduled()`. Apple states no requirement that immediate presentation needs it. It is also a test variable for M1.
- Precision: Metal shaders use 32-bit floats. At 1,000,000 points from the origin, the step between two values is 0.0625 points, and 0.125 from 1,048,576. Store positions as `Double` and send positions relative to the camera to the GPU.

Source: <https://developer.apple.com/documentation/uikit/uiupdatelink>, <https://developer.apple.com/documentation/uikit/leveraging-touch-input-for-drawing-apps>.

### 4.3 UIPencilInteraction

- iOS 17.5 added `pencilInteraction(_:didReceiveTap:)` and `pencilInteraction(_:didReceiveSqueeze:)`. The squeeze has phases. Act on `.ended`.
- Both events carry a `hoverPose`, so the app can place a palette at the pencil tip.
- The user chooses the double-tap action and the squeeze action in Settings. Read `UIPencilInteraction.preferredTapAction` and `preferredSqueezeAction`. Values: `.ignore`, `.switchEraser`, `.switchPrevious`, `.showColorPalette`, `.showInkAttributes`, `.showContextualPalette`, `.runSystemShortcut`.
- If the setting is `.runSystemShortcut`, the app never receives the squeeze.
- If the app has no squeeze delegate, the system shows its own undo slider on squeeze (WWDC24 session 10214).
- The system plays a haptic on squeeze and on double tap of Apple Pencil Pro. The user turns it off under Settings > Apple Pencil > Haptics. No public API turns it off. (Source review 2026-10-17. This resolves the doubt in D-23.)

| Pencil | Double tap | Squeeze | Pressure | Hover |
|---|---|---|---|---|
| Apple Pencil Pro | Yes | Yes | Yes | Yes |
| Apple Pencil (2nd generation) | Yes | No | Yes | M2 iPad Pro only |
| Apple Pencil (USB-C) | No | No | No | Yes |
| Apple Pencil (1st generation) | No | No | Yes | No |

Hover works on these iPads: iPad Pro M4 and M5, iPad Pro 11-inch (4th generation), iPad Pro 12.9-inch (6th generation), iPad Air M2 and M3, and iPad mini (A17 Pro). Apple Pencil (2nd generation) hovers on the two M2 iPad Pro models only. Source: the tech specs pages of each pencil (source review 2026-10-17).

Sources: <https://developer.apple.com/documentation/uikit/uipencilinteraction>, <https://developer.apple.com/documentation/applepencil/handling-squeezes-from-apple-pencil>, <https://support.apple.com/en-us/108937>.

### 4.4 Vector PDF

- Use `UIGraphicsPDFRenderer`, or `CGContext(consumer:mediaBox:)` for pages of a custom size.
- Draw ink as `CGPath` objects. A monoline stroke is a center line with round caps and round joins.
- Draw text with Core Text (`CTFramesetter`, `CTFrameDraw`). The result is real glyphs.
- Never use `CALayer.render(in:)` or a view snapshot. A TextKit 2 text view becomes a bitmap that way (forum thread 745459).

Decision: Pointer uses a custom Metal renderer for display and Core Graphics for PDF export. Both use the same stroke geometry. If the custom engine fails the latency test in M1, the fallback is PencilKit for input capture only, with the custom renderer (D-33).

## 5. Storage

| Option | Result for Pointer |
|---|---|
| SwiftData or Core Data | Rejected. They add a framework layer over SQLite with less control over the schema, the transactions, and the snapshots. |
| SQLite directly | Selected (2026-10-17, by the product owner). Fastest for small records. One transaction covers a whole command. Backup uses snapshots (`VACUUM INTO`), because a live database is not safe to copy. |
| Plain files per object | Rejected. Easy to back up and to diff, but about 250 times slower for small records (see the table below). |

Measured cost (2026-10-17, Mac with Apple silicon, APFS, Swift `-O`, best of 5 runs, warm cache). The records are 400 bytes, the size of one card or text box. SQLite ran in WAL mode with `synchronous=NORMAL`.

| Task | Files | SQLite |
|---|---|---|
| Write 1,000 records | 141 ms (one atomic file each) | 0.55 ms (one transaction), 8.4 ms (1,000 transactions) |
| Read 1,000 records | 10 ms | 0.04 ms |
| Save 5 changed records | 0.65 ms | 0.01 ms |
| Write one 1 MB ink chunk | 0.30 ms | 0.90 ms |
| Read one 1 MB ink chunk | 0.04 ms | 0.05 ms |

For many small records, SQLite is about 250 times faster. For large ink chunks, files are equal or faster. In normal use, the difference is below what a user can see: a save takes under 1 ms off the main actor, and ink is most of the data. The limit is the open of a canvas with many cards and text boxes. At 1,000 nodes the files cost about 10 ms. At the limit of 10,000 nodes, about 100 ms is the estimate, which is one third of the 300 ms budget. An iPad is slower than this Mac, and a cold cache is slower than a warm one. Repeat the test on the iPad in M3. After this measurement, the product owner chose SQLite.

Facts that the design uses:

- `NSFileCoordinator.coordinate(readingItemAt:options:.forUploading)` gives a zip of a folder without third-party code. The system deletes the zip at the end of the block. Move the zip to a different location inside the block.
- `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` show the `Documents` folder in the Files app.
- Device backups (iCloud or Finder) include `Documents` and `Library`, but not `Library/Caches`.
- Background tasks (`BGProcessingTask`) cannot run on a fixed schedule. A Shortcuts automation can call an App Intent at a fixed time. A Time of Day automation has a privacy switch for a locked device, and an App Intent with `IntentAuthenticationPolicy.alwaysAllowed` runs on a locked device. No Apple page states the full chain from the automation to the intent. Version 1 has no App Intent (D-14).
- `VACUUM INTO` facts from the SQLite manual: the copy is a consistent snapshot. An interrupted run leaves an incomplete and corrupt output file. The target file must not exist. If the source runs with `synchronous = NORMAL` or `FULL`, SQLite syncs the output file. The manual does not say that writers wait.
- If the destination uses WAL and the page sizes of the source and the destination differ, `sqlite3_backup_step` returns `SQLITE_READONLY`.
- iOS gives about 30 seconds of background time after `beginBackgroundTask` (Apple DTS, forum thread 85066). Apple changed that value before.
- Community data on the SQLite version per OS: iOS 18.0 ships 3.43.2, iOS 26.0 ships 3.51.0. `STRICT` tables need 3.37.0.

Sources: <https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions/foruploading>, <https://developer.apple.com/forums/thread/681770>, <https://www.sqlite.org/fasterthanfs.html>, <https://www.sqlite.org/lang_vacuum.html>, <https://www.sqlite.org/c3ref/backup_finish.html>, <https://developer.apple.com/forums/thread/85066>, <https://support.apple.com/guide/shortcuts/add-automations-apdfbdbd7123/ios>.

## 6. Coding standards

The research for the coding standard is in [code-of-code.md](code-of-code.md), section 1.
