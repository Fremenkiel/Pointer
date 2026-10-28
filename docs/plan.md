# Build plan

This document gives the build order, the state of each milestone, and the open work. A milestone is done only with all of its acceptance criteria met and the checklist in [code-of-code.md](code-of-code.md) section 5 passed. Each milestone ended with a demo on a real iPad.

The task lists of the milestones (`m2-plan.md` to `m10-plan.md` and the fix plans) left `docs/` after the close of M10. Git history holds them: `git show e5d3105:docs/m10-plan.md`. [decisions.md](decisions.md) records each decision of the product owner with its date, and the review documents record the code reviews.

## 1. Milestones

All ten milestones are done, and M11 is planned. The dates are the days of the close on the iPad Pro 11-inch (M4).

| Milestone | Scope | Done | Notes |
|---|---|---|---|
| M0 | Project skeleton: Xcode project, the packages, the check scripts, `AGENTS.md` | 2026-10-17 | |
| M1 | Latency test: PencilKit, a custom Metal input path, and the hybrid | 2026-10-17 | The custom input path trailed the pencil. Pointer uses the hybrid (D-02, D-33). The product owner compared by eye and skipped the camera measurement (research.md section 3.5). |
| M2 | Ink on one canvas: `Geometry`, `Model`, the point arena, the B-spline shader, the committed texture, pan and zoom | 2026-10-18 | 200,000 strokes pan and zoom at 120 Hz. Pen latency of about 25 ms accepted (D-40). |
| M3 | Storage and workspaces: SQLite repository, snapshots, the workspace selector, device state | 2026-10-19 | A force quit loses at most 2 seconds of ink. The D-56 canvas opens in under 300 ms. |
| M4 | Eraser and undo: `InkEngine`, the commands and `History`, the eraser mask, the palette | 2026-10-20 | Erase, undo, and redo of 1,000 strokes in under 33 ms per step (D-75, D-79). |
| M5 | Text boxes: the text tool, the edit view, the glyph atlas, move and delete | 2026-10-21 | Scribble works. Text on the canvas and in edit mode line up within 1 pixel. |
| M6 | Cards and navigation: card creation, previews, open, the up button, the pinch-out exit | 2026-10-22 | No visible jump at an open or a leave. A tree of 32 levels works. |
| M7 | Apple Pencil interactions: double tap, squeeze, the hover dot | 2026-10-23 | Each pencil model works. Drawing plays no haptic. |
| M8 | PDF export: `Export`, the export button, the share sheet | 2026-10-24 | Vector ink and searchable text. The checkpoint design of D-146 and D-147. |
| M9 | Backup: "Back up now" and restore | 2026-10-24 | A restore gives the same rows. A restore on a new device ID works. |
| M10 | Hardening: limits, UI tests, baselines, stored glyph quads, accessibility, the review items of M7 to M9 | 2026-10-27 | `make perf-compare` passes 136 samples with 0 failures against the baseline of f8e4c0b. `make coverage` gives 88.8 % to 94.1 % per package. |
| M11 | Review fixes: the open findings of the review of 2026-10-28, the decisions D-194 to D-196 | | Planned. The M11 plan ([m11-plan.md](m11-plan.md)) holds the tasks. |

## 2. Acceptance criteria of the last milestone

M10 had two acceptance criteria:

1. All performance tests pass against their baselines on the device. Passed: `make perf-compare` on f8e4c0b passed 136 time samples with 0 failures, and 59 samples are recorded without a gate.
2. Coverage meets TEST-02. Passed: Geometry 91.2 %, Model 91.9 %, InkEngine 94.1 %, Persistence 91.2 %, Rendering 88.8 %, and Export 90.7 % of lines.

`make validation` passed with 420 tests. Ten full runs of `PointerDeviceTests` passed with 501 tests each, after one run in which the test process crashed in QuartzCore (section 4, item 3).

## 3. Work that waits for the product owner

1. The seven manual tests with the pencil of the close of M10, on the iPad:
   1. The message at the stroke limit: draw past the limit of a canvas, read "This canvas holds no more ink. Erase some ink or draw in a card.", erase some ink, and draw again.
   2. The text at zoom 0.25 and 8 with the stored glyph quads: open the D-56 canvas, zoom out to 0.25 and in to 8, pan over the text at both, and compare the glyphs with zoom 1.
   3. The open and the leave of cards: tap a card, draw in the child, leave with the up button, and look at the preview of the card.
   4. The previews of a screen of many cards at zoom 0.25 (D-193): on a canvas of about 2,000 cards, hold the camera still and then pan. Each card on the screen shows its preview, and the screen rests.
   5. VoiceOver on each button: turn VoiceOver on, and move over the bar, the selector, and the card menu. Each button has a label and a hint.
   6. The selector at the largest text size: set the text size to AX5 in Settings, open the selector, and look at each row.
   7. The Large Content Viewer: at an accessibility text size, long press each button of the bar. The viewer shows the icon and the name.
2. A finding without a fix. In 1 of 10 full runs of `PointerDeviceTests` on f8e4c0b, the test process crashed with `EXC_BAD_ACCESS` in `+[CADisplayLink notifyDisplayChange:]`. The crash came on a QuartzCore queue with no frame of Pointer in that thread. The main thread removed a canvas view in `RestoreFlowTests` at that moment. Ten more full runs and 20 runs of the suites in that process did not crash. The cause is a race in QuartzCore between a display change and the removal of a view.
3. The UI tests after the review of 2026-10-28. `make test` runs them first, and the iPad asks for its passcode (D-192).
4. `make perf-compare` after the review of 2026-10-28, after a restart of the iPad. On 2026-10-28, the compare failed 6 samples of the card frame loop, the erase undo, and the save. The base commit e5d3105 fails the same samples by the same amounts. The review code against the base commit passes all 26 samples in 5 pairs. The iPad thus runs in a state other than the normal state of the baseline. Section 7 of the review holds the numbers.

## 4. Next milestone

The next milestone is M11, review fixes. The product owner picked the candidates of section 4 of the review of 2026-10-28 ([review-2026-10-28.md](review-2026-10-28.md)) on 2026-10-28, with the decisions D-194 to D-197. The M11 plan ([m11-plan.md](m11-plan.md)) holds the tasks in that order. Task 4.3 of M10 is closed (D-197).
