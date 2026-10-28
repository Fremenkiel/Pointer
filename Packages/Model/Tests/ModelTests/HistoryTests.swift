import Testing

@testable import Model

@Suite("History")
struct HistoryTests {
    @Test(
        "The history keeps at most the history depth of steps",
        arguments: [0, 1, Limits.maxHistoryDepth, Limits.maxHistoryDepth + 1]
    )
    func depth(stepCount: Int) throws {
        var rig = CommandRig()
        var history = History()
        for _ in 0..<stepCount {
            _ = try history.perform(
                AddStroke(strokes: [rig.stroke()]),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        let kept = min(stepCount, Limits.maxHistoryDepth)
        #expect(history.undoSteps.count == kept)
        #expect(history.canUndo == (kept > 0))
        for _ in 0..<kept {
            _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        }
        #expect(!history.canUndo)
        #expect(history.redoSteps.count == kept)
        #expect(try history.undo(on: &rig.content, clock: &rig.factory.clock).isEmpty)
        #expect(rig.content.strokes.count == stepCount - kept)
    }

    @Test("Undo and redo move one step between the lists")
    func undoRedo() throws {
        var rig = CommandRig()
        var history = History()
        let command = AddStroke(strokes: [rig.stroke()])
        _ = try history.perform(command, on: &rig.content, clock: &rig.factory.clock)
        _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        #expect(rig.content.strokes.isEmpty)
        #expect(history.canRedo)
        _ = try history.redo(on: &rig.content, clock: &rig.factory.clock)
        #expect(rig.content.strokes.count == 1)
        #expect(!history.canRedo)
        #expect(history.undoSteps.count == 1)
        #expect(try history.redo(on: &rig.content, clock: &rig.factory.clock).isEmpty)
    }

    @Test("A new command clears the redo list")
    func newCommandClearsRedo() throws {
        var rig = CommandRig()
        var history = History()
        for _ in 0..<2 {
            _ = try history.perform(
                AddStroke(strokes: [rig.stroke()]),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        #expect(history.canRedo)
        _ = try history.perform(
            AddStroke(strokes: [rig.stroke()]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        #expect(!history.canRedo)
        #expect(history.undoSteps.count == 2)
    }

    @Test("A command that fails keeps the history as it was")
    func failedSteps() throws {
        var rig = CommandRig()
        var history = History()
        let stroke = try rig.load(1)[0]
        #expect(throws: CommandError.strokeAlreadyLive(stroke.id)) {
            try history.perform(
                AddStroke(strokes: [stroke]),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        #expect(!history.canUndo)
        let erase = EraseStrokes(removed: [stroke], parts: [])
        _ = try history.perform(erase, on: &rig.content, clock: &rig.factory.clock)
        _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        _ = try rig.apply(erase)
        #expect(throws: CommandError.strokeNotLive(stroke.id)) {
            try history.redo(on: &rig.content, clock: &rig.factory.clock)
        }
        #expect(history.canRedo)
        #expect(history.undoSteps.isEmpty)
    }

    /// A stroke of `count` control points that share `points`.
    private static func stroke(
        _ rig: inout CommandRig,
        points: InkPoints
    ) -> Stroke {
        Stroke(
            id: rig.factory.identifiers.make(StrokeID.self),
            canvasID: Fixtures.canvas,
            created: rig.factory.clock.now(),
            origin: .zero,
            width: 2,
            points: points
        )
    }

    private static func points(_ count: Int) -> InkPoints {
        InkPoints((0..<count).map { InkPoint(x: Float($0), y: 0, force: 1, time: 0) })
    }

    @Test(
        "The history keeps its byte budget and drops the oldest step past it (D-76, D-183)",
        arguments: [0, 1]
    )
    func byteBudget(over: Int) throws {
        var rig = CommandRig()
        let stepBytes = HistoryCost.bytes(ofStroke: 10)
        var history = History(byteBudget: 10 * stepBytes)
        var first: StrokeID?
        for _ in 0..<9 {
            let stroke = Self.stroke(&rig, points: Self.points(10))
            first = first ?? stroke.id
            _ = try history.perform(
                AddStroke(strokes: [stroke]),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        // The last step takes the history to the bound, or to the bound plus one.
        let performed = try history.perform(
            AddStroke(strokes: [Self.stroke(&rig, points: Self.points(10 + over))]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        let lastBytes = HistoryCost.bytes(ofStroke: 10 + over)
        #expect(history.byteCount == (over == 0 ? 10 * stepBytes : 8 * stepBytes + lastBytes))
        #expect(history.undoSteps.count == (over == 0 ? 10 : 9))
        var dropped: [StrokeID] = []
        for step in performed.dropped {
            step.forEachHeldStroke { dropped.append($0) }
        }
        #expect(dropped == (over == 0 ? [] : [first].compactMap { $0 }))
    }

    @Test("The default byte budget is the limit of one canvas")
    func defaultBudget() {
        #expect(History().byteBudget == Limits.maxHistoryBytesPerCanvas)
    }

    @Test("500 steps of 300,000 points each keep at most the byte budget (M-01, D-183)")
    func manyLargeSteps() throws {
        var rig = CommandRig()
        var history = History()
        // The strokes share their points, so the test holds them once (data-model.md 7.4).
        let shared = Self.points(15_000)
        for _ in 0..<500 {
            let strokes = (0..<20).map { _ in Self.stroke(&rig, points: shared) }
            _ = try history.perform(
                AddStroke(strokes: strokes),
                on: &rig.content,
                clock: &rig.factory.clock
            )
        }
        let stepBytes = 20 * HistoryCost.bytes(ofStroke: 15_000)
        #expect(history.byteCount <= Limits.maxHistoryBytesPerCanvas)
        #expect(history.undoSteps.count == Limits.maxHistoryBytesPerCanvas / stepBytes)
    }

    @Test("Dropped steps lose the records of their strokes, and held strokes keep them (M-02)")
    func droppedRecords() throws {
        var rig = CommandRig()
        // The budget holds two steps of one stroke of 2 points.
        var history = History(byteBudget: 2 * HistoryCost.bytes(ofStroke: 2))
        let first = Self.stroke(&rig, points: Self.points(2))
        _ = try history.perform(
            AddStroke(strokes: [first]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        // The erase holds the stroke too, so the drop of the add keeps its record.
        let erase = try history.perform(
            EraseStrokes(removed: [first], parts: []),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        #expect(erase.dropped.isEmpty)
        let second = Self.stroke(&rig, points: Self.points(2))
        let add = try history.perform(
            AddStroke(strokes: [second]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        #expect(add.dropped.count == 1)
        #expect(history.unheldStrokeIDs(of: add.dropped).isEmpty)
        // The undo of the second add gives it a record, and a new step clears the redo list.
        _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        #expect(rig.content.erased[second.id] != nil)
        let third = try history.perform(
            AddStroke(strokes: [Self.stroke(&rig, points: Self.points(2))]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        rig.content.forgetRecords(of: history.unheldStrokeIDs(of: third.dropped))
        #expect(rig.content.erased[second.id] == nil)
        #expect(rig.content.erased[first.id] != nil)
    }

    @Test("A stroke that two dropped steps hold is reported once")
    func unheldStrokeOnce() throws {
        var rig = CommandRig()
        var history = History()
        let stroke = Self.stroke(&rig, points: Self.points(2))
        _ = try history.perform(
            AddStroke(strokes: [stroke]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        _ = try history.perform(
            EraseStrokes(removed: [stroke], parts: []),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        let dropped = history.dropOldest(toFit: 0)
        #expect(dropped.count == 2)
        #expect(history.unheldStrokeIDs(of: dropped) == [stroke.id])
    }

    @Test("A dropped step frees no stroke that a step of the redo list still holds (D-76)")
    func redoStepHoldsStroke() throws {
        var rig = CommandRig()
        var history = History()
        let stroke = Self.stroke(&rig, points: Self.points(2))
        _ = try history.perform(
            AddStroke(strokes: [stroke]),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        _ = try history.perform(
            EraseStrokes(removed: [stroke], parts: []),
            on: &rig.content,
            clock: &rig.factory.clock
        )
        _ = try history.undo(on: &rig.content, clock: &rig.factory.clock)
        let redo = try #require(history.redoSteps.first)
        // The budget keeps the erase on the redo list and drops the add from the undo list.
        let dropped = history.dropOldest(toFit: redo.heldByteCount)
        #expect(dropped.count == 1)
        #expect(history.unheldStrokeIDs(of: dropped).isEmpty)
    }
}
