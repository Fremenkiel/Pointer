# Build plan

This document gives the build order, the state of each milestone, and the open work. A milestone is done only with all of its acceptance criteria met and the checklist in [code-of-code.md](code-of-code.md) section 5 passed. Each milestone ended with a demo on a real iPad.

The task lists of the milestones (`m2-plan.md` to `m11-plan.md` and the fix plans) left `docs/` after the close of each milestone. Git history holds them: `git show e5d3105:docs/m10-plan.md` and `git show aac9ac4:docs/m11-plan.md`. [decisions.md](decisions.md) records each decision of the product owner with its date, and the review documents record the code reviews.

## 1. Milestones

All eleven milestones are done. The dates are the days of the close on the iPad Pro 11-inch (M4).

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
| M11 | Review fixes: the open findings of the review of 2026-10-28, the decisions D-194 to D-196 | 2026-10-30 | Each item of section 3.2 and items 1 to 7 of section 3.4 of the review is closed with a test or a commit body. Items 3.3.1 to 3.3.4 and 3.3.10 showed no gain in pairs on the iPad, so their code stays as it was. `make perf-compare` in the normal state after a restart first failed the text pass and the stored text build of task 4.4 by 28 to 83 %, fixed in aac9ac4, and then passed 134 samples with 2 fails, the text zoom GPU p50 (+31 %) and the save p99 (+58 %), which the baseline commit f8e4c0b fails by the same amounts in 5 pairs on the same day (section 2, D-198). |

## 2. Acceptance criteria of the last milestone

M11 had three acceptance criteria:

1. Every item of section 3.2 and items 1 to 7 of section 3.4 of the review of 2026-10-28 is closed. Passed: each item has a test, or a commit body that says why the finding was wrong. Items 3.3.1 to 3.3.4 and 3.3.10 showed no gain in pairs on the iPad, so their code stays as it was, and their tests stay.
2. `make perf-compare` passes against the baseline of f8e4c0b in the normal state of the iPad. Not met by two samples of the iPad. The compare of 2026-10-30, after a restart, first failed the text pass of D-56 at zoom 1 by 28 % and the stored text build at zoom 1 by 61 to 83 %: the shared glyph walk of task 4.4 gave the glyph and its place back as one optional per call. Commit aac9ac4 keeps the shared step inlined in both loops, and 5 pairs against 09cf989 give 0.836 against 0.873 ms. The compare then passed 134 samples with 2 fails and 0 unsure: the text zoom GPU p50 (0.54 to 0.71 ms, +31 %) and the save p99 of the same saves (0.58 to 0.92 ms, +58 %). The baseline commit f8e4c0b gives 0.70 ms and 0.59 ms in 5 alternating pairs against aac9ac4 (0.66 ms and 0.60 ms) on the same day, so the iPad changed since the baseline of 2026-10-27, not the code. The product owner closed M11 with this result on 2026-10-30, and the baseline stays (D-198).
3. Coverage meets TEST-02. Passed: Geometry 91.4 %, Model 91.9 %, InkEngine 94.1 %, Persistence 91.5 %, Rendering 88.8 %, and Export 90.7 % of lines.

`make validation` passed with 435 tests, `make snapshots` with 60 tests, the full `PointerDeviceTests` with 517 tests, and the UI tests of `PointerUITests` with 7 tests, on aac9ac4.

## 3. Work that waits for the product owner

Nothing waits for the product owner. On 2026-10-30, the product owner closed M11 with the compare result of section 2, kept D-195, and dropped the open points of M10 and M11 (D-198): the seven manual pencil tests of the M10 close, the QuartzCore crash of 1 of 10 full runs on f8e4c0b, the black capture of a presented alert early in a full run, and the review items 3.3.7, 3.3.8, 3.3.9, and 3.3.11 without a measure. The entry D-198 of decisions.md records each point.

## 4. Next milestone

No next milestone is planned. The candidates come from the next review.

On 2026-10-30, after the close of M11, the product owner asked for two features. The first is a choice of three pen widths in the palette (TOOL-09, D-199). The second is a clear canvas command behind a question, as one undo step (TOOL-10, D-200). Both are built with their tests and their snapshot references.
