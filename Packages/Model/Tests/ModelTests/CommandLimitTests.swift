import Testing

@testable import Model

@Suite("Canvas commands at the stroke limit")
struct CommandLimitTests {
    @Test("An erase passes the stroke limit, and the pen then refuses a stroke (D-71)")
    func eraseAtLimit() throws {
        var rig = CommandRig()
        let loaded = try rig.load(Limits.maxStrokesPerCanvas)
        let erase = EraseStrokes(removed: [loaded[0]], parts: [rig.stroke(), rig.stroke()])
        _ = try rig.apply(erase)
        #expect(rig.content.strokes.count == Limits.maxStrokesPerCanvas + 1)
        #expect(throws: CommandError.strokeLimitReached) {
            try rig.apply(AddStroke(strokes: [rig.stroke()]))
        }
        _ = try rig.revert(erase)
        #expect(rig.content.strokes.count == Limits.maxStrokesPerCanvas)
        let full = EraseStrokes(removed: [loaded[1], loaded[2]], parts: [])
        _ = try rig.apply(full)
        _ = try rig.apply(AddStroke(strokes: [rig.stroke(), rig.stroke()]))
        #expect(throws: ModelError.strokeLimitReached) {
            try rig.content.restore(loaded[1], at: rig.factory.clock.now(), ignoringLimit: false)
        }
        // An undo takes the canvas up to the bound after an erase (D-159).
        _ = try rig.revert(full)
        #expect(rig.content.strokes.count == Limits.maxStrokesPerCanvas + 2)
    }

    @Test("The undo of a whole-stroke erase after a cutting erase at the limit works (D-159)")
    func undoAfterCuttingErase() throws {
        var rig = CommandRig()
        let loaded = try rig.load(Limits.maxStrokesPerCanvas)
        _ = try rig.apply(EraseStrokes(removed: [loaded[0]], parts: [rig.stroke(), rig.stroke()]))
        let whole = EraseStrokes(removed: [loaded[1]], parts: [])
        _ = try rig.apply(whole)
        #expect(rig.content.strokes.count == Limits.maxStrokesPerCanvas)
        _ = try rig.revert(whole)
        #expect(rig.content.strokes.count == Limits.maxStrokesPerCanvas + 1)
    }

    @Test("An undo that passes the bound after an erase is refused (D-73, D-159)")
    func undoPastTheBound() throws {
        var rig = CommandRig()
        let loaded = try rig.load(Limits.maxStrokesPerCanvas)
        for _ in Limits.maxStrokesPerCanvas..<Limits.maxStrokesAfterErase - 1 {
            try rig.content.add(rig.stroke(), limit: Limits.maxStrokesAfterErase)
        }
        let whole = EraseStrokes(removed: [loaded[0], loaded[1]], parts: [])
        _ = try rig.apply(whole)
        let parts = [rig.stroke(), rig.stroke(), rig.stroke(), rig.stroke()]
        _ = try rig.apply(EraseStrokes(removed: [loaded[2]], parts: parts))
        #expect(rig.content.strokes.count == Limits.maxStrokesAfterErase)
        #expect(throws: CommandError.strokeLimitReached) {
            try rig.revert(whole)
        }
        #expect(rig.content.strokes.count == Limits.maxStrokesAfterErase)
    }

    @Test(
        "An erase never passes the bound after an erase, and a load takes strokes up to it (D-73)"
    )
    func boundAfterErase() throws {
        var rig = CommandRig()
        let loaded = try rig.load(Limits.maxStrokesPerCanvas)
        for _ in Limits.maxStrokesPerCanvas..<(Limits.maxStrokesAfterErase - 1) {
            try rig.content.add(rig.stroke(), limit: Limits.maxStrokesAfterErase)
        }
        #expect(throws: ModelError.strokeLimitReached) {
            try rig.content.add(rig.stroke(), limit: Limits.maxStrokesPerCanvas)
        }
        let tooMany = EraseStrokes(
            removed: [loaded[0]],
            parts: [rig.stroke(), rig.stroke(), rig.stroke()]
        )
        #expect(throws: CommandError.strokeLimitReached) {
            try rig.apply(tooMany)
        }
        _ = try rig.apply(EraseStrokes(removed: [loaded[0]], parts: [rig.stroke(), rig.stroke()]))
        #expect(rig.content.strokes.count == Limits.maxStrokesAfterErase)
        _ = try rig.apply(EraseStrokes(removed: [loaded[1]], parts: []))
        #expect(rig.content.strokes.count == Limits.maxStrokesAfterErase - 1)
    }
}
