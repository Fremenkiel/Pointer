# M8 work plan: PDF export

This document breaks milestone M8 of [plan.md](plan.md) into tasks. The acceptance criteria stay in [plan.md](plan.md). The tasks build on EXP-01 to EXP-04, D-13, D-15, D-26, D-84, and D-138 to D-145.

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

## 1. How to work

### 1.1 Device and build

1. Use only the iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator, and never make one (learned rule 1 of `AGENTS.md`).
2. Before each device run, run `xcrun devicectl device info lockState --device 00008132-000018993E8B801C`. If it prints `passcodeRequired: true`, stop and ask the product owner to unlock the iPad.
3. Run one device suite with this command. Replace `<Suite>` and `<Name>`.

```
xcodebuild test -project Pointer.xcodeproj -scheme PointerApp -configuration Release \
  -destination 'id=00008132-000018993E8B801C' -derivedDataPath .build/DeviceData \
  -allowProvisioningUpdates ENABLE_TESTABILITY=YES \
  -only-testing:PointerDeviceTests/<Suite> -resultBundlePath .build/Runs/<Name>.xcresult
```

4. Give each run that you compare a `-resultBundlePath` under `.build/Runs`. Xcode keeps only the 5 newest bundles in `.build/DeviceData/Logs/Test`, so an older run without its own path is lost.
5. Read the measures as in section 1.2 of [m6-fix-plan.md](m6-fix-plan.md). Compare two builds only with alternating runs (section 1.3 there).

### 1.2 What a test can and cannot do

1. Package tests cannot run on the iPad, so the tests of `Export` run in `PointerDeviceTests`, as the tests of `Rendering` do (D-77, D-140).
2. A test can read a PDF back with PDFKit: `PDFDocument(data:)`, `PDFPage.string`, `PDFDocument.findString(_:withOptions:)`, and the media box. Preview on the Mac uses the same text extraction for selection and search.
3. A test can render a PDF page into an image with `UIGraphicsImageRenderer` and `CGContext.drawPDFPage(_:)`, and compare it with a reference PNG (TEST-07).
4. A test cannot open the share sheet and pick a target. Keep the button handler thin. Test the code behind it: the empty check, the end of a text edit, and the item provider that the share sheet gets.
5. Only the product owner can open the PDF in Preview on a Mac and zoom to 6400 %.

## 2. Facts from the code at the start of M8

Read on 2026-10-23 on `main` at commit 55d43ea. Paths are under `Packages/` unless they start with `PointerApp/` or `Scripts/`.

### 2.1 The Export package

1. `Export/Sources/Export/Export.swift` holds only `public enum Export {}`. `Export/Package.swift` depends on `Geometry`, `InkEngine`, and `Model`, and has no test target.
2. `Pointer.xcodeproj` does not link `Export`, and no feature package depends on it. `PointerDeviceTests` has no synchronized group for Export tests.
3. `Scripts/coverage.swift` leaves out Export on purpose, and the `coverage` target of the `Makefile` reads only the framework of `Rendering`. TEST-02 asks for 70 % in Tier B.
4. `Scripts/assertion-density.swift` already covers Export ("Export: no functions").
5. The lint rule `arch_04_pdf` in `.swiftlint.yml` bans only `UIGraphicsPDFRenderer` outside `Packages/Export/` (D-139).

### 2.2 Strokes

1. `Stroke` has an `origin` in `Double` and points as `Float` offsets from it. `Stroke.canvasPoint(at:)` adds them in `Double`. `Stroke.curve` makes a `StrokeCurve` in canvas space (`Model/Sources/Model/Stroke.swift:92` and `:99`).
2. `StrokeCurve` (`Geometry/Sources/Geometry/StrokeCurve.swift`) is the uniform cubic B-spline of D-26. It has `segmentCount`, `extendedControlPoint(at:)` with the phantom points at -1 and `count`, and `point(at:)`. It has no Bézier conversion.
3. `Stroke.width` is a `Float` in canvas points. `Stroke.bounds` holds the control points plus half the width. The curve stays inside the convex hull of its control points.
4. The canvas has no coordinate limit. M2 acceptance 3 tests strokes at (1,000,000, 1,000,000).

### 2.3 Text

1. `TextLayout` (`Rendering/Sources/Rendering/TextLayout.swift`) breaks the lines with `CTTypesetterSuggestLineBreak` at `TextStyle.maxWidth` (640 points), with `TextLayout.baseFont` (SF Mono at 17 points from `UIFont.monospacedSystemFont`). It keeps glyph IDs, positions, and font indices, not the text or the lines.
2. The baseline of line `n` is at `n * TextLayout.lineHeight + TextLayout.ascent` from the top of the box (`TextLayout.Glyph.position`).
3. An empty text and a text that ends with a new line count one more, empty line.
4. The probe of D-140 showed that glyph IDs drawn into a PDF lose the text, and that `CTLineDraw` keeps it.

### 2.4 The canvas screen

1. `installHistoryButtons()` (`CanvasFeature/Sources/CanvasFeature/CanvasViewController+History.swift:254`) puts `HistoryButtons` into a `UIHostingController` in the top right corner. EXP-01 puts the export button next to undo and redo.
2. `DesignSystem.Icon` holds the SF Symbol names of the chrome, for example `undo` and `redo`. It has no export icon.
3. `CanvasDependencies.onMessage` shows a message. `CanvasStrings` reads the String Catalog of the canvas.
4. A text edit keeps its text in the edit view until it ends (D-87). `content` holds the text of the box before the edit.
5. `ParentLink.card` holds the card of a canvas inside a card, or `nil`. `Card.title` is optional. The screen does not know the title of its workspace (D-143).

## 3. Decisions

The product owner decided these on 2026-10-23. [decisions.md](decisions.md) gives the facts and the reasons.

| ID | Decision | Tasks |
|---|---|---|
| D-138 | The exporter takes a `CanvasContent` value. | 2.5 |
| D-139 | A Core Graphics PDF context writes the PDF. The lint rule bans it outside `Export`. | 0.2, 2.5 |
| D-140 | `TextLayout` gives the font and the lines. Export draws each line with `CTLineDraw`. | 1.2, 2.4 |
| D-141 | The page bounds come from the strokes and the full text boxes, not the cards. `contentBounds` stays. | 2.1 |
| D-142 | An empty canvas gives a message and no PDF. Emoji stay bitmaps. A page over 14,400 points scales as a whole. | 2.1, 2.2, 3.2 |
| D-143 | The item provider names the PDF after the title of the card, or of the workspace on the root canvas and for a card without a title. Characters that file names do not allow become "-". | 3.2 |
| D-144 | An export of D-56 takes at most 8.5 s, and an export of 200,000 handwriting strokes at most 17 s. The memory budgets of D-144 went under D-145. | 2.7 |
| D-145 | The export test records the memory and fails only on the time budgets. | Phase 5 |

Raise each new question as an open entry in [decisions.md](decisions.md) before the task that needs it. Do not decide it yourself (AGENT-04). The product owner decided D-143 and D-144 on 2026-10-23, and D-145 on 2026-10-24.

## 4. Tasks

### Phase 0: preparation

#### 0.1 Baseline

1. Run the full `PointerDeviceTests` once, with a result bundle.
2. Record the erase, undo, and redo steps in section 6. Also record the open of the D-56 canvas and its memory, and the frame loops. Also record the count of each allocation test and the times of `TextLayoutPerformanceTests`.

Done when: section 6 holds the baseline. Phase 5 compares against it (code-of-code.md section 5, item 10).

#### 0.2 The package, the tests, and the checks

1. Add `Rendering` to the dependencies of `Export/Package.swift` (D-140). Add a test target `ExportTests` that depends on `Export`, `Geometry`, `Model`, and `Rendering`, and excludes `References`, as `Rendering/Package.swift` does.
2. Add the folder `Export/Tests/ExportTests` as a synchronized group of `PointerDeviceTests` in `Pointer.xcodeproj`, as `Rendering/Tests/RenderingTests` is.
3. Add `Export` to the dependencies of `CanvasFeature/Package.swift`, because the canvas screen starts the export.
4. Extend `arch_04_pdf`: it also bans `CGContext(consumer:` and `beginPDFPage` outside `Packages/Export/` (D-139). Add one violation to the lint fixture of `Scripts/Fixtures`, and update the rule count that `Scripts/self-test.sh` expects.
5. Update the context map of `AGENTS.md` (AGENT-07): Export gets `Tests/ExportTests/` and `References/`, part of `PointerDeviceTests` only.
6. Leave the coverage of Export out until task 2.6, because a package without code has no report.

Done when: `make build`, `make lint`, `make layers`, and `make self-test` pass, and an empty Swift Testing suite in `ExportTests` runs on the iPad.

Rules: ARCH-02, ARCH-04, AGENT-07, D-77.

### Phase 1: geometry and text

#### 1.1 The Bézier segments of a stroke curve

1. Add a function to `StrokeCurve` that returns the 4 Bézier points of segment `i`. Segment `i` uses the extended control points `P0` to `P3` at `i - 1` to `i + 2`. The points are `(P0 + 4 P1 + P2) / 6`, `(2 P1 + P2) / 3`, `(P1 + 2 P2) / 3`, and `(P1 + 4 P2 + P3) / 6`. This conversion of a uniform cubic B-spline is exact (D-26).
2. Add Swift Testing tests (TEST-01, TEST-02) for curves of 2, 3, and 300 points. The Bézier curve of each segment matches `point(at:)` to within 1e-9 canvas points. Test 33 parameters per segment, the ends included. The first point of segment 0 is the first control point, and the last point of the last segment is the last control point.
3. Add a parameterized test for the precondition of the segment index: 0, the last segment, and one past it (TEST-06).

Done when: `swift test --package-path Packages/Geometry` passes, and the coverage of `Geometry` stays at 90 % or more.

Rules: D-26, TEST-01, TEST-02, TEST-06, CONTRACT-02.

#### 1.2 The lines of a text layout

1. Add a function to `TextLayout` that gives the lines of a text: for each line, its UTF-16 range and its `CTLine` in `TextLayout.baseFont`. It must share the line-break loop of `init(text:)`, so that the screen and the PDF break at the same places. The stored layout of the screen must not grow, because the D-56 canvas holds 10,000 text boxes (D-93).
2. Add tests on the iPad with these texts: empty, one line, a new line at the end, a long word, 10,000 code points, CJK, and emoji. For each text, the number of lines equals `lineCount`. The ranges cover the text without a gap. The glyphs of each `CTLine` equal the glyphs of that line in the layout.
3. Run `TextLayoutTests`, `TextLayoutPerformanceTests`, `TextRenderingTests`, and `TextAlignmentSnapshotTests`. The performance test must not be more than 10 % slower than the baseline of task 0.1.

Done when: the tests pass.

Rules: D-84, D-140, PERF-01, TEST-06.

### Phase 2: the exporter

#### 2.1 The page bounds

1. Add a function in `Export` that returns the page bounds of a `CanvasContent` (D-141). If the content has no stroke and no text box, it returns `nil` (D-142). The bounds are the union of `Stroke.bounds` and the rectangle of each text box from its origin and `TextLayout.size`, plus `PDFExporter.margin` of 48 points. Cards do not count.
2. Add tests for strokes only, text only, and strokes and text. Add tests for cards only and for an empty canvas, which both give `nil`. Add a test for a stroke at (1,000,000, 1,000,000).

Done when: the tests pass on the iPad.

Rules: EXP-03, D-13, D-141, D-142.

#### 2.2 The page size and the scale

1. Add a function that returns the media box and the scale for page bounds. If the longer side is at most 14,400 points, the scale is 1. If not, the scale is 14,400 divided by the longer side, and the media box is the bounds times the scale (D-142). Put 14,400 in a named constant with its source, ISO 32000 Annex C (DOC-03).
2. Add a parameterized test with a longer side of 3 points, 14,400 points, 14,401 points, and 2,000,000 points, in width and in height (TEST-06). No side of a media box is over 14,400 points.

Done when: the tests pass.

Rules: EXP-03, D-142, DOC-03, TEST-06.

#### 2.3 The strokes

1. Draw each stroke as one `CGPath` of the Bézier segments of task 1.1. Use black, the width of the stroke, `.round` caps, and `.round` joins. Compute each point relative to the page origin in `Double`, then convert it to `CGFloat`. Then a stroke at (1,000,000, 1,000,000) keeps its shape (M2 acceptance 3).
2. Read the points with `Stroke.canvasPoint(at:)`. Do not keep a `StrokeCurve` of all strokes at once.
3. Add tests for strokes of 2 and 300 points. The path has one `move` and `count - 1` curves. The first and the last point equal the end control points. The path of a stroke at (1,000,000, 1,000,000) equals the moved path of the same stroke at the origin.

Done when: the tests pass.

Rules: EXP-02, D-26, M2 acceptance 3.

#### 2.4 The text

1. Draw each text box with the lines of task 1.2 and `CTLineDraw`, in black, at the baselines of section 2.3. Flip the text matrix for the coordinate system of the PDF (D-140).
2. Do not draw glyph IDs. The probe of D-140 shows that the PDF then loses the text.
3. Add tests that read the PDF back with PDFKit. A search finds each word of each text box. The page text holds no title of a card. A text with emoji and CJK keeps its letters.

Done when: the tests pass.

Rules: EXP-02, D-84, D-140, D-142.

#### 2.5 `PDFExporter`

1. Add `PDFExporter` with one function that takes a `CanvasContent` and returns the PDF `Data`, or throws `ExportError` (SAFE-04). `ExportError` holds the case of an empty canvas and the case of a failed PDF context.
2. Make the PDF with `CGContext(consumer:mediaBox:_:)`, one page, `beginPDFPage`, a white fill, the strokes, the text, `endPDFPage`, and `closePDF` (D-139). Apply the scale of task 2.2 to the whole page.
3. The function is not bound to an actor, so that the canvas can run it off the main actor. It reads only its argument (TEST-04).
4. Add an `OSSignposter` interval "Export" (PERF-03).
5. Add tests. An empty canvas throws. A canvas gives one page with the media box of task 2.2. The PDF of an ink-only canvas holds no image, because the ink is vector paths (EXP-02). An export in a `Task.detached` gives the same page text and media box as on the main actor.

Done when: the tests pass.

Rules: EXP-02, EXP-03, D-138, D-139, SAFE-04, PERF-03, CONTRACT-01.

#### 2.6 The snapshot of a PDF page and the coverage

1. Add `PDFSnapshotTests` (acceptance 2). The content holds strokes, two text boxes, and a card with a title. Export it, render the page with `UIGraphicsImageRenderer` and `drawPDFPage`, and compare it with a reference PNG (TEST-07). The image shows a white page, black ink and text, and no card.
2. The iPad makes the reference. Look at it before you commit it.
3. Add the class to the `snapshots` target of the `Makefile`.
4. Add `Export` with 70 % to `Scripts/coverage.swift`, and read the Export framework in the `coverage` target of the `Makefile`, as for `Rendering`. Update the comment that says Export has no tests.

Done when: `make snapshots` and `make coverage` pass.

Rules: TEST-02, TEST-07, D-13, D-120.

#### 2.7 The measures of an export

1. Add `ExportPerformanceTests`. Export the D-56 canvas (20,000 strokes and 10,000 text boxes) and the 200,000 handwriting strokes of `FrameLoopTests`. Record the time, the peak memory growth, and the size of the PDF of each.
2. Record the measures in section 6. No budget exists for an export (architecture.md section 12). Raise D-144 with the measures and a recommended budget, and wait for the product owner.

Done when: section 6 holds the measures, and D-144 is decided.

Rules: PERF-03, AGENT-04.

### Phase 3: the button and the share sheet

#### 3.1 The export button

1. Add `DesignSystem.Icon.export` with the SF Symbol `square.and.arrow.up` (STYLE-03). Add the string "Export" to the String Catalog of the canvas (STYLE-05).
2. Add the button to `HistoryButtons`, next to undo and redo (EXP-01). It is off while an export runs.
3. Make the references of `HistoryButtonsSnapshotTests` again on the iPad, and look at them before you commit them (TEST-07).

Done when: `HistoryButtonsSnapshotTests` passes.

Rules: EXP-01, STYLE-03, STYLE-05, TEST-07.

#### 3.2 The export of the shown canvas

1. The button ends a running text edit first, as a tool change does (D-87), so that the PDF holds the text of the edit.
2. If the canvas has no stroke and no text box, show the message of D-142 and stop. Add the message to the String Catalog.
3. Copy `content`, and run `PDFExporter` in a `Task` off the main actor. The task holds the canvas screen weakly.
4. Give the PDF to `UIActivityViewController(activityItemsConfiguration:)` through an `NSItemProvider` with `UTType.pdf` and the name of D-143. Do not write a file (ARCH-04). Anchor the popover at the export button.
5. A failure shows a message and writes a log entry without content (SAFE-06).

Done when: the code passes the tests of task 3.3.

Rules: EXP-01, EXP-04, D-87, D-142, D-143, ARCH-04, PERF-02.

#### 3.3 Tests of the export action

1. Test the code behind the button. An empty canvas and a canvas with only cards show the message. A running text edit ends, and its text is in the PDF. The item provider has the type PDF and the name of D-143. A second tap during an export starts no second export.
2. Add a test that the canvas screen goes away after an export, as `CanvasLifetimeTests` checks after a leave.
3. Run `TextEditTests`, `HistoryTests`, `CanvasLifetimeTests`, and `AppMessageTests`.

Done when: the tests pass.

Rules: TEST-03, TEST-04, EXP-04.

### Phase 4: manual acceptance

#### 4.1 The manual tests for the product owner

1. Acceptance 1. Draw ink and write text with Scribble on a canvas. Export it, and send the PDF to the Mac. Open it in Preview. Zoom to 6400 %: the ink stays sharp. Select a line of text, and search a word.
2. Export a canvas with a card. The PDF shows no card.
3. Export a canvas with ink far apart, so that the page is over 14,400 points. Preview opens it, and the ink keeps its proportions.
4. Write a text with an emoji and export it. The emoji shows, and a search finds the text around it.
5. Export an empty canvas. The message shows, and no share sheet opens.
6. Record each result in section 6.

Done when: the product owner reports a pass for each test, or decides about a failure.

Rules: EXP-01 to EXP-04, D-13, D-142.

### Phase 5: close

1. Run `make check` with the iPad, and `make coverage`.
2. Run the full `PointerDeviceTests` 5 times in a row (D-79). Compare each measure with the baseline of task 0.1. A measure can be at most 10 % slower.
3. Fill in section 6 of this plan, and the M8 status in [plan.md](plan.md).
4. Update the context map of `AGENTS.md` if a folder is new (AGENT-07).

Done when: each step passes, or the product owner accepts the failure.

Rules: AGENT-05, DOC-06, D-79.

## 5. Facts to keep in mind

- `CanvasViewController` has a type body limit of 250 lines and a function body limit of 40 lines (SwiftLint). Put new code in an extension file, for example `CanvasViewController+Export.swift`.
- The assertion density script needs 2.00 checks per function in Tier A and Tier B packages (CONTRACT-02, `make density`). `Export` is Tier B. `Rendering` is exactly at 2.00, so each new function there needs its two checks.
- A test that keeps a canvas screen in a local constant keeps it alive until the end of the scope. Put the steps of a round in a function of their own (`CanvasLifetimeTests`).
- A test helper that gives a closure to the composition must capture it weakly, or the composition stays alive after the test.
- `#expect` cannot hold a call of a mutating method. Assign the result to a constant first.
- `AppMessageTests` "A message shows while the palette is open" can fail in a full run, and `testSnapshotOfTwentyThousandStrokesWithSaves` can take just over 50 ms. Both are older than M8, and M10 holds them.
- A new file in a synchronized group joins the next device build. Do not add files while `make check` runs.

## 6. Results

Fill in this section during the work.

### 6.1 Baseline (task 0.1)

Measured on 2026-10-23 on the iPad Pro 11-inch (M4) in Release, with the code of commit e986140 (the code of 55d43ea). The run is one full run of `PointerDeviceTests` with the result bundle `.build/Runs/m8-baseline.xcresult`. It took 296 s, and all 358 tests passed.

| Step | Median | Slowest | Steps |
|---|---|---|---|
| Erase | 20.83 ms | 25.57 ms | 5 |
| Undo | 16.88 ms | 20.21 ms | 5 |
| Redo | 19.01 ms | 24.58 ms | 5 |

The main-thread calls of `EraseUndoPerformanceTests` took 4.9 to 12.7 ms.

The open of the D-56 canvas (`CanvasOpenPerformanceTests`) took a median of 248.2 ms and at most 259.9 ms over 10 opens, from the tap to the first frame. The load part took 69.7 to 86.1 ms. The memory of the open canvas was 339 MB held and 351 MB at the peak. The transition between two D-56 canvases held 223 MB for the parent, 353 MB at the peak of the open, 297 MB after the open, and 434 MB at the peak of the leave, and it freed the parent.

| Card flight | Time | Frames | Late | Held |
|---|---|---|---|---|
| Open of the D-56 card | 469 ms to the child | 56 | 0 | 0 |
| Leave of the D-56 card | 595 ms | 2 child, 43 parent | 0 | 0 |
| Open of the empty card | 471 ms to the child | 56 | 0 | 0 |
| Leave of the empty card | 490 ms | 2 child, 43 parent | 0 | 0 |
| Open, main thread blocked | 465 ms to the child | 56 | 0 | 0 |
| Leave, main thread blocked | 488 ms | 2 child, 43 parent | 0 | 0 |

Each frame loop of `FrameLoopTests` ran at 120.0 fps with 0 late frames of 479.

| Frame loop | Main ms, mean / p99 / max | Render ms, p50 / max | GPU ms, p50 / max | Allocations, p50 / p99 / max | Uncovered |
|---|---|---|---|---|---|
| few pan | 0.01 / 0.03 / 0.04 | 0.17 / 0.30 | 0.35 / 1.60 | 17 / 33 / 36 | 0 / 480 |
| dense 20k pan | 0.01 / 0.03 / 0.04 | 0.20 / 2.86 | 0.35 / 2.62 | 17 / 2,256 / 2,641 | 0 / 480 |
| dense 20k fast pan | 0.00 / 0.04 / 0.06 | 0.22 / 2.87 | 0.35 / 2.63 | 26 / 2,482 / 3,184 | 0 / 480 |
| dense 20k zoom | 0.00 / 0.03 / 0.04 | 0.19 / 2.78 | 0.35 / 2.91 | 17 / 2,032 / 2,097 | 0 / 480 |
| handwriting 200k pan | 0.01 / 0.03 / 0.04 | 0.20 / 2.18 | 0.35 / 5.07 | 17 / 2,170 / 2,175 | 0 / 480 |
| handwriting 200k zoom | 0.01 / 0.03 / 0.04 | 0.19 / 2.69 | 0.35 / 4.32 | 17 / 2,161 / 2,176 | 0 / 480 |
| D-56 text pan | 0.01 / 0.03 / 0.05 | 0.24 / 3.51 | 0.40 / 2.39 | 36 / 2,064 / 2,224 | 120 / 480 |
| D-56 text zoom | 0.01 / 0.02 / 0.05 | 2.19 / 3.55 | 0.83 / 3.47 | 50 / 2,673 / 4,339 | 0 / 480 |
| D-56 cards pan | 0.00 / 0.00 / 0.01 | 0.44 / 2.44 | 0.67 / 5.07 | 238 / 8,587 / 9,539 | 0 / 480 |
| D-56 cards pan at zoom 1 | 0.00 / 0.00 / 0.01 | 0.12 / 0.90 | 0.79 / 7.06 | 89 / 2,613 / 2,621 | 0 / 480 |
| D-56 cards zoom | 0.00 / 0.01 / 0.04 | 0.38 / 3.33 | 0.64 / 4.86 | 221 / 6,500 / 8,065 | 0 / 480 |

The preview render of D-56 took 39.0 ms. The eraser frame took 0.13 ms on the CPU and 0.36 ms on the GPU at the median, and at most 0.22 and 1.57 ms.

| Allocation test | Count |
|---|---|
| `FrameAllocationTests` | frame p50 15, bare Metal frame p50 15 |
| `TransitionAllocationTests`, flight frame | p50 15, bare frame p50 15 |
| `TransitionAllocationTests`, open frame | p50 15, bare frame p50 15 |
| `PreviewAllocationTests` | card pass p50 2, bare pass p50 2 |
| `TextPassAllocationTests` | text pass p50 2, bare pass p50 2 |
| `TextMoveAllocationTests`, move step | median 6 |
| `EditAllocationTests` | `FrameRenderer.apply`: erase 14, undo 2, redo 1 |
| `HoverSampleAllocationTests`, pen and eraser | hover 0, bare move 0 |
| `TextEditFrameAllocationTests`, short and long text | edit frame max 4, bare move max 4 |
| `ZoomFrameAllocationTests` | spring median 0, max 140, glide max 0 |

`TextLayoutPerformanceTests` laid out 5,000 boxes in a median of 57.6 ms. `TextPassPerformanceTests` took a median of 0.830 ms for 300 boxes and 48,000 glyphs.

### 6.2 Geometry and text (tasks 1.1 and 1.2)

Task 1.1, on 2026-10-23 on the Mac: `StrokeCurve.bezierSegment(at:)` gives a `BezierSegment`. For curves of 2, 3, and 300 points, the largest distance between the Bézier segments and `point(at:)` at 33 parameters per segment was below 1e-9 canvas points. The ends equal the end control points. Exit tests cover the preconditions of the segment index and of the Bézier parameter. All 40 Geometry tests pass, and the line coverage of `Geometry` is 90.88 % (518 of 570 lines).

Task 1.2, on 2026-10-23 on the iPad in Release: `TextLayout.lines(of:)` gives the UTF-16 range and the `CTLine` of each line. It shares the private line-break loop `breakLines(of:_:)` with `init(text:)`, and the stored layout did not change. `TextLineTests` passes for the empty text, one line, a new line at the end, a long word, 10,000 code points, CJK, and emoji. `TextLayoutTests`, `TextRenderingTests`, and `TextAlignmentSnapshotTests` pass (result bundle `.build/Runs/T12-text-1.xcresult`). `TextLayoutPerformanceTests` laid out 5,000 boxes in a median of 54.6, 55.7, and 54.8 ms in three runs, against 57.6 ms in the baseline. The density of `Rendering` stays at 2.00 (237 functions, 474 checks).

### 6.3 The exporter (tasks 2.1 to 2.6)

Measured on 2026-10-23 on the iPad in Release.

1. Task 2.1 (commit 0fba8a5): `PDFExporter.pageBounds(of:)`. `PageBoundsTests` passes: strokes only, text only, strokes and text, a far card that does not count, cards only and an empty canvas (`nil`), and a stroke at (1,000,000, 1,000,000).
2. Task 2.2 (commit c76bdbf): `PDFExporter.pageLayout(for:)` and `PageLayout`. `PageLayoutTests` passes for a longer side of 3, 14,400, 14,401, and 2,000,000 points, in width and in height.
3. Task 2.3 (commit b110609): `PDFExporter.path(of:from:)` and `drawStrokes`. `StrokePathTests` passes: one move and `count - 1` curves for 2 and 300 points, the end points, and the same path within 1e-6 points for a stroke at (1,000,000, 1,000,000). The test reads the path elements in `PathElements+Unsafe.swift` (SAFE-09).
4. Task 2.4 (commit e7c46f5): `drawText` with `CTLineDraw`. `PDFTextTests` passes: PDFKit finds each word of two text boxes, "balanced" 30 times, the emoji, the CJK, and the Hangul, and the lines are in order from top to bottom.
5. Task 2.5 (commit bb5fbb1): `PDFExporter.pdfData(of:)` and `ExportError`. `PDFExporterTests` passes: an empty canvas and a canvas with only cards throw `emptyCanvas`, one page with the media box of the layout, no card title in the page text, no XObject on an ink-only page that shows more than 1,000 dark pixels, a page over 14,400 points with its proportions kept, and the same page text and media box from a detached task.
6. Task 2.6: `PDFSnapshotTests` compares the page at scale 2 with `References/pdf-page.png` (830 by 869 pixels). The card lies inside the page, and the image shows no card. The first image had a dark last column, because the media box is not a whole number of pixels. `PDFRender` now cuts the image to whole pixels. `make snapshots` passes. `make coverage` passes: Geometry 90.88 %, Model 90.80 %, InkEngine 92.73 %, Persistence 91.15 %, Rendering 86.95 %, and Export 87.14 % (122 of 140 lines). In the instrumented run, `EraseUndoPerformanceTests` failed, as the `coverage` target of the `Makefile` expects.

### 6.4 The measures of an export (task 2.7)

Measured on 2026-10-23 on the iPad in Release, with `ExportPerformanceTests` in two runs (result bundles `.build/Runs/T27-1.xcresult` and `.build/Runs/T27-2.xcresult`). Each test exports once in a detached task, as the canvas will do, and reads `os_proc_available_memory` every 2 ms. The test makes sure that the PDF has a page.

| Content | Time | Peak memory growth | PDF size |
|---|---|---|---|
| D-56: 20,000 strokes of 300 points, 5,000 cards, 5,000 text boxes | 6.92 s, 7.06 s | 101 MB, 101 MB | 79.6 MB |
| 20,000 strokes of D-56 and 10,000 text boxes | 7.43 s, 7.52 s | 137 MB, 137 MB | 79.8 MB |
| 200,000 handwriting strokes of `FrameLoopTests` | 14.77 s, 14.83 s | 277 MB, 235 MB | 226.4 MB |

Task 2.7 names "the D-56 canvas (20,000 strokes and 10,000 text boxes)", but D-56 holds 5,000 cards and 5,000 text boxes. The test measures both. The strokes take almost all of the time: about 1.1 to 1.3 µs per Bézier segment, for 6.0 million segments in D-56 and 11.8 million in the handwriting. The product owner decided D-144 on 2026-10-23: the recommendation, (a), with 160 MB for D-56 and 320 MB for the handwriting. With these budgets, the test failed: D-56 peaked at 261 MB in 3 of 6 runs (result bundles `.build/Runs/T27-3.xcresult` to `T27-6.xcresult`), and the handwriting at up to 331 MB. The reads every 2 ms missed short peaks. Two copies of the PDF caused them: the bridge from `NSMutableData` to `Data` copies the whole buffer (a probe on the Mac showed that `as Data` and `Data(referencing:)` do not share the bytes), and the growing buffer can move. The product owner chose to remove the copy first.

After the fix, `PDFExporter.data(sharing:)` gives `Data` that shares the bytes of the buffer, and `PDFBufferTests` makes sure that the addresses match. The test reads the memory every 0.25 ms. Four runs (`T27-7.xcresult` to `T27-10.xcresult`):

| Content | Time | Peak memory growth |
|---|---|---|
| D-56 | 6.97, 7.04, 7.25, 7.30 s | 100, 100, 100, 101 MB |
| 20,000 strokes of D-56 and 10,000 text boxes | 7.49, 7.53, 7.65, 7.68 s | 121, 128, 136, 131 MB |
| 200,000 handwriting strokes | 14.89, 14.92, 15.01, 15.06 s | 323, 276, 227, 220 MB |

The product owner decided D-144 again on the same day: D-56 at most 8.5 s and 120 MB, and 200,000 handwriting strokes at most 17 s and 370 MB. `ExportPerformanceTests` fails above them. The first run with these budgets passed (`T27-11.xcresult`): D-56 6.98 s and 91 MB, 10,000 text boxes 7.50 s and 122 MB, and the handwriting 14.87 s and 320 MB.

At the close (phase 5), the full run of `make check` failed the budget of D-56 with 178 MB, and it reported 0 MB for the export with 10,000 text boxes. The export reused memory that the content build had freed just before, and other tests of the full run free and take memory. `ExportPerformanceTests` now waits for 1.5 s of steady memory with `OnScreenCanvas.waitForSteadyMemory()` before it measures. Four runs alone (`.build/Runs/P5-fix-1.xcresult` to `P5-fix-4.xcresult`):

| Content | Time | Peak memory growth |
|---|---|---|
| D-56 | 6.95, 7.10, 7.25, 7.27 s | 153, 139, 150, 152 MB |
| 20,000 strokes of D-56 and 10,000 text boxes | 7.47, 7.54, 7.64, 7.65 s | 139, 139, 144, 142 MB |
| 200,000 handwriting strokes | 14.84, 14.91, 14.99, 15.02 s | 279, 265, 281, 273 MB |

The product owner decided D-144 a third time on the same day: D-56 at most 8.5 s and 180 MB, and 200,000 handwriting strokes at most 17 s and 370 MB.

### 6.5 The button and the share sheet (tasks 3.1 to 3.3)

Task 3.1, on 2026-10-23 on the iPad in Release: `DesignSystem.Icon.export` (`square.and.arrow.up`), the string "Export", and the third button of `HistoryButtons`, which is off while `HistoryControls.isExporting` is `true`. The iPad made the references of `HistoryButtonsSnapshotTests` again, 288 by 88 pixels, and I looked at them before the commit. A new case shows the export button off during an export. The 4 tests pass (`.build/Runs/T31-3.xcresult`).

Tasks 3.2 and 3.3, on 2026-10-23 on the iPad in Release. `CanvasViewController+Export.swift` ends a running text edit, shows the message "This canvas holds no ink and no text to export." for a canvas without strokes and text boxes, and runs `PDFExporter` in a detached task from a copy of the content. `CanvasExport` holds the running task, the anchor view, and the `share` closure that opens `UIActivityViewController(activityItemsConfiguration:)` with an `NSItemProvider` of the type PDF. `PDFFileName` makes the name of D-143. It also cuts a name over 255 UTF-8 bytes, the name limit of APFS, because a title of 120 CJK characters has 360 bytes. `PointerApp` gives the workspace title through `CanvasDependencies.workspaceTitle`. A failed export shows "The PDF could not be made." and logs the error without content.

`ExportActionTests` passes: an empty canvas and a canvas with only cards show the message and start no export, a running edit ends and PDFKit finds its text in the PDF, the provider has the type PDF and the name "Trees.pdf" or the card title "AVL.pdf", a second tap starts no second export, and the screen goes away after an export. `PDFFileNameTests` passes. `TextEditTests`, `CanvasHistoryTests`, `CanvasLifetimeTests`, `AppMessageTests`, and `HistoryButtonsSnapshotTests` pass (39 tests, `.build/Runs/T33-3.xcresult`).

### 6.6 Manual tests (task 4.1)

The product owner tested on 2026-10-23 with the iPad Pro 11-inch (M4) and a Mac, with the Release build of commit d2066dd, and reported:

1. Acceptance 1, ink, zoom to 6400 %, select, and search: "stroke stays sharp and search works."
2. A canvas with a card: "No cards shown"
3. A page over 14,400 points: "Works"
4. A text with an emoji: "OK"
5. An empty canvas: "The dialog is shown"

The product owner did not report the name of the PDF on the Mac.

### 6.7 Close (phase 5)

Measured on 2026-10-23 on the iPad in Release.

1. The first `make check` failed in `make test`: `ExportPerformanceTests.testExportOfD56Canvas` (178 MB against 120 MB) and `ToolControlsSnapshotTests.palette(tool:)` ("Size 612x112 differs from the reference 512x112"). The palette reused `HistoryButtons` and showed the export button too. Commit e0c8e65 keeps the button out of the palette. Commit 185a261 makes the export measure start at steady memory, and the product owner set the D-56 budget to 180 MB (section 6.4).
2. The second `make check` passed: 0 analyzer findings, format, lint, layers, density (Export 2.14), self-test, plist, and all tests on the Mac and the iPad (`.build/Runs/P5-check2.log`).
3. `make coverage` passed: Geometry 90.88 %, Model 91.08 %, InkEngine 92.73 %, Persistence 91.15 %, Rendering 86.87 %, and Export 87.20 % (143 of 164 lines).
4. Five full runs of `PointerDeviceTests` (`.build/Runs/P5-full-1.xcresult` to `P5-full-5.xcresult`) ran 395 tests each. Run 3 passed. The other runs failed one test each:
   - Runs 1 and 4: `ExportPerformanceTests.testExportOfD56Canvas`, 198 MB and 210 MB against 180 MB. The export with 10,000 text boxes read 0, 8, 1, 0, and 8 MB in the five runs, so the memory measure of one export in a full run is not reliable. D-145 holds the question.
   - Run 2: `TextEditFrameAllocationTests.testGlideFramesWithALongText`, edit frame max 5 against bare move max 4. Alternating runs (item 6) show the same failure on the base build.
   - Run 5: `SnapshotPerformanceTests.testSnapshotOfTwentyThousandStrokesWithSaves`, 54.66 ms against 50 ms. Section 5 lists this failure as older than M8, and M10 holds it.
   - Runs 1 and 2 also had the expected failure of D-137 in `OpenAnimationTests`.
5. The measures of the five runs against the baseline of section 6.1:

| Measure | Baseline | Five runs |
|---|---|---|
| Erase, median | 20.83 ms | 23.40, 22.81, 24.77, 21.15, 24.43 ms |
| Undo, median | 16.88 ms | 17.02, 18.16, 17.84, 17.66, 18.60 ms |
| Redo, median | 19.01 ms | 17.79, 21.32, 21.50, 20.67, 19.51 ms |
| Open of D-56, median | 248.2 ms | 254.2, 252.4, 257.8, 258.9, 253.2 ms |
| Memory of the open canvas, held / peak | 339 / 351 MB | 333 to 337 / 334 to 349 MB |
| Transition, open peak / leave peak | 353 / 434 MB | 334 to 366 / 416 to 447 MB |
| Text layout of 5,000 boxes | 57.6 ms | 56.7 to 57.5 ms |
| Text pass of 300 boxes | 0.830 ms | 0.836 to 0.873 ms |
| Preview render of D-56 | 39.0 ms | 37.6 to 45.9 ms |
| Export of D-56 | none | 6.94 to 6.99 s |
| Export of 200,000 handwriting strokes | none | 14.79 to 14.88 s, 272 to 316 MB |

   Each frame loop ran at 119.7 to 120.0 fps, with at most 1 late frame of 479 in the D-56 text loops, and main ms max at most 0.08. The allocation counts equal the baseline: frame 15 / bare 15, apply 14 / 2 / 1, move step 6, and zoom spring median 0, max 140.
6. One baseline run is not a fair comparison, so the erase steps and the glide allocations ran in 6 alternating pairs of the base build 55d43ea and the new build (`.build/Runs/P5-alt-*.xcresult`, section 1.3 of m6-fix-plan.md):

| Build | Erase, median per run | Undo, median per run | Redo, median per run |
|---|---|---|---|
| Base | 22.91, 23.82, 25.02, 21.34, 22.44, 24.25 ms (mean 23.30) | 20.50, 16.35, 19.11, 17.50, 17.09, 17.39 ms (mean 17.99) | 22.45, 21.54, 24.31, 23.36, 19.52, 18.16 ms (mean 21.56) |
| New | 24.83, 25.15, 22.84, 25.76, 24.03, 25.03 ms (mean 24.61) | 20.32, 16.94, 17.60, 19.14, 19.09, 19.94 ms (mean 18.84) | 21.78, 17.56, 21.17, 21.04, 20.58, 19.99 ms (mean 20.35) |

   The new build is 5.6 % slower on erase (slower in 5 of 6 pairs), 4.7 % slower on undo, and 5.6 % faster on redo. Each is under the limit of 10 % (code-of-code.md section 5, item 10). The glide check failed in 1 of 6 base runs and in 2 of 6 new runs, always with an edit frame of 5 against 4, so the failure is older than M8.

D-145, decided on 2026-10-24. A try of the malloc count in a run alone (`.build/Runs/D145-alone-1.xcresult`) read 228 MB for D-56, 228 MB for 10,000 text boxes, and 539 MB for the handwriting, whose free memory grew only 198 MB, and the handwriting export took 16.04 s. The product owner then chose time budgets only. `ExportPerformanceTests` records the free-memory growth after the steady wait and fails only above 8.5 s for D-56 and 17 s for the handwriting.

