# M11 work plan: review fixes

This document breaks milestone M11 of [plan.md](plan.md) into tasks. The tasks take the open findings of [review-2026-10-28.md](review-2026-10-28.md), in the order of its section 4. They build on the decisions D-194 to D-197, which the product owner decided on 2026-10-28.

Read [AGENTS.md](../AGENTS.md) and [code-of-code.md](code-of-code.md) before you start. All rules there apply. Do the phases in order. Inside a phase, do the tasks in order. Each task is one commit or a small set of commits (GIT-02). Each bug fix comes with a test that fails before the fix (TEST-03). Name the requirement, decision, and rule IDs in each commit body (GIT-03).

In this plan, "the review" is [review-2026-10-28.md](review-2026-10-28.md). An item reference such as "3.2.4" names section 3.2, item 4 of the review.

## 1. How to work

1. Use only the connected iPad Pro 11-inch (M4) with the UDID `00008132-000018993E8B801C`, in Release. Never use a simulator (learned rule 1 of `AGENTS.md`). Keep the iPad unlocked during a device run.
2. Compare two builds only in alternating pairs in the same hour (D-177 point 4). Build the base commit in a worktree under `.build/Base`. Give each result bundle a unique name under `.build/Runs`, and remove no bundle in a loop. The iPad has two performance states: the normal state after a restart, and a slower state. Note the state next to each measure. A compare against the baseline file decides nothing in the slow state (section 7 of the review).
3. Run the Tier A tests on the Mac and `PointerDeviceTests` on the iPad. Do not ask the product owner to accept a failed test (learned rule 2).
4. A change of the frame path runs `make validation` before its commit (D-186).
5. Each task names the item of the review that it closes. If a fix shows that the finding was wrong, say so in the commit body and leave the code.

## 2. Decisions

- D-194: a type with `@unchecked Sendable` and a safety comment can leave its `+Unsafe.swift` file. SAFE-09 says so. No code changes for the rule.
- D-195: one private core per erase record transition in `CanvasContent`. Task 2.1.
- D-196: each session carries its workspace, and a delete removes the sessions of the workspace. Task 2.2.
- D-197: task 4.3 of M10 is closed. The quad limit of 65,536 per frame stays.

## 3. Phases

### Phase 1: correctness, section 3.2 of the review

Each task has a test that fails before the fix (TEST-03). Tasks 1.1 to 1.6 touch stored data or the restore, so they come first.

1. 1.1 (3.2.1) `LibraryMaintenance` dooms a stroke by `modified < ?1` instead of `erased < ?1`, as the other tables do. Test: a stroke erased on day 0, brought back, and erased again on day 35 survives the launch of day 35 and goes on day 65.
2. 1.2 (3.2.2) `SnapshotWriter.writeSnapshotNow()` passes the new name to `removeOldSnapshots(except:)`, and a newest snapshot dated in the future counts as due. Test: a clock that went back past 7 daily snapshots keeps the new file.
3. 1.3 (3.2.3) `SQLiteLibraryRepository.restore` throws `restoreStopped` at a set stop flag, and logs the error of `backup.finish()`. Test: a stopped restore with a failing finish throws `restoreStopped`.
4. 1.4 (3.2.4) `SQLiteLibraryRepository.create(_:)` uses a plain `INSERT`. Test: a second create of the same workspace ID throws, and the first row stays.
5. 1.5 (3.2.5) A load that passes a limit stops at the limit error and reports the count from the count query. `workspaces()` throws `workspaceLimitReached` past the limit. Test: a library with 50,000 rows over the limit reports that count, and a library with one workspace too many throws.
6. 1.6 (3.2.6) `open()` sets an `isOpening` flag before the await of the pre-migration snapshot, and the preconditions of `open()` and `close()` read it. Test: a second `open()` during the await fails its precondition (a test of the flag, not of the crash).
7. 1.7 (3.2.7) `Eraser.changedArea` rounds its range as `partPoints` does. Test: a cut on an exact integer parameter gives an area that holds the control points on both sides.
8. 1.8 (3.2.8) `Eraser`, `StrokeHitTest`, and `EraserPath` grow a bounds once. Test: the candidates of a hit test stay the same for the fixture strokes, and the count of the prefilter falls.
9. 1.9 (3.2.9) `PreviewAtlas.place` allocates the new slot first, then frees the earlier slot of the card. Test: if no slot can go, a card with a smaller preview keeps it.
10. 1.10 (3.2.10) `PreviewLoader.request` gives a dropped request back through the inbox, or its contract says that the loader never drops. Pick the form that the code of the loader already supports, and test it.
11. 1.11 (3.2.11) `GlyphAtlas.drop` ends the scope of the page copy before the release of the empty heaps. Test: the memory of the page table after a drop of the last page of a heap.
12. 1.12 (3.2.12) `GlyphPageTable` pushes the placement index back after a failed buffer. Test: a failed buffer leaves the free indices as they were.
13. 1.13 (3.2.13) `RenderEngine.tryGiveParentImage` reads a completion flag of the freeze command buffer, or its contract says that the caller calls it after the flight. If the test can set the flag, pick the flag. Else pick the contract line.
14. 1.14 (3.2.14) `RenderThread.setDrawableSize` captures `self` weakly, as `wake()` does (D-194).
15. 1.15 (3.2.15) `leaveByPinch()` gets the guards of `leave()` on `isLibraryBusy` and `isSwapping`. Test: a pinch leave during a restore starts no load.
16. 1.16 (3.2.16) The export checks `Task.isCancelled` before `finishExport`. Test: an export that ends after its controller left the screen presents nothing.
17. 1.17 (3.2.17) `InkPoints.init` checks that the points are finite, and the contracts name it. Test: a point with an infinite coordinate fails the precondition of `InkPoints`.
18. 1.18 (3.2.18) `Card.init` maps an empty title to `nil`. Test: a card made with an empty title has no title, and the row holds `NULL`.
19. 1.19 (3.2.19) `PresentedHandoffs.attach` clears an entry with the same drawable identifier. Test: a handoff of a drawable that is never presented does not fire for a later drawable with the same identifier.

Done when: each item has its test, `make check` passes on the Mac, and the full `PointerDeviceTests` passes on the iPad.

### Phase 2: the decisions

1. 2.1 (D-195) `CanvasContent` gets a private core for the remove and one for the restore of a stroke. `remove(_:at:)`, `restore(_:at:)`, and the batch forms call them. The single forms keep their preconditions and return values. The batch forms keep the `ChangeLog` and the rows. The record invariant test of data-model.md section 9 and the Model tests pass without a change. `EraseUndoPerformanceTests` and `EraseStepPerformanceTests` show no change over 10 % in pairs.
2. 2.2 (D-196) `CanvasSessions.save` takes the workspace of the session, and `remove(workspace:)` drops the sessions of that workspace. `AppComposition.forgetSession(of:)` calls it. architecture.md section 5 (M-03) gains one sentence. Test: a deleted workspace with two card canvases leaves no session.

Done when: both tasks are in, and the documents name them.

### Phase 3: performance, section 3.3 of the review

Measure each item in alternating pairs on the iPad before and after (D-177 point 4). If the pair shows a gain, or if the change removes an allocation on the frame path (PERF-01), keep the change. Else drop it. Items 3.1 to 3.6 are on the frame path.

1. 3.1 (3.3.1) The page lists of a glyph run in an inline form, so a build allocates no array. Measure: `TextBuildPerformanceTests` and `TextPassAllocationTests`.
2. 3.2 (3.3.2) `TextEncoder+StoredDraw` keeps a `[any MTLResource]` list in the store. Measure: `TextPassPerformanceTests`.
3. 3.3 (3.3.3) `room(for:)` returns the entry, so a pass looks each item up once. Measure: `TextPassPerformanceTests`.
4. 3.4 (3.3.4) The stored text builds take `configuration.buildTimeBudget`. Test: a configuration with a budget of 1 ms builds in frames of at most 1 ms.
5. 3.5 (3.3.5) A full glyph atlas logs once per frame. Test: the log count of a frame with 100 glyphs over the atlas.
6. 3.6 (3.3.6) `InkView.layoutSubviews` posts the viewport only after a change of it. Test: a layout with the same size draws no frame.
7. 3.7 (3.3.7 to 3.3.12) The items outside the frame path: the arena growth signpost, the spline reserve, and the part build order of `StrokeSplitter`. Also the double layout of `PDFExporter`, the double copy of `StrokeFactory`, and the public test-only members. If a pair or an allocation count shows a gain, do the item. Else leave it. 3.3.12 also closes the SCOPE-01 gap of `make unused`.

Done when: each kept change has its pair in the commit body, and `make perf-compare` passes in the normal state of the iPad.

### Phase 4: code quality, section 3.4 of the review

1. 4.1 (3.4.1) The card state leaves `TextEditing` for a holder of its own, or the type gets a name that says what it holds.
2. 4.2 (3.4.2) One generic helper over `sortKey` and `id` replaces the four copies in `CanvasFeature`: the sort key helpers, `isAbove`, and the drag delta math.
3. 4.3 (3.4.3) `Rect` in `Geometry` gains `union` and `intersection`, with tests, and the six `dirtyArea` sites use them.
4. 4.4 (3.4.4) The glyph placement loop and the corner computation exist once each.
5. 4.5 (3.4.5) The factor 1.5 of the glyph row height and the texture limit 16,384 get names (STYLE-03).
6. 4.6 (3.4.6) The limit messages of `CanvasStrings` interpolate `Limits`, as `WorkspaceStrings` does. The String Catalog changes with them.
7. 4.7 (3.4.7) A token `DesignSystem.Color.ink` replaces the raw white of `TextEditView` and `PenTool` (D-38, D-15).

Items 3.4.8 to 3.4.12 wait: the contract lines, the trivial checks, the split of `FrameRenderer`, the getter of `RestoreStop`, and the two alert paths. The split of `FrameRenderer` comes with the next feature that touches it.

Done when: `make check` passes, the snapshot tests pass without a new reference, and the allocation tests pass.

### Phase 5: the close

1. 5.1 `make check` on the Mac and the iPad, `make validation`, and `make coverage` (TEST-02).
2. 5.2 `make perf-compare` in the normal state of the iPad, after a restart. If a sample fails, run the sample in pairs against the commit before the phase that changed it, and fix the cause. Record no new baseline in the slow state (D-177 point 6).
3. 5.3 plan.md gets the M11 row with the date and the notes. This plan leaves `docs/` as the earlier plans did, and decisions.md says where git history holds it.

## 4. Acceptance criteria

1. Every item of section 3.2 and items 1 to 7 of section 3.4 of the review is closed. The close is a test, or a commit body that says why the finding was wrong.
2. `make perf-compare` passes against the baseline of f8e4c0b in the normal state of the iPad.
3. Coverage meets TEST-02.
