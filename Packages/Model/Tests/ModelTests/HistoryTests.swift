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
}
